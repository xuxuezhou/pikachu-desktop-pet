import AppKit

// MARK: - Speech bubble (never steals focus, click to dismiss, auto-hides)

private final class BubbleContentView: NSView {
    let text: String
    var onClick: (() -> Void)?

    private let font = NSFont.systemFont(ofSize: 13, weight: .medium)
    private let padding = NSSize(width: 14, height: 10)
    private let tailHeight: CGFloat = 9

    init(text: String, maxWidth: CGFloat) {
        self.text = text
        super.init(frame: .zero)
        let bounding = (text as NSString).boundingRect(
            with: NSSize(width: maxWidth - padding.width * 2, height: 400),
            options: [.usesLineFragmentOrigin],
            attributes: [.font: font]
        )
        frame = NSRect(
            x: 0, y: 0,
            width: ceil(bounding.width) + padding.width * 2,
            height: ceil(bounding.height) + padding.height * 2 + tailHeight
        )
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        let bodyRect = NSRect(
            x: 0.5, y: tailHeight + 0.5,
            width: bounds.width - 1, height: bounds.height - tailHeight - 1
        )
        let bubble = NSBezierPath(roundedRect: bodyRect, xRadius: 11, yRadius: 11)

        // Tail pointing down toward the pet.
        let tail = NSBezierPath()
        let tailX = bounds.midX
        tail.move(to: NSPoint(x: tailX - 7, y: tailHeight + 2))
        tail.line(to: NSPoint(x: tailX, y: 1))
        tail.line(to: NSPoint(x: tailX + 7, y: tailHeight + 2))
        tail.close()
        bubble.append(tail)

        NSColor(calibratedRed: 1.0, green: 0.98, blue: 0.90, alpha: 0.97).setFill()
        bubble.fill()
        NSColor(calibratedRed: 0.85, green: 0.68, blue: 0.20, alpha: 0.9).setStroke()
        bubble.lineWidth = 1.2
        bubble.stroke()

        let textRect = bodyRect.insetBy(dx: 13, dy: 9)
        (text as NSString).draw(
            in: textRect,
            withAttributes: [
                .font: font,
                .foregroundColor: NSColor(calibratedRed: 0.25, green: 0.18, blue: 0.05, alpha: 1),
            ]
        )
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}

final class SpeechBubbleWindow: NSPanel {
    private var hideTimer: Timer?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        hidesOnDeactivate = false
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(text: String, above petFrame: NSRect, on screen: NSScreen?, duration: Double) {
        hideTimer?.invalidate()

        let content = BubbleContentView(text: text, maxWidth: 260)
        content.onClick = { [weak self] in self?.dismiss() }
        setContentSize(content.frame.size)
        contentView = content

        let visible = (screen ?? NSScreen.main)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        var origin = NSPoint(
            x: petFrame.midX - content.frame.width / 2,
            y: petFrame.maxY + 4
        )
        origin.x = min(max(origin.x, visible.minX + 6), visible.maxX - content.frame.width - 6)
        origin.y = min(origin.y, visible.maxY - content.frame.height - 6)
        setFrameOrigin(origin)
        orderFront(nil)

        hideTimer = Timer.scheduledTimer(withTimeInterval: max(1.5, duration), repeats: false) { [weak self] _ in
            self?.dismiss()
        }
    }

    func dismiss() {
        hideTimer?.invalidate()
        hideTimer = nil
        orderOut(nil)
    }
}
