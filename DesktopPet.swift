import AppKit
import CoreGraphics

final class PetWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

struct SpriteAnimation {
    let image: NSImage
    let frameWidth: Int
    let frameHeight: Int
    let durations: [Int]
    let defaultRow: Int
    let visualScale: CGFloat

    var frameCount: Int {
        max(1, Int(image.size.width) / frameWidth)
    }

    var totalDuration: Int {
        max(1, durations.reduce(0, +))
    }

    func frameIndex(at tick: Int) -> Int {
        let wrapped = tick % totalDuration
        var elapsed = 0

        for index in 0..<min(frameCount, durations.count) {
            elapsed += durations[index]
            if wrapped < elapsed {
                return index
            }
        }

        return max(0, min(frameCount - 1, durations.count - 1))
    }
}

private enum SpriteRow {
    static let front = 7
    static let left = 1
    static let right = 5
}

struct SpriteSet {
    let idle: SpriteAnimation
    let walk: SpriteAnimation
    let hop: SpriteAnimation
    let nod: SpriteAnimation
    let pose: SpriteAnimation
    let trip: SpriteAnimation

    static func load() -> SpriteSet? {
        guard
            let idleImage = loadSpriteImage(named: "Idle-Anim.png"),
            let walkImage = loadSpriteImage(named: "Walk-Anim.png"),
            let hopImage = loadSpriteImage(named: "Hop-Anim.png"),
            let nodImage = loadSpriteImage(named: "Nod-Anim.png"),
            let poseImage = loadSpriteImage(named: "Pose-Anim.png"),
            let tripImage = loadSpriteImage(named: "Trip-Anim.png")
        else {
            return nil
        }

        return SpriteSet(
            idle: SpriteAnimation(
                image: idleImage,
                frameWidth: 40,
                frameHeight: 56,
                durations: [40, 2, 3, 3, 3, 2],
                defaultRow: SpriteRow.front,
                visualScale: 1.0
            ),
            walk: SpriteAnimation(
                image: walkImage,
                frameWidth: 32,
                frameHeight: 40,
                durations: [4, 5, 4, 5],
                defaultRow: SpriteRow.front,
                visualScale: 0.95
            ),
            hop: SpriteAnimation(
                image: hopImage,
                frameWidth: 40,
                frameHeight: 88,
                durations: [2, 1, 2, 3, 4, 4, 3, 2, 1, 2],
                defaultRow: SpriteRow.front,
                visualScale: 0.95
            ),
            nod: SpriteAnimation(
                image: nodImage,
                frameWidth: 32,
                frameHeight: 48,
                durations: [6, 8, 6],
                defaultRow: SpriteRow.front,
                visualScale: 0.95
            ),
            pose: SpriteAnimation(
                image: poseImage,
                frameWidth: 32,
                frameHeight: 40,
                durations: [12, 2, 8],
                defaultRow: SpriteRow.front,
                visualScale: 0.95
            ),
            trip: SpriteAnimation(
                image: tripImage,
                frameWidth: 40,
                frameHeight: 40,
                durations: [4, 6, 4, 4, 4],
                defaultRow: SpriteRow.front,
                visualScale: 0.92
            )
        )
    }

    private static func loadSpriteImage(named name: String) -> NSImage? {
        let fileManager = FileManager.default
        let current = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        let parent = executable.deletingLastPathComponent()

        var folders = [
            current.appendingPathComponent("pmd_sprites"),
            executable.appendingPathComponent("pmd_sprites"),
            parent.appendingPathComponent("Resources").appendingPathComponent("pmd_sprites")
        ]

        if let resources = Bundle.main.resourceURL {
            folders.append(resources.appendingPathComponent("pmd_sprites"))
        }

        for folder in folders {
            let url = folder.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: url.path), let image = NSImage(contentsOf: url) else {
                continue
            }
            return image
        }

        return nil
    }
}

private enum PanelButtonStyle {
    case action
    case utility
    case danger
    case quiet
}

private final class PanelButton: NSButton {
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
            let badgeRect = NSRect(
                x: (bounds.width - 28) / 2,
                y: 8,
                width: 28,
                height: 17
            )
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

private final class InteractionPanelView: NSView {
    override var isFlipped: Bool { true }

