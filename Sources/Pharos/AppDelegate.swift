import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let sleepGuard = SleepGuard()
    private let updater = UpdaterController()
    private var statusItem: NSStatusItem?
    private var settingsWindowController: SettingsWindowController?
    private var expiryDate: Date?
    private var expiryTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpMainMenu()
        observePreferenceChanges()
        updateStatusItemVisibility()

        if AppPreferences.activatesOnLaunch {
            setAwake(true)
        }
        if CommandLine.arguments.contains("--settings") {
            openSettings()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        /* The assertion dies with the process anyway; releasing explicitly
           just keeps `pmset -g assertions` tidy during a graceful quit. */
        sleepGuard.deactivate()
    }

    /* Launching the app again while it's already running sends "reopen" to
       the live instance. With the menu bar icon hidden this is the only way
       back into the UI, so surface Settings (which also puts the app in the
       Dock via updateActivationPolicy). */
    func applicationShouldHandleReopen(
        _ sender: NSApplication, hasVisibleWindows: Bool
    ) -> Bool {
        if AppPreferences.isMenuBarIconHidden {
            openSettings()
        }
        return false
    }

    // MARK: - Keep awake

    /* Single entry point for every state change: toggle, timer preset,
       timer expiry, and launch activation all land here, so the expiry
       timer and the icon can never drift out of sync with the assertion. */
    private func setAwake(_ on: Bool, for duration: TimeInterval? = nil) {
        expiryTimer?.invalidate()
        expiryTimer = nil
        expiryDate = nil

        if on {
            sleepGuard.activate(keepingDisplayAwake: AppPreferences.keepsDisplayAwake)
            if sleepGuard.isActive, let duration {
                expiryDate = Date(timeIntervalSinceNow: duration)
                let timer = Timer(timeInterval: duration, repeats: false) { [weak self] _ in
                    self?.setAwake(false)
                }
                RunLoop.main.add(timer, forMode: .common)
                expiryTimer = timer
            }
        } else {
            sleepGuard.deactivate()
        }
        updateStatusIcon()
    }

    @objc private func toggleAwake() {
        setAwake(!sleepGuard.isActive)
    }

    @objc private func keepAwakeFor(_ sender: NSMenuItem) {
        setAwake(true, for: TimeInterval(sender.tag))
    }

    // MARK: - Status item

    private func updateStatusItemVisibility() {
        if AppPreferences.isMenuBarIconHidden {
            if let statusItem {
                NSStatusBar.system.removeStatusItem(statusItem)
            }
            statusItem = nil
        } else if statusItem == nil {
            setUpStatusItem()
        }
        updateActivationPolicy()
    }

    private func setUpStatusItem() {
        /* A fixed length instead of squareLength: square items are as wide
           as the menu bar is tall, which pads a ~18pt symbol with a lot of
           dead space. 20pt hugs the icon while keeping its natural size. */
        let item = NSStatusBar.system.statusItem(withLength: 20)
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        /* Left click toggles, right click opens the menu — the standard
           idiom for toggle-style menu bar apps (Caffeine and friends). */
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
        updateStatusIcon()
    }

    private func updateStatusIcon() {
        let style = AppPreferences.menuBarIconStyle
        statusItem?.button?.image = NSImage(
            systemSymbolName: sleepGuard.isActive
                ? style.activeSymbolName : style.idleSymbolName,
            accessibilityDescription: sleepGuard.isActive
                ? "Pharos — keeping the Mac awake" : "Pharos"
        )
    }

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        let wantsMenu = event.map {
            $0.type == .rightMouseUp || $0.modifierFlags.contains(.control)
        } ?? true
        wantsMenu ? showStatusMenu() : toggleAwake()
    }

    /* The menu is attached only for the duration of one tracking session:
       a permanently-assigned menu would swallow left clicks, killing the
       click-to-toggle behavior. Built fresh each time so the checkmark and
       the countdown are current. */
    private func showStatusMenu() {
        guard let item = statusItem else { return }

        let menu = NSMenu()
        menu.delegate = self

        let version =
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        let about = NSMenuItem(title: "Pharos \(version)", action: nil, keyEquivalent: "")
        about.isEnabled = false
        menu.addItem(about)
        menu.addItem(.separator())

        let toggle = NSMenuItem(
            title: "Keep Mac Awake", action: #selector(toggleAwake), keyEquivalent: "")
        toggle.target = self
        toggle.state = sleepGuard.isActive ? .on : .off
        menu.addItem(toggle)

        if sleepGuard.isActive, let expiryDate {
            let label = AwakeCountdown.remainingLabel(
                seconds: expiryDate.timeIntervalSinceNow)
            menu.addItem(NSMenuItem(title: "Off in \(label)", action: nil, keyEquivalent: ""))
        }

        let durations = NSMenu()
        for duration in AwakeDuration.allCases {
            let durationItem = NSMenuItem(
                title: duration.title, action: #selector(keepAwakeFor(_:)), keyEquivalent: "")
            durationItem.target = self
            durationItem.tag = duration.rawValue
            durations.addItem(durationItem)
        }
        let durationsItem = NSMenuItem(title: "Keep Awake For", action: nil, keyEquivalent: "")
        durationsItem.submenu = durations
        menu.addItem(durationsItem)

        menu.addItem(.separator())
        let settingsItem = NSMenuItem(
            title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(updater.makeMenuItem())
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(title: "Quit Pharos", action: #selector(quit), keyEquivalent: "q"))

        item.menu = menu
        item.button?.performClick(nil)
    }

    func menuDidClose(_ menu: NSMenu) {
        statusItem?.menu = nil
    }

    // MARK: - Menus & windows

    /* An accessory app has no visible menu bar, but ⌘-key equivalents are
       still dispatched through the main menu — without one, ⌘W/⌘Q do
       nothing in the settings window. The menu also becomes visible for
       real whenever the app temporarily joins the Dock (regular policy). */
    private func setUpMainMenu() {
        let appMenu = NSMenu()
        let settingsItem = NSMenuItem(
            title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(updater.makeMenuItem())
        appMenu.addItem(.separator())
        appMenu.addItem(
            NSMenuItem(
                title: "Quit Pharos",
                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(
            NSMenuItem(
                title: "Close Window",
                action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        windowMenu.addItem(
            NSMenuItem(
                title: "Minimize",
                action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))

        let mainMenu = NSMenu()
        for submenu in [appMenu, windowMenu] {
            let item = NSMenuItem()
            item.submenu = submenu
            mainMenu.addItem(item)
        }
        NSApp.mainMenu = mainMenu
    }

    private func observePreferenceChanges() {
        NotificationCenter.default.addObserver(
            forName: AppPreferences.changed, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.updateStatusItemVisibility()
            self.updateStatusIcon()
            /* Flipping "keep display awake" while active swaps the assertion
               type in place; the expiry timer is untouched. */
            if self.sleepGuard.isActive {
                self.sleepGuard.activate(
                    keepingDisplayAwake: AppPreferences.keepsDisplayAwake)
            }
        }
    }

    private var isSettingsWindowVisible: Bool {
        settingsWindowController?.window?.isVisible == true
    }

    /* Dock presence: the app normally stays invisible (accessory policy),
       but while the menu bar icon is hidden AND Settings is open there would
       be no sign the app is running — so it joins the Dock for the duration
       and leaves again when the settings window closes. */
    private func updateActivationPolicy() {
        let wantsDock = AppPreferences.isMenuBarIconHidden && isSettingsWindowVisible
        let policy: NSApplication.ActivationPolicy = wantsDock ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
        /* Flipping the policy can drop activation; keep Settings in front. */
        if isSettingsWindowVisible {
            NSApp.activate(ignoringOtherApps: true)
            settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(updater: updater)
            if let window = settingsWindowController?.window {
                NotificationCenter.default.addObserver(
                    forName: NSWindow.willCloseNotification, object: window, queue: .main
                ) { [weak self] _ in
                    /* isVisible is still true inside willClose; re-evaluate
                       (and leave the Dock) on the next runloop cycle. */
                    DispatchQueue.main.async { self?.updateActivationPolicy() }
                }
            }
        }
        /* Accessory apps don't come forward on their own — activate first or
           the window opens behind the current app. */
        NSApp.activate(ignoringOtherApps: true)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        updateActivationPolicy()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
