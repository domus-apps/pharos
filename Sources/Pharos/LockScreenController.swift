import AppKit
import Carbon.HIToolbox
import IOKit.pwr_mgt
import LocalAuthentication

/* Locked Awake: cover every display with a black shield, swallow all input,
   and keep the Mac awake — for stepping away while background work (an AI
   session, a build) keeps running. Return or a click starts Touch ID with
   the automatic password fallback (LocalAuthentication's
   .deviceOwnerAuthentication); success drops the shields.

   Security model, stated plainly: this is a privacy barrier against casual
   physical access, not a security boundary. It cannot stop `pkill Pharos`
   (which harmlessly drops the shields), synthetic events posted through the
   Accessibility API, or remote access. For real security, lock the session.

   The shields sit at CGShieldingWindowLevel — above Spotlight, notification
   banners, and screen savers. All of them accept clicks (a click anywhere
   begins authentication; leaving any screen click-through would let clicks
   land on whatever is underneath). Keyboard and scroll events are swallowed
   by an active CGEvent tap, which is why this feature — alone in Pharos —
   needs the Accessibility permission, and asks for it only when used. */
final class LockScreenController {
    private(set) var isLocked = false
    var onStateChange: (() -> Void)?

    /* The lock holds its own assertion so the user's regular keep-awake
       toggle is untouched by locking and unlocking. Display sleep is
       prevented (and user activity declared, below) so the system's idle
       screen saver / auto-lock never fights the shields. */
    private let awakeGuard = SleepGuard()
    private var userActivityTimer: Timer?
    private var userActivityID: IOPMAssertionID = 0

    private var shields: [ShieldWindow] = []
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isAuthenticating = false
    private var authContext: LAContext?
    private var shieldRebuild: DispatchWorkItem?
    private var observers: [any NSObjectProtocol] = []

