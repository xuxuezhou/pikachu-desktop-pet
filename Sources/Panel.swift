import AppKit

// MARK: - Panel buttons (ported from the original single-file implementation)

enum PanelButtonStyle {
    case action
    case utility
    case danger
    case quiet
}

final class PanelButton: NSButton {
    var badge: String? {
        didSet { needsDisplay = true }
    }

    var onPress: (() -> Void)?

    private let displayTitle: String
    private let accent: NSColor
    private let buttonStyle: PanelButtonStyle
    private var isHovering = false
    private var hoverTrackingArea: NSTrackingArea?

    override var isFlipped: Bool { true }

    override var isHighlighted: Bool {
        didSet { needsDisplay = true }
    }

    init(
        title: String,
        badge: String? = nil,
        accent: NSColor,
        style: PanelButtonStyle = .action,
        onPress: @escaping () -> Void
    ) {
        self.displayTitle = title
        self.badge = badge
        self.accent = accent
        self.buttonStyle = style
        self.onPress = onPress
        super.init(frame: .zero)
        self.title = ""
        isBordered = false
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(runPressAction)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius: CGFloat = buttonStyle == .action ? 14 : 11
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)

        let base: NSColor
        switch buttonStyle {
        case .action:
            base = NSColor(calibratedWhite: 1.0, alpha: isHighlighted ? 0.20 : (isHovering ? 0.16 : 0.10))
        case .utility:
            base = NSColor(calibratedWhite: 1.0, alpha: isHighlighted ? 0.18 : (isHovering ? 0.13 : 0.08))
        case .danger:
            base = NSColor(calibratedRed: 0.95, green: 0.22, blue: 0.18, alpha: isHighlighted ? 0.30 : (isHovering ? 0.22 : 0.15))
        case .quiet:
            base = NSColor(calibratedWhite: 1.0, alpha: isHighlighted ? 0.16 : (isHovering ? 0.10 : 0.06))
        }

        base.setFill()
        path.fill()

        accent.withAlphaComponent(buttonStyle == .action ? 0.95 : 0.75).setStroke()
        path.lineWidth = isHovering ? 1.4 : 0.8
        path.stroke()

        if buttonStyle == .action, let badge, !badge.isEmpty {
            let badgeRect = NSRect(x: (bounds.width - 28) / 2, y: 8, width: 28, height: 17)
            let glow = NSBezierPath(roundedRect: badgeRect, xRadius: 8.5, yRadius: 8.5)
            accent.withAlphaComponent(isHighlighted ? 0.95 : 0.80).setFill()
            glow.fill()
        }

        if let badge, !badge.isEmpty {
            let badgeRect: NSRect
            if buttonStyle == .action {
                badgeRect = NSRect(x: (bounds.width - 28) / 2, y: 8, width: 28, height: 17)
            } else {
                badgeRect = NSRect(x: (bounds.width - 28) / 2, y: bounds.height - 14, width: 28, height: 12)
                let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: 8.5, yRadius: 8.5)
                accent.withAlphaComponent(0.22).setFill()
                badgePath.fill()
            }

            let badgeAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: buttonStyle == .action ? 10 : 8, weight: .bold),
                .foregroundColor: buttonStyle == .action
                    ? NSColor(calibratedWhite: 0.09, alpha: 1)
                    : accent
            ]
            (badge as NSString).draw(
                in: badgeRect.insetBy(dx: 0, dy: buttonStyle == .action ? 2 : 1),
                withAttributes: centeredAttributes(badgeAttributes)
            )
        }

        let titleFontSize: CGFloat = buttonStyle == .action ? 13 : 12
        let titleY: CGFloat
        let titleHeight: CGFloat
        if buttonStyle == .action {
            titleY = 29
            titleHeight = 18
        } else if badge == nil {
            titleY = (bounds.height - 16) / 2
            titleHeight = 18
        } else {
            titleY = 4
            titleHeight = 13
        }
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: titleFontSize, weight: buttonStyle == .danger ? .semibold : .medium),
            .foregroundColor: NSColor(calibratedWhite: 0.98, alpha: buttonStyle == .quiet ? 0.82 : 1)
        ]
        (displayTitle as NSString).draw(
            in: NSRect(x: 3, y: titleY, width: bounds.width - 6, height: titleHeight),
            withAttributes: centeredAttributes(titleAttributes)
        )
    }

    private func centeredAttributes(_ attributes: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        var result = attributes
        result[.paragraphStyle] = paragraph
        return result
    }

    @objc private func runPressAction() {
        onPress?()
    }
}

// MARK: - Interaction panel view (now with a live status line)

final class InteractionPanelView: NSView {
    override var isFlipped: Bool { true }

    /// Refreshed on each redraw; supplies "😊 开心 · ⚡️82 · 🍎74".
    private let statusProvider: () -> String

