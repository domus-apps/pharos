import AppKit

/* First-run onboarding: what Pharos is and how it's driven — no permission
   gate, since keeping the Mac awake needs none. The window has no close
   button; the only way out is the Start button, and completion is
   persisted only at that click, so quitting (or force-quitting)
   mid-onboarding brings the onboarding back on the next launch. */
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    private let onComplete: () -> Void

    private lazy var startButton = NSButton(
        title: "Start Using Pharos", target: self, action: #selector(start))

    init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete

        /* No .closable: the traffic-light close button never appears. */
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.delegate = self
        window.contentView = makeContent()
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /* Closing only via start(). */
    func windowShouldClose(_ sender: NSWindow) -> Bool { false }

    // MARK: - Content

    private func makeContent() -> NSView {
        let title = NSTextField(labelWithString: "Welcome to Pharos")
        title.font = .systemFont(ofSize: 30, weight: .bold)

        let intro = NSTextField(
            wrappingLabelWithString:
                "Pharos keeps your Mac awake from the menu bar. Click the beacon "
                + "to toggle; right-click for timed presets — from 15 minutes to "
                + "8 hours — with a live countdown.")
        intro.font = .systemFont(ofSize: 14)
        intro.textColor = .secondaryLabelColor
        intro.alignment = .center
        intro.preferredMaxLayoutWidth = 470

        let illustration = OnboardingIllustrationView()
        illustration.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            illustration.widthAnchor.constraint(equalToConstant: 480),
            illustration.heightAnchor.constraint(equalToConstant: 180),
        ])

        let hint = NSTextField(
            labelWithString: "Left-click toggles · right-click opens timers and settings")
        hint.font = .systemFont(ofSize: 14)
        hint.textColor = .secondaryLabelColor

        startButton.bezelStyle = .rounded
        startButton.controlSize = .large
        startButton.keyEquivalent = "\r"

        let stack = NSStackView(views: [title, intro, illustration, hint, startButton])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 16
        stack.setCustomSpacing(10, after: title)
        stack.setCustomSpacing(22, after: intro)
        stack.setCustomSpacing(24, after: hint)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 44),
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.bottomAnchor.constraint(
                lessThanOrEqualTo: container.bottomAnchor, constant: -32),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 500),
        ])
        return container
    }

    @objc private func start() {
        window?.delegate = nil
        onComplete()
        close()
    }
}

/* A drawn "screenshot" of Pharos in action: the menu bar with the beacon
   lit, and beneath it the open menu with the toggle checked and a running
   countdown. Drawn (not a bundled image) so it stays crisp at any backing
   scale and needs no resource plumbing. */
private final class OnboardingIllustrationView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let canvas = bounds

        // Backdrop in the app's indigo
        let backdrop = NSBezierPath(roundedRect: canvas, xRadius: 12, yRadius: 12)
        NSGradient(
            starting: NSColor(srgbRed: 0.13, green: 0.1, blue: 0.28, alpha: 1),
            ending: NSColor(srgbRed: 0.06, green: 0.05, blue: 0.14, alpha: 1)
        )?.draw(in: backdrop, angle: -90)

        // Menu bar strip
        let bar = NSRect(x: 12, y: canvas.maxY - 34, width: canvas.width - 24, height: 24)
        NSColor.white.withAlphaComponent(0.12).setFill()
        NSBezierPath(roundedRect: bar, xRadius: 6, yRadius: 6).fill()

        // Neighbor status icons (quiet dots) and the beacon, lit
        for index in 0..<3 {
            let dot = NSRect(
                x: bar.maxX - 110 + CGFloat(index) * 26, y: bar.midY - 4,
                width: 8, height: 8)
            NSColor.white.withAlphaComponent(0.3).setFill()
            NSBezierPath(ovalIn: dot).fill()
        }
        let beaconCenter = NSPoint(x: bar.maxX - 22, y: bar.midY)
        // Glow
        let glow = NSBezierPath(
            ovalIn: NSRect(
                x: beaconCenter.x - 10, y: beaconCenter.y - 10, width: 20, height: 20))
        NSColor.systemYellow.withAlphaComponent(0.35).setFill()
        glow.fill()
        // Beacon dot
        let beacon = NSBezierPath(
            ovalIn: NSRect(
                x: beaconCenter.x - 5, y: beaconCenter.y - 5, width: 10, height: 10))
        NSColor.systemYellow.setFill()
        beacon.fill()

        // The open menu card under the beacon
        let menu = NSRect(x: bar.maxX - 190, y: bar.minY - 106, width: 180, height: 98)
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 10
        shadow.shadowOffset = NSSize(width: 0, height: -4)
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
        NSGraphicsContext.current?.saveGraphicsState()
        shadow.set()
        NSColor(srgbRed: 0.94, green: 0.94, blue: 0.96, alpha: 1).setFill()
        NSBezierPath(roundedRect: menu, xRadius: 9, yRadius: 9).fill()
        NSGraphicsContext.current?.restoreGraphicsState()

        func menuRow(_ text: String, y: CGFloat, checked: Bool, dimmed: Bool) {
            var x = menu.minX + 12
            if checked {
                let check = NSAttributedString(
                    string: "✓",
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                        .foregroundColor: NSColor.black.withAlphaComponent(0.85),
                    ])
                check.draw(at: NSPoint(x: x, y: y))
                x += 14
            }
            let label = NSAttributedString(
                string: text,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11),
                    .foregroundColor: NSColor.black.withAlphaComponent(dimmed ? 0.45 : 0.85),
                ])
            label.draw(at: NSPoint(x: x, y: y))
        }
        menuRow("Keep Mac Awake", y: menu.maxY - 24, checked: true, dimmed: false)
        menuRow("Off in 1h 12m", y: menu.maxY - 44, checked: false, dimmed: true)
        menuRow("Keep Awake For", y: menu.maxY - 64, checked: false, dimmed: false)
        menuRow("Settings…", y: menu.maxY - 88, checked: false, dimmed: false)
    }
}