    private static let shieldLevel = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))

    // MARK: - Permission

    /* An active event tap requires the Accessibility grant. There is no
       usable lock without it: shields that can't swallow ⌘Tab are theater. */
    static var hasPermission: Bool { AXIsProcessTrusted() }

    /* The system prompt appears only on the very first ask; afterwards
       macOS stays silent, so callers also offer the settings deep link. */
    static func promptForPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    // MARK: - Lock / unlock

    /// Returns false when the lock can't be established (no Accessibility
    /// grant, or the event tap failed) — never hold a screen you can't
    /// defend.
    @discardableResult
    func lock() -> Bool {
        guard !isLocked else { return true }
        guard Self.hasPermission else { return false }

        buildShields()
        guard startTap() else {
            tearDownShields()
            return false
        }

        awakeGuard.activate(keepingDisplayAwake: true)
        startUserActivityRefresh()
        installObservers()
        NSApp.activate(ignoringOtherApps: true)
        NSCursor.setHiddenUntilMouseMoves(true)

        isLocked = true
        onStateChange?()
        return true
    }

    /// For applicationWillTerminate: drop everything unconditionally.
    func teardown() {
        guard isLocked else { return }
        authContext?.invalidate()
        unlock()
    }

    private func unlock() {
        guard isLocked else { return }
        isLocked = false
        stopTap()
        tearDownShields()
        removeObservers()
        stopUserActivityRefresh()
        awakeGuard.deactivate()
        onStateChange?()
    }

    // MARK: - Shields

    private func buildShields() {
        tearDownShields()
        for screen in NSScreen.screens {
            let shield = ShieldWindow(
                screen: screen, showsHint: screen == NSScreen.screens.first)
            shield.onInteraction = { [weak self] in self?.beginAuthentication() }
            shield.level = Self.shieldLevel
            shield.orderFrontRegardless()
            shields.append(shield)
        }
    }

    private func tearDownShields() {
        /* orderOut, not close: shields are reused conceptually and close()
           mid-display is where AppKit crashes live. */
        for shield in shields {
            shield.orderOut(nil)
            shield.contentView = nil
        }
        shields = []
    }

    private func setShieldLevel(_ level: NSWindow.Level) {
        for shield in shields {
            shield.level = level
        }
    }

    // MARK: - Input tap

    private func startTap() -> Bool {
        guard eventTap == nil else { return true }
        /* Keyboard and scroll only — mouse events stay live so clicks reach
           the shields (which cover everything, so they can't reach anything
           else). Return doubles as the authentication trigger. */
        let mask =
            (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.scrollWheel.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let controller = Unmanaged<LockScreenController>.fromOpaque(context)
                .takeUnretainedValue()
            return controller.handleTap(type: type, event: event)
        }
        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: CGEventMask(mask),
                callback: callback,
                userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return false }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        return true
    }

    private func stopTap() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        runLoopSource = nil
        eventTap = nil
    }

    private func handleTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            /* The system pauses taps it thinks are stuck; resume. */
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)

        case .keyDown
        where [kVK_Return, kVK_Escape]
            .contains(Int(event.getIntegerValueField(.keyboardEventKeycode))):
            DispatchQueue.main.async { [weak self] in self?.beginAuthentication() }
            return nil

        default:
            /* Swallowed. ⌘Tab, ⌘Q, Spotlight, typing — none of it lands. */
            return nil
        }
    }

    // MARK: - Authentication

    private func beginAuthentication() {
        guard isLocked, !isAuthenticating else { return }
        isAuthenticating = true

        /* The Touch ID / password dialog lives below the shielding level:
           drop the shields to just above normal windows and lift the tap so
           the user can type. Every exit path below restores both. */
        setShieldLevel(.statusBar)
        stopTap()

        let context = LAContext()
        authContext = context
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            NSLog("Pharos: device owner authentication unavailable: \(String(describing: error))")
            finishAuthentication(unlocked: false)
            return
        }

        /* Detached on purpose: evaluating on the main actor deadlocks —
           the system dialog itself needs the main thread. */
        Task.detached {
            let unlocked =
                (try? await context.evaluatePolicy(
                    .deviceOwnerAuthentication,
                    localizedReason: "unlock the screen it is covering")) ?? false
            await MainActor.run { [weak self] in
                self?.finishAuthentication(unlocked: unlocked)
            }
        }
    }

    private func finishAuthentication(unlocked: Bool) {
        authContext = nil
        isAuthenticating = false
        guard isLocked else { return }
        if unlocked {
            unlock()
        } else {
            reassertShield()
        }
    }

    /* Raise the shields and restart the tap — after a failed auth, a wake,
       or a session switch. If the tap can't come back, force-unlock rather
       than hold a screen that no longer swallows input. */
    private func reassertShield() {
        guard isLocked, !isAuthenticating else { return }
        setShieldLevel(Self.shieldLevel)
        for shield in shields {
            shield.orderFrontRegardless()
        }
        if !startTap() {
            NSLog("Pharos: event tap lost while locked; unlocking")
            unlock()
            return
        }
        NSCursor.setHiddenUntilMouseMoves(true)
    }

    // MARK: - Keeping the system on our screen

    /* The display-sleep assertion alone doesn't stop the idle screen saver
       or auto-lock; periodically declared user activity does. */
    private func startUserActivityRefresh() {
        declareUserActivity()
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            self?.declareUserActivity()
        }
        RunLoop.main.add(timer, forMode: .common)
        userActivityTimer = timer
    }

    private func stopUserActivityRefresh() {
        userActivityTimer?.invalidate()
        userActivityTimer = nil
    }

    private func declareUserActivity() {
        IOPMAssertionDeclareUserActivity(
            "Pharos is holding the lock screen" as CFString,
            kIOPMUserActiveLocal, &userActivityID)
    }

    // MARK: - Guards

    private func installObservers() {
        removeObservers()
        let workspace = NSWorkspace.shared.notificationCenter

        /* Wake and session return can drop both the tap and window order. */
        for name in [
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification,
        ] {
            observers.append(
                workspace.addObserver(forName: name, object: nil, queue: .main) {
                    [weak self] _ in
                    self?.reassertShield()
                })
        }

        /* Fast user switching mid-auth: cancel the dialog and re-arm. */
        observers.append(
            workspace.addObserver(
                forName: NSWorkspace.sessionDidResignActiveNotification, object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.authContext?.invalidate()
            })

        /* Displays coming and going: rebuild the whole shield set, debounced
           because one hardware change publishes several notifications. */
        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self, self.isLocked else { return }
                self.shieldRebuild?.cancel()
                let work = DispatchWorkItem { [weak self] in
                    guard let self, self.isLocked, !self.isAuthenticating else { return }
                    self.buildShields()
                }
                self.shieldRebuild = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
            })
    }

    private func removeObservers() {
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
        observers = []
    }
}

// MARK: - Shield window

/* One black window covering one screen. Borderless windows refuse key
   status by default; accepting it keeps the covered app frontmost so the
   cursor stays hidden and clicks are unquestionably ours. */
private final class ShieldWindow: NSWindow {
    var onInteraction: (() -> Void)? {
        get { (contentView as? ShieldView)?.onInteraction }
        set { (contentView as? ShieldView)?.onInteraction = newValue }
    }

    init(screen: NSScreen, showsHint: Bool) {
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false)
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = ShieldView(showsHint: showsHint)
    }

    override var canBecomeKey: Bool { true }
}

/* Black, with (on the main display) a barely-there lock glyph and hint —
   enough that a passer-by understands the machine is intentionally covered,
   quiet enough to disappear on an idle screen. */
private final class ShieldView: NSView {
    var onInteraction: (() -> Void)?
    private let showsHint: Bool

    init(showsHint: Bool) {
        self.showsHint = showsHint
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        guard showsHint else { return }

        let glyph = NSImageView(
            image: NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "locked")?
                .withSymbolConfiguration(.init(pointSize: 26, weight: .regular)) ?? NSImage())
        glyph.contentTintColor = NSColor.white.withAlphaComponent(0.22)

        let hint = NSTextField(
            labelWithString: "Press Return, Esc, or click — Touch ID or password to unlock")
        hint.font = .systemFont(ofSize: 13)
        hint.textColor = NSColor.white.withAlphaComponent(0.25)

        let stack = NSStackView(views: [glyph, hint])
        stack.orientation = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func mouseDown(with event: NSEvent) {
        onInteraction?()
    }
}