    init(
        frame frameRect: NSRect,
        isAlwaysOnTop: Bool,
        statusProvider: @escaping () -> String,
        onJump: @escaping () -> Void,
        onBow: @escaping () -> Void,
        onPose: @escaping () -> Void,
        onTrip: @escaping () -> Void,
        onRunLeft: @escaping () -> Void,
        onRunRight: @escaping () -> Void,
        onSmaller: @escaping () -> Void,
        onBigger: @escaping () -> Void,
        onToggleTop: @escaping () -> Bool,
        onQuit: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.statusProvider = statusProvider
        super.init(frame: frameRect)
        wantsLayer = true

        let yellow = NSColor(calibratedRed: 1.00, green: 0.80, blue: 0.20, alpha: 1)
        let coral = NSColor(calibratedRed: 1.00, green: 0.36, blue: 0.32, alpha: 1)
        let mint = NSColor(calibratedRed: 0.28, green: 0.86, blue: 0.65, alpha: 1)
        let sky = NSColor(calibratedRed: 0.36, green: 0.66, blue: 1.00, alpha: 1)
        let violet = NSColor(calibratedRed: 0.78, green: 0.58, blue: 1.00, alpha: 1)

        addActionButton("Left", badge: "A", accent: sky, frame: NSRect(x: 14, y: 60, width: 62, height: 50), action: onRunLeft)
        addActionButton("Jump", badge: "W", accent: yellow, frame: NSRect(x: 80, y: 60, width: 62, height: 50), action: onJump)
        addActionButton("Right", badge: "D", accent: sky, frame: NSRect(x: 146, y: 60, width: 62, height: 50), action: onRunRight)
        addActionButton("Bow", badge: "B", accent: coral, frame: NSRect(x: 14, y: 116, width: 62, height: 50), action: onBow)
        addActionButton("Pose", badge: "P", accent: violet, frame: NSRect(x: 80, y: 116, width: 62, height: 50), action: onPose)
        addActionButton("Down", badge: "S", accent: mint, frame: NSRect(x: 146, y: 116, width: 62, height: 50), action: onTrip)

        addUtilityButton("Sm", badge: nil, accent: sky, frame: NSRect(x: 14, y: 182, width: 45, height: 30), action: onSmaller)
        addUtilityButton("Lg", badge: nil, accent: yellow, frame: NSRect(x: 66, y: 182, width: 45, height: 30), action: onBigger)

        let topButton = PanelButton(
            title: "Pin",
            badge: isAlwaysOnTop ? "ON" : "OFF",
            accent: mint,
            style: .utility
        ) {}
        topButton.onPress = { [weak topButton] in
            let enabled = onToggleTop()
            topButton?.badge = enabled ? "ON" : "OFF"
        }
        topButton.frame = NSRect(x: 118, y: 182, width: 45, height: 30)
        addSubview(topButton)

        addUtilityButton("Quit", badge: nil, accent: coral, style: .danger, frame: NSRect(x: 170, y: 182, width: 45, height: 30), action: onQuit)
        addUtilityButton("x", badge: nil, accent: NSColor(calibratedWhite: 1, alpha: 0.8), style: .quiet, frame: NSRect(x: 196, y: 12, width: 20, height: 20), action: onClose)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        let panelRect = bounds.insetBy(dx: 1, dy: 1)
        let panelPath = NSBezierPath(roundedRect: panelRect, xRadius: 18, yRadius: 18)
        NSColor(calibratedRed: 0.08, green: 0.08, blue: 0.10, alpha: 0.94).setFill()
        panelPath.fill()

        NSColor(calibratedRed: 1.00, green: 0.80, blue: 0.22, alpha: 0.36).setStroke()
        panelPath.lineWidth = 1
        panelPath.stroke()

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: NSColor(calibratedWhite: 1, alpha: 0.96)
        ]
        ("Pika Cmd" as NSString).draw(
            in: NSRect(x: 14, y: 13, width: 140, height: 20),
            withAttributes: titleAttributes
        )

        let statusAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor(calibratedWhite: 1, alpha: 0.72)
        ]
        (statusProvider() as NSString).draw(
            in: NSRect(x: 14, y: 36, width: bounds.width - 28, height: 16),
            withAttributes: statusAttributes
        )

        let divider = NSBezierPath()
        divider.move(to: NSPoint(x: 14, y: 174))
        divider.line(to: NSPoint(x: bounds.width - 14, y: 174))
        NSColor(calibratedWhite: 1, alpha: 0.10).setStroke()
        divider.lineWidth = 1
        divider.stroke()
    }

    private func addActionButton(
        _ title: String,
        badge: String,
        accent: NSColor,
        frame: NSRect,
        action: @escaping () -> Void
    ) {
        let button = PanelButton(title: title, badge: badge, accent: accent, style: .action, onPress: action)
        button.frame = frame
        addSubview(button)
    }

    private func addUtilityButton(
        _ title: String,
        badge: String?,
        accent: NSColor,
        style: PanelButtonStyle = .utility,
        frame: NSRect,
        action: @escaping () -> Void
    ) {
        let button = PanelButton(title: title, badge: badge, accent: accent, style: style, onPress: action)
        button.frame = frame
        addSubview(button)
    }
}

final class InteractionPanelWindow: NSPanel {
    static let panelSize = NSSize(width: 222, height: 226)

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(
        isAlwaysOnTop: Bool,
        statusProvider: @escaping () -> String,
        onJump: @escaping () -> Void,
        onBow: @escaping () -> Void,
        onPose: @escaping () -> Void,
        onTrip: @escaping () -> Void,
        onRunLeft: @escaping () -> Void,
        onRunRight: @escaping () -> Void,
        onSmaller: @escaping () -> Void,
        onBigger: @escaping () -> Void,
        onToggleTop: @escaping () -> Bool,
        onQuit: @escaping () -> Void
    ) {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = isAlwaysOnTop ? .floating : .normal
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        contentView = InteractionPanelView(
            frame: NSRect(origin: .zero, size: Self.panelSize),
            isAlwaysOnTop: isAlwaysOnTop,
            statusProvider: statusProvider,
            onJump: onJump,
            onBow: onBow,
            onPose: onPose,
            onTrip: onTrip,
            onRunLeft: onRunLeft,
            onRunRight: onRunRight,
            onSmaller: onSmaller,
            onBigger: onBigger,
            onToggleTop: onToggleTop,
            onQuit: onQuit,
            onClose: { [weak self] in self?.orderOut(nil) }
        )
    }
}