    init(
        frame frameRect: NSRect,
        isAlwaysOnTop: Bool,
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
        super.init(frame: frameRect)
        wantsLayer = true

        let yellow = NSColor(calibratedRed: 1.00, green: 0.80, blue: 0.20, alpha: 1)
        let coral = NSColor(calibratedRed: 1.00, green: 0.36, blue: 0.32, alpha: 1)
        let mint = NSColor(calibratedRed: 0.28, green: 0.86, blue: 0.65, alpha: 1)
        let sky = NSColor(calibratedRed: 0.36, green: 0.66, blue: 1.00, alpha: 1)
        let violet = NSColor(calibratedRed: 0.78, green: 0.58, blue: 1.00, alpha: 1)

        addActionButton("Left", badge: "A", accent: sky, frame: NSRect(x: 14, y: 42, width: 62, height: 50), action: onRunLeft)
        addActionButton("Jump", badge: "W", accent: yellow, frame: NSRect(x: 80, y: 42, width: 62, height: 50), action: onJump)
        addActionButton("Right", badge: "D", accent: sky, frame: NSRect(x: 146, y: 42, width: 62, height: 50), action: onRunRight)
        addActionButton("Bow", badge: "B", accent: coral, frame: NSRect(x: 14, y: 98, width: 62, height: 50), action: onBow)
        addActionButton("Pose", badge: "P", accent: violet, frame: NSRect(x: 80, y: 98, width: 62, height: 50), action: onPose)
        addActionButton("Down", badge: "S", accent: mint, frame: NSRect(x: 146, y: 98, width: 62, height: 50), action: onTrip)

        addUtilityButton("Sm", badge: nil, accent: sky, frame: NSRect(x: 14, y: 164, width: 45, height: 30), action: onSmaller)
        addUtilityButton("Lg", badge: nil, accent: yellow, frame: NSRect(x: 66, y: 164, width: 45, height: 30), action: onBigger)

        let topButton = PanelButton(
            title: "Pin",
            badge: isAlwaysOnTop ? "ON" : "OFF",
            accent: mint,
            style: .utility
        ) {
            return
        }
        topButton.onPress = { [weak topButton] in
            let enabled = onToggleTop()
            topButton?.badge = enabled ? "ON" : "OFF"
        }
        topButton.frame = NSRect(x: 118, y: 164, width: 45, height: 30)
        addSubview(topButton)

        addUtilityButton("Quit", badge: nil, accent: coral, style: .danger, frame: NSRect(x: 170, y: 164, width: 45, height: 30), action: onQuit)
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

        let dotPath = NSBezierPath(ovalIn: NSRect(x: 14, y: 34, width: 42, height: 2.5))
        NSColor(calibratedRed: 1.00, green: 0.78, blue: 0.18, alpha: 0.85).setFill()
        dotPath.fill()

        let divider = NSBezierPath()
        divider.move(to: NSPoint(x: 14, y: 156))
        divider.line(to: NSPoint(x: bounds.width - 14, y: 156))
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

private final class InteractionPanelWindow: NSPanel {
    static let panelSize = NSSize(width: 222, height: 208)

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(
        isAlwaysOnTop: Bool,
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
        level = .floating
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        contentView = InteractionPanelView(
            frame: NSRect(origin: .zero, size: Self.panelSize),
            isAlwaysOnTop: isAlwaysOnTop,
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

final class PetView: NSView {
    private enum PetAction {
        case idle
        case hop
        case nod
        case pose
        case trip
        case run
    }

    private enum ManualAction {
        case jump
        case bow
        case pose
        case trip
        case runLeft
        case runRight
    }

    private let petImage: NSImage?
    private let spriteSet: SpriteSet?
    private var timer: Timer?
    private var phase: CGFloat = 0
    private var animationTick = 0
    private var activeAction: PetAction = .idle
    private var actionTicksRemaining = 0
    private var dragStartScreen: NSPoint = .zero
    private var dragStartOrigin: NSPoint = .zero
    private var dragDidMove = false
    private var jumpTick = 0
    private var jumpTicksRemaining = 0
    private var runDistanceRemaining: CGFloat = 0
    private var runDirection: CGFloat = 1
    private var facingDirection: CGFloat = 1
    private var currentWindowLift: CGFloat = 0
    private var lastClickTimestamp: TimeInterval = 0
    private var lastInteractionTimestamp: TimeInterval = ProcessInfo.processInfo.systemUptime
    private var nextAutonomousTimestamp: TimeInterval = ProcessInfo.processInfo.systemUptime + 14
    private var rapidClickCount = 0
    private var isAlwaysOnTop = true
    private var interactionPanel: InteractionPanelWindow?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(image: NSImage?, spriteSet: SpriteSet?) {
        self.petImage = image
        self.spriteSet = spriteSet
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        startAnimation()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        timer?.invalidate()
        interactionPanel?.close()
    }

    private func startAnimation() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.phase += 0.08
            self.animationTick += 1
            self.updateMotion()
            self.needsDisplay = true
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func updateMotion() {
        maybeStartAutonomousAction()

        if actionTicksRemaining > 0 {
            actionTicksRemaining -= 1
            if actionTicksRemaining == 0 && runDistanceRemaining <= 0 {
                activeAction = .idle
                animationTick = 0
            }
        }

        if jumpTicksRemaining > 0 {
            jumpTick += 1
            jumpTicksRemaining -= 1
            if jumpTicksRemaining == 0 {
                jumpTick = 0
                if activeAction == .hop && actionTicksRemaining == 0 {
                    activeAction = .idle
                    animationTick = 0
                }
            }
        }

        guard let window else { return }

        var frame = window.frame
        let baseY = frame.origin.y - currentWindowLift
        let targetWindowLift = currentMotionLift()
        frame.origin.y = baseY + targetWindowLift
        currentWindowLift = targetWindowLift

        guard runDistanceRemaining > 0 else {
            window.setFrameOrigin(frame.origin)
            return
        }

        let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let step = min(15, runDistanceRemaining) * runDirection
        let minX = visibleFrame.minX + 8
        let maxX = visibleFrame.maxX - frame.width - 8
        let nextX = min(max(frame.origin.x + step, minX), maxX)
        let moved = abs(nextX - frame.origin.x)

        if moved < 0.5 {
            runDistanceRemaining = 0
            activeAction = .idle
            animationTick = 0
            window.setFrameOrigin(frame.origin)
            return
        }

        frame.origin.x = nextX
        runDistanceRemaining -= moved
        if runDistanceRemaining <= 0 {
            activeAction = .idle
            animationTick = 0
        }
        window.setFrameOrigin(frame.origin)
    }

    private func maybeStartAutonomousAction() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now >= nextAutonomousTimestamp else { return }
        guard activeAction == .idle, runDistanceRemaining <= 0, jumpTicksRemaining <= 0 else { return }
        guard now - lastInteractionTimestamp >= 12 else {
            scheduleNextAutonomousAction(after: 4...8)
            return
        }

        startAutonomousAction()
    }

    private func scheduleNextAutonomousAction(after range: ClosedRange<Double> = 9...16) {
        nextAutonomousTimestamp = ProcessInfo.processInfo.systemUptime + Double.random(in: range)
    }

    private func markInteraction() {
        lastInteractionTimestamp = ProcessInfo.processInfo.systemUptime
        scheduleNextAutonomousAction(after: 12...20)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()

        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()

        let usingSprites = spriteSet != nil
        let idleBounce = runDistanceRemaining > 0 || jumpTicksRemaining > 0 || usingSprites ? CGFloat(0) : sin(phase) * 4
        let wiggle = sin(phase * 0.55) * 0.035
        let runLean = runDistanceRemaining > 0 && !usingSprites ? runDirection * 0.08 : CGFloat(0)
        let squash = 1 + sin(phase * 0.9) * 0.015
        let xScale = usingSprites ? 1 : (facingDirection < 0 ? -1 : 1) / squash

        context.translateBy(x: bounds.midX, y: bounds.midY + idleBounce)
        context.rotate(by: (usingSprites ? 0 : wiggle) + runLean)
        context.scaleBy(x: xScale, y: usingSprites ? 1 : squash)
        context.translateBy(x: -bounds.midX, y: -bounds.midY)

        let petRect = bounds.insetBy(dx: 12, dy: 10)
        if let spriteSet {
            drawActiveSprite(spriteSet, in: petRect)
        } else if let petImage {
            drawPetImage(petImage, in: petRect)
        } else {
            drawBuiltInPet(in: petRect)
        }

        context.restoreGState()
    }

    private func currentMotionLift() -> CGFloat {
        let jumpLift = currentJumpLift()
        let runLift = runDistanceRemaining > 0 ? abs(sin(phase * 3.8)) * 18 : CGFloat(0)
        return max(jumpLift, runLift)
    }

    private func currentJumpLift() -> CGFloat {
        guard jumpTicksRemaining > 0 else { return 0 }
        let totalTicks: CGFloat = 22
        let progress = min(1, CGFloat(jumpTick) / totalTicks)
        let height: CGFloat = runDistanceRemaining > 0 ? 24 : 44
        return sin(progress * .pi) * height
    }

    private func settleVerticalMotion() {
        guard currentWindowLift != 0, let window else { return }
        let old = window.frame
        window.setFrameOrigin(NSPoint(x: old.origin.x, y: old.origin.y - currentWindowLift))
        currentWindowLift = 0
    }

    private func drawActiveSprite(_ spriteSet: SpriteSet, in rect: NSRect) {
        switch activeAction {
        case .run:
            let row = runDirection > 0 ? SpriteRow.right : SpriteRow.left
            drawSprite(spriteSet.walk, in: rect, row: row)
        case .hop:
            drawSprite(spriteSet.hop, in: rect)
        case .nod:
            drawSprite(spriteSet.nod, in: rect)
        case .pose:
            drawSprite(spriteSet.pose, in: rect)
        case .trip:
            drawSprite(spriteSet.trip, in: rect)
        case .idle:
            drawSprite(spriteSet.idle, in: rect, fixedFrame: 0)
        }
    }

    private func drawSprite(
        _ animation: SpriteAnimation,
        in rect: NSRect,
        row overrideRow: Int? = nil,
        fixedFrame: Int? = nil
    ) {
        guard animation.image.size.width > 0, animation.image.size.height > 0 else { return }

        let frameIndex = fixedFrame ?? animation.frameIndex(at: animationTick)
        let row = overrideRow ?? animation.defaultRow
        let source = NSRect(
            x: frameIndex * animation.frameWidth,
            y: row * animation.frameHeight,
            width: animation.frameWidth,
            height: animation.frameHeight
        )

        let targetAspect = CGFloat(animation.frameWidth) / CGFloat(animation.frameHeight)
        var drawSize = rect.size
        if drawSize.width / drawSize.height > targetAspect {
            drawSize.width = drawSize.height * targetAspect
        } else {
            drawSize.height = drawSize.width / targetAspect
        }
        drawSize.width *= animation.visualScale
        drawSize.height *= animation.visualScale

        let drawRect = NSRect(
            x: rect.midX - drawSize.width / 2,
            y: rect.midY - drawSize.height / 2,
            width: drawSize.width,
            height: drawSize.height
        )

        animation.image.draw(
            in: drawRect,
            from: source,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.none]
        )
    }

    private func drawPetImage(_ image: NSImage, in rect: NSRect) {
        guard image.size.width > 0, image.size.height > 0 else { return }
        let scale = min(rect.width / image.size.width, rect.height / image.size.height)
        let drawSize = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let drawRect = NSRect(
            x: rect.midX - drawSize.width / 2,
            y: rect.midY - drawSize.height / 2,
            width: drawSize.width,
            height: drawSize.height
        )
        image.draw(
            in: drawRect,
            from: NSRect(origin: .zero, size: image.size),
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
    }

    private func point(_ x: CGFloat, _ y: CGFloat, in rect: NSRect) -> NSPoint {
        NSPoint(x: rect.minX + x / 200 * rect.width, y: rect.minY + y / 240 * rect.height)
    }

    private func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, in base: NSRect) -> NSRect {
        NSRect(
            x: base.minX + x / 200 * base.width,
            y: base.minY + y / 240 * base.height,
            width: width / 200 * base.width,
            height: height / 240 * base.height
        )
    }

    private func path(_ points: [NSPoint]) -> NSBezierPath {
        let result = NSBezierPath()
        guard let first = points.first else { return result }
        result.move(to: first)
        for point in points.dropFirst() {
            result.line(to: point)
        }
        result.close()
        return result
    }

    private func drawBuiltInPet(in rect: NSRect) {
        let yellow = NSColor(calibratedRed: 1.0, green: 0.82, blue: 0.18, alpha: 1)
        let shadowYellow = NSColor(calibratedRed: 0.78, green: 0.55, blue: 0.10, alpha: 1)
        let line = NSColor(calibratedRed: 0.18, green: 0.13, blue: 0.05, alpha: 1)
        let cheek = NSColor(calibratedRed: 0.95, green: 0.22, blue: 0.16, alpha: 1)
        let mouth = NSColor(calibratedRed: 0.92, green: 0.25, blue: 0.21, alpha: 1)

        func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { point(x, y, in: rect) }
        func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect { self.rect(x, y, w, h, in: rect) }

        let strokeWidth = max(2.0, rect.width * 0.01)

        let tail = path([
            p(145, 120), p(190, 92), p(175, 116), p(195, 124),
            p(166, 156), p(151, 147)
        ])
        yellow.setFill()
        tail.fill()
        line.setStroke()
        tail.lineWidth = strokeWidth
        tail.stroke()

        let leftEar = path([p(82, 64), p(99, 2), p(117, 10), p(101, 75)])
        yellow.setFill()
        leftEar.fill()
        line.setStroke()
        leftEar.lineWidth = strokeWidth
        leftEar.stroke()

        let leftTip = path([p(99, 2), p(117, 10), p(111, 31)])
        NSColor.black.setFill()
        leftTip.fill()

        let rightEar = path([p(136, 70), p(184, 79), p(192, 96), p(145, 101)])
        yellow.setFill()
        rightEar.fill()
        line.setStroke()
        rightEar.lineWidth = strokeWidth
        rightEar.stroke()

        let rightTip = path([p(174, 78), p(192, 96), p(160, 98)])
        NSColor.black.setFill()
        rightTip.fill()

        let leftArmLift = sin(phase * 1.3) * 5
        let leftArm = NSBezierPath()
        leftArm.move(to: p(55, 116 + leftArmLift))
        leftArm.curve(
            to: p(33, 84 + leftArmLift),
            controlPoint1: p(40, 111 + leftArmLift),
            controlPoint2: p(30, 101 + leftArmLift)
        )
        leftArm.curve(
            to: p(48, 76 + leftArmLift),
            controlPoint1: p(34, 78 + leftArmLift),
            controlPoint2: p(41, 74 + leftArmLift)
        )
        leftArm.curve(
            to: p(67, 121 + leftArmLift),
            controlPoint1: p(57, 86 + leftArmLift),
            controlPoint2: p(62, 102 + leftArmLift)
        )
        leftArm.close()
        yellow.setFill()
        leftArm.fill()
        line.setStroke()
        leftArm.lineWidth = strokeWidth
        leftArm.stroke()

        let rightArm = NSBezierPath()
        rightArm.move(to: p(139, 121))
        rightArm.curve(to: p(169, 139), controlPoint1: p(152, 119), controlPoint2: p(163, 125))
        rightArm.curve(to: p(162, 154), controlPoint1: p(174, 148), controlPoint2: p(170, 157))
        rightArm.curve(to: p(132, 143), controlPoint1: p(149, 153), controlPoint2: p(140, 149))
        rightArm.close()
        yellow.setFill()
        rightArm.fill()
        line.setStroke()
        rightArm.lineWidth = strokeWidth
        rightArm.stroke()

        let body = NSBezierPath()
        body.move(to: p(63, 102))
        body.curve(to: p(52, 211), controlPoint1: p(44, 131), controlPoint2: p(38, 184))
        body.curve(to: p(101, 229), controlPoint1: p(62, 228), controlPoint2: p(82, 231))
        body.curve(to: p(151, 211), controlPoint1: p(124, 232), controlPoint2: p(144, 228))
        body.curve(to: p(137, 100), controlPoint1: p(161, 183), controlPoint2: p(159, 126))
        body.curve(to: p(63, 102), controlPoint1: p(118, 80), controlPoint2: p(82, 81))
        body.close()
        yellow.setFill()
        body.fill()
        line.setStroke()
        body.lineWidth = strokeWidth
        body.stroke()

        let bellyShadow = NSBezierPath()
        bellyShadow.move(to: p(74, 178))
        bellyShadow.curve(to: p(123, 184), controlPoint1: p(86, 195), controlPoint2: p(109, 197))
        bellyShadow.lineWidth = strokeWidth * 1.5
        shadowYellow.withAlphaComponent(0.45).setStroke()
        bellyShadow.stroke()

        let leftFoot = NSBezierPath()
        leftFoot.move(to: p(68, 222))
        leftFoot.curve(to: p(38, 231), controlPoint1: p(57, 224), controlPoint2: p(46, 226))
        leftFoot.curve(to: p(73, 229), controlPoint1: p(47, 237), controlPoint2: p(62, 236))
        leftFoot.close()
        yellow.setFill()
        leftFoot.fill()
        line.setStroke()
        leftFoot.lineWidth = strokeWidth
        leftFoot.stroke()

        let rightFoot = NSBezierPath()
        rightFoot.move(to: p(127, 223))
        rightFoot.curve(to: p(162, 231), controlPoint1: p(139, 224), controlPoint2: p(152, 226))
        rightFoot.curve(to: p(124, 231), controlPoint1: p(153, 238), controlPoint2: p(138, 237))
        rightFoot.close()
        yellow.setFill()
        rightFoot.fill()
        line.setStroke()
        rightFoot.lineWidth = strokeWidth
        rightFoot.stroke()

        NSColor.black.setFill()
        NSBezierPath(ovalIn: r(66, 88, 17, 20)).fill()
        NSBezierPath(ovalIn: r(124, 91, 17, 20)).fill()

        cheek.setFill()
        NSBezierPath(ovalIn: r(52, 117, 26, 24)).fill()
        NSBezierPath(ovalIn: r(139, 119, 26, 24)).fill()

        line.setStroke()
        let nose = NSBezierPath()
        nose.move(to: p(99, 109))
        nose.curve(to: p(104, 109), controlPoint1: p(101, 111), controlPoint2: p(103, 111))
        nose.lineWidth = strokeWidth
        nose.stroke()

        let smile = NSBezierPath()
        smile.move(to: p(91, 119))
        smile.curve(to: p(101, 124), controlPoint1: p(93, 126), controlPoint2: p(98, 127))
        smile.curve(to: p(111, 120), controlPoint1: p(104, 127), controlPoint2: p(109, 126))
        smile.lineWidth = strokeWidth
        smile.stroke()

        let openMouth = NSBezierPath()
        openMouth.move(to: p(85, 125))
        openMouth.curve(to: p(119, 127), controlPoint1: p(95, 151), controlPoint2: p(112, 151))
        openMouth.curve(to: p(85, 125), controlPoint1: p(111, 138), controlPoint2: p(94, 137))
        openMouth.close()
        mouth.setFill()
        openMouth.fill()
        line.setStroke()
        openMouth.lineWidth = strokeWidth
        openMouth.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        beginPointerAction(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        beginPointerAction(with: event)
    }

    private func beginPointerAction(with event: NSEvent) {
        markInteraction()
        window?.makeFirstResponder(self)

        if event.modifierFlags.contains(.option) {
            showInteractionPanel()
            dragDidMove = true
            return
        }

        closeInteractionPanel()
        settleVerticalMotion()
        dragStartScreen = NSEvent.mouseLocation
        dragStartOrigin = window?.frame.origin ?? .zero
        dragDidMove = false
    }

    override func mouseDragged(with event: NSEvent) {
        dragPointer(with: event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        dragPointer(with: event)
    }

    private func dragPointer(with event: NSEvent) {
        markInteraction()
        guard let window else { return }
        let current = NSEvent.mouseLocation
        let delta = NSPoint(x: current.x - dragStartScreen.x, y: current.y - dragStartScreen.y)
        if hypot(delta.x, delta.y) > 6 {
            dragDidMove = true
            runDistanceRemaining = 0
            jumpTicksRemaining = 0
            jumpTick = 0
            actionTicksRemaining = 0
            activeAction = .idle
        }
        window.setFrameOrigin(NSPoint(x: dragStartOrigin.x + delta.x, y: dragStartOrigin.y + delta.y))
    }

    override func mouseUp(with event: NSEvent) {
        finishPointerAction(with: event)
    }

    override func rightMouseUp(with event: NSEvent) {
        finishPointerAction(with: event)
    }

    private func finishPointerAction(with event: NSEvent) {
        guard !dragDidMove else { return }
        handlePetClick(event)
    }

    private func handlePetClick(_ event: NSEvent) {
        markInteraction()

        let now = ProcessInfo.processInfo.systemUptime
        if now - lastClickTimestamp > 0.55 {
            rapidClickCount = 0
        }

        rapidClickCount += 1
        lastClickTimestamp = now

        if event.clickCount >= 2 || rapidClickCount >= 3 {
            startRunning()
        } else {
            performManualAction(.jump, mark: false)
        }
    }

    override func keyDown(with event: NSEvent) {
        guard let key = event.charactersIgnoringModifiers?.lowercased().first else {
            super.keyDown(with: event)
            return
        }

        switch key {
        case "w":
            performManualAction(.jump)
        case "a":
            performManualAction(.runLeft)
        case "d":
            performManualAction(.runRight)
        case "b":
            performManualAction(.bow)
        case "p":
            performManualAction(.pose)
        case "s":
            performManualAction(.trip)
        default:
            super.keyDown(with: event)
        }
    }

    private func performManualAction(_ action: ManualAction, mark shouldMarkInteraction: Bool = true) {
        if shouldMarkInteraction {
            markInteraction()
        }

        switch action {
        case .jump:
            jumpInPlace()
        case .bow:
            startSpriteOneShot(.nod, duration: spriteSet?.nod.totalDuration ?? 20)
        case .pose:
            startSpriteOneShot(.pose, duration: spriteSet?.pose.totalDuration ?? 22)
        case .trip:
            startSpriteOneShot(.trip, duration: spriteSet?.trip.totalDuration ?? 24)
        case .runLeft:
            startRunning(forcedDirection: -1)
        case .runRight:
            startRunning(forcedDirection: 1)
        }
    }

    private func performManualPanelAction(_ action: ManualAction) {
        performManualAction(action)
        closeInteractionPanel()
    }

    private func startSpriteOneShot(_ action: PetAction, duration: Int) {
        guard spriteSet != nil else {
            jumpInPlace()
            return
        }

        startOneShot(action, duration: duration)
    }

    private func startAutonomousAction() {
        guard spriteSet != nil else {
            jumpInPlace()
            scheduleNextAutonomousAction()
            return
        }

        let moodRoll = Int.random(in: 0..<100)
        if moodRoll < 34 {
            jumpInPlace()
        } else if moodRoll < 58 {
            startOneShot(.pose, duration: spriteSet?.pose.totalDuration ?? 22)
        } else if moodRoll < 76 {
            startOneShot(.nod, duration: spriteSet?.nod.totalDuration ?? 20)
        } else if moodRoll < 92 {
            startRunning(maxDistance: 180)
        } else {
            startOneShot(.trip, duration: spriteSet?.trip.totalDuration ?? 24)
        }

        scheduleNextAutonomousAction(after: 8...15)
    }

    private func startOneShot(_ action: PetAction, duration: Int) {
        settleVerticalMotion()
        activeAction = action
        actionTicksRemaining = max(1, duration)
        animationTick = 0
        runDistanceRemaining = 0
        jumpTicksRemaining = 0
        jumpTick = 0
    }

    private func jumpInPlace() {
        settleVerticalMotion()
        activeAction = .hop
        actionTicksRemaining = spriteSet?.hop.totalDuration ?? 26
        animationTick = 0
        jumpTick = 0
        jumpTicksRemaining = 26
    }

    private func startRunning(maxDistance: CGFloat = 340, forcedDirection: CGFloat? = nil) {
        guard let window else {
            jumpInPlace()
            return
        }

        let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        var direction: CGFloat = forcedDirection ?? (window.frame.midX < visibleFrame.midX ? -1 : 1)
        let available = direction > 0
            ? visibleFrame.maxX - window.frame.maxX - 12
            : window.frame.minX - visibleFrame.minX - 12

        if forcedDirection == nil && available < 70 {
            direction *= -1
        }

        let correctedAvailable = direction > 0
            ? visibleFrame.maxX - window.frame.maxX - 12
            : window.frame.minX - visibleFrame.minX - 12

        guard correctedAvailable > 25 else {
            jumpInPlace()
            return
        }

        runDirection = direction
        facingDirection = direction
        activeAction = .run
        actionTicksRemaining = 0
        animationTick = 0
        runDistanceRemaining = min(maxDistance, correctedAvailable)
        jumpTick = 0
        jumpTicksRemaining = 0
    }

    private func showInteractionPanel() {
        if let interactionPanel, interactionPanel.isVisible {
            closeInteractionPanel()
            return
        }

        closeInteractionPanel()

        let panel = InteractionPanelWindow(
            isAlwaysOnTop: isAlwaysOnTop,
            onJump: { [weak self] in self?.performManualPanelAction(.jump) },
            onBow: { [weak self] in self?.performManualPanelAction(.bow) },
            onPose: { [weak self] in self?.performManualPanelAction(.pose) },
            onTrip: { [weak self] in self?.performManualPanelAction(.trip) },
            onRunLeft: { [weak self] in self?.performManualPanelAction(.runLeft) },
            onRunRight: { [weak self] in self?.performManualPanelAction(.runRight) },
            onSmaller: { [weak self] in
                self?.markInteraction()
                self?.resizeWindow(by: 0.88)
            },
            onBigger: { [weak self] in
                self?.markInteraction()
                self?.resizeWindow(by: 1.12)
            },
            onToggleTop: { [weak self] in
                self?.markInteraction()
                return self?.toggleAlwaysOnTop() ?? false
            },
            onQuit: { [weak self] in self?.quit() }
        )

        panel.setFrameOrigin(preferredInteractionPanelOrigin(for: InteractionPanelWindow.panelSize))
        panel.orderFront(nil)
        interactionPanel = panel
    }

    private func closeInteractionPanel() {
        interactionPanel?.orderOut(nil)
        interactionPanel = nil
    }

    private func preferredInteractionPanelOrigin(for panelSize: NSSize) -> NSPoint {
        guard let window else {
            return NSPoint(x: 120, y: 120)
        }

        let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let gap: CGFloat = 12
        let rightOriginX = window.frame.maxX + gap
        let leftOriginX = window.frame.minX - panelSize.width - gap
        let rightSpace = visibleFrame.maxX - window.frame.maxX
        let leftSpace = window.frame.minX - visibleFrame.minX
        let canFitRight = rightOriginX + panelSize.width <= visibleFrame.maxX - 8
        let canFitLeft = leftOriginX >= visibleFrame.minX + 8

        var origin = NSPoint(
            x: rightSpace >= leftSpace ? rightOriginX : leftOriginX,
            y: window.frame.midY - panelSize.height / 2
        )

        if !canFitRight && canFitLeft {
            origin.x = leftOriginX
        } else if canFitRight && !canFitLeft {
            origin.x = rightOriginX
        }

        origin.x = min(max(origin.x, visibleFrame.minX + 8), visibleFrame.maxX - panelSize.width - 8)
        origin.y = min(max(origin.y, visibleFrame.minY + 8), visibleFrame.maxY - panelSize.height - 8)
        return origin
    }

    @objc private func makeBigger() {
        resizeWindow(by: 1.12)
    }

    @objc private func makeSmaller() {
        resizeWindow(by: 0.88)
    }

    private func resizeWindow(by factor: CGFloat) {
        guard let window else { return }
        let old = window.frame
        let width = min(420, max(60, old.width * factor))
        let height = min(500, max(70, old.height * factor))
        let newFrame = NSRect(
            x: old.midX - width / 2,
            y: old.midY - height / 2,
            width: width,
            height: height
        )
        window.setFrame(newFrame, display: true, animate: true)
    }

    @discardableResult
    private func toggleAlwaysOnTop() -> Bool {
        guard let window else { return isAlwaysOnTop }
        isAlwaysOnTop.toggle()
        window.level = isAlwaysOnTop ? .floating : .normal
        return isAlwaysOnTop
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: PetWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let size = NSSize(width: 115, height: 140)
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let origin = NSPoint(x: screen.maxX - size.width - 90, y: screen.minY + 80)

        let petWindow = PetWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        petWindow.isOpaque = false
        petWindow.backgroundColor = .clear
        petWindow.hasShadow = true
        petWindow.level = .floating
        petWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        petWindow.ignoresMouseEvents = false

        let spriteSet = SpriteSet.load()
        let petImage = loadPetImage()
        let petView = PetView(image: petImage, spriteSet: spriteSet)
        petWindow.contentView = petView
        petWindow.makeKeyAndOrderFront(nil)
        petWindow.makeFirstResponder(petView)

        self.window = petWindow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

func loadPetImage() -> NSImage? {
    let fileManager = FileManager.default
    let current = URL(fileURLWithPath: fileManager.currentDirectoryPath)
    let executable = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
    let parent = executable.deletingLastPathComponent()
    let resources = Bundle.main.resourceURL

    let names = ["pet.png", "pet.jpg", "pet.jpeg"]
    var folders = [
        current,
        current.appendingPathComponent("assets"),
        executable,
        executable.appendingPathComponent("assets"),
        parent.appendingPathComponent("assets")
    ]

    if let resources {
        folders.append(resources)
        folders.append(resources.appendingPathComponent("assets"))
    }

    for folder in folders {
        for name in names {
            let url = folder.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: url.path), let image = NSImage(contentsOf: url) else {
                continue
            }
            return imageByRemovingWhiteBackground(image) ?? image
        }
    }

    return nil
}

func imageByRemovingWhiteBackground(_ image: NSImage) -> NSImage? {
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

    let width = cgImage.width
    let height = cgImage.height
    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

    guard let context = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: bitmapInfo.rawValue
    ) else {
        return nil
    }

    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

    func pixelOffset(_ x: Int, _ y: Int) -> Int {
        y * bytesPerRow + x * bytesPerPixel
    }

    func isBackgroundCandidate(_ offset: Int) -> Bool {
        let red = Int(pixels[offset])
        let green = Int(pixels[offset + 1])
        let blue = Int(pixels[offset + 2])
        let alpha = Int(pixels[offset + 3])
        let brightest = max(red, green, blue)
        let darkest = min(red, green, blue)
        let colorSpread = brightest - darkest

        if alpha < 8 {
            return true
        }

        return (darkest >= 228 && colorSpread <= 42) || darkest >= 246
    }

    var isBackground = [Bool](repeating: false, count: width * height)
    var queue: [Int] = []
    queue.reserveCapacity(width * height / 4)

    func enqueueBackground(_ x: Int, _ y: Int) {
        guard x >= 0, x < width, y >= 0, y < height else { return }

        let position = y * width + x
        guard !isBackground[position] else { return }
        guard isBackgroundCandidate(pixelOffset(x, y)) else { return }

        isBackground[position] = true
        queue.append(position)
    }

    for x in 0..<width {
        enqueueBackground(x, 0)
        enqueueBackground(x, height - 1)
    }

    for y in 0..<height {
        enqueueBackground(0, y)
        enqueueBackground(width - 1, y)
    }

    var cursor = 0
    while cursor < queue.count {
        let position = queue[cursor]
        cursor += 1

        let x = position % width
        let y = position / width
        enqueueBackground(x + 1, y)
        enqueueBackground(x - 1, y)
        enqueueBackground(x, y + 1)
        enqueueBackground(x, y - 1)
    }

    var visitedCandidate = [Bool](repeating: false, count: width * height)
    let largeInteriorArea = max(180, (width * height) / 1300)
    let largeInteriorWidth = max(18, width / 24)
    let largeInteriorHeight = max(20, height / 24)

    func markLargeInteriorWhiteComponents() {
        for start in 0..<(width * height) {
            guard !isBackground[start], !visitedCandidate[start] else { continue }

            let startX = start % width
            let startY = start / width
            guard isBackgroundCandidate(pixelOffset(startX, startY)) else {
                visitedCandidate[start] = true
                continue
            }

            var component: [Int] = []
            var componentQueue = [start]
            var componentCursor = 0
            var minX = startX
            var maxX = startX
            var minY = startY
            var maxY = startY
            visitedCandidate[start] = true

            while componentCursor < componentQueue.count {
                let position = componentQueue[componentCursor]
                componentCursor += 1
                component.append(position)

                let x = position % width
                let y = position / width
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)

                let neighbors = [
                    (x + 1, y),
                    (x - 1, y),
                    (x, y + 1),
                    (x, y - 1)
                ]

                for (neighborX, neighborY) in neighbors {
                    guard neighborX >= 0, neighborX < width, neighborY >= 0, neighborY < height else {
                        continue
                    }

                    let neighborPosition = neighborY * width + neighborX
                    guard !isBackground[neighborPosition], !visitedCandidate[neighborPosition] else {
                        continue
                    }

                    visitedCandidate[neighborPosition] = true
                    guard isBackgroundCandidate(pixelOffset(neighborX, neighborY)) else {
                        continue
                    }

                    componentQueue.append(neighborPosition)
                }
            }

            let componentWidth = maxX - minX + 1
            let componentHeight = maxY - minY + 1
            let isLargeInteriorBackground = component.count >= largeInteriorArea
                || componentWidth >= largeInteriorWidth
                || componentHeight >= largeInteriorHeight

            if isLargeInteriorBackground {
                for position in component {
                    isBackground[position] = true
                }
            }
        }
    }

    markLargeInteriorWhiteComponents()

    func hasBackgroundNeighbor(_ x: Int, _ y: Int, radius: Int) -> Bool {
        for neighborY in max(0, y - radius)...min(height - 1, y + radius) {
            for neighborX in max(0, x - radius)...min(width - 1, x + radius) {
                if isBackground[neighborY * width + neighborX] {
                    return true
                }
            }
        }
        return false
    }

    func scalePixelAlpha(at offset: Int, by factor: CGFloat) {
        let bounded = min(1, max(0, factor))
        pixels[offset] = UInt8(CGFloat(pixels[offset]) * bounded)
        pixels[offset + 1] = UInt8(CGFloat(pixels[offset + 1]) * bounded)
        pixels[offset + 2] = UInt8(CGFloat(pixels[offset + 2]) * bounded)
        pixels[offset + 3] = UInt8(CGFloat(pixels[offset + 3]) * bounded)
    }

    for y in 0..<height {
        for x in 0..<width {
            let position = y * width + x
            let offset = pixelOffset(x, y)

            if isBackground[position] {
                pixels[offset] = 0
                pixels[offset + 1] = 0
                pixels[offset + 2] = 0
                pixels[offset + 3] = 0
                continue
            }

            guard hasBackgroundNeighbor(x, y, radius: 2) else { continue }

            let red = Int(pixels[offset])
            let green = Int(pixels[offset + 1])
            let blue = Int(pixels[offset + 2])
            let brightest = max(red, green, blue)
            let darkest = min(red, green, blue)
            let colorSpread = brightest - darkest

            if darkest > 172 && colorSpread < 52 {
                let keep = CGFloat(245 - darkest) / 73
                scalePixelAlpha(at: offset, by: keep)
            }
        }
    }

    let data = Data(pixels)
    guard
        let provider = CGDataProvider(data: data as CFData),
        let output = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    else {
        return nil
    }

    return NSImage(cgImage: output, size: image.size)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
