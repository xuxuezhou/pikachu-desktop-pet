import AppKit
import CoreGraphics

// MARK: - Pet view: rendering + input + lightweight physics.
// Decisions (what/when/why) live in PetController; this class executes them.

final class PetView: NSView, PetControllerDelegate {
    let controller: PetController
    weak var coordinator: AppCoordinator?

    private let petImage: NSImage?
    private let sprites: SpriteLibrary?

    private var timer: Timer?
    private var phase: CGFloat = 0
    private var animationTick = 0
    private var lastRenderSignature = 0
    private var safetyCheckCountdown = 60

    // Current mechanical action
    private var activeAnimName: String?
    private var actionTicksRemaining = 0
    private var jumpTick = 0
    private var jumpTicksRemaining = 0
    private var runDistanceRemaining: CGFloat = 0
    private var runDirection: CGFloat = 1
    private var facingDirection: CGFloat = 1
    private var currentWindowLift: CGFloat = 0
    private var thunderTicksRemaining = 0
    private var sleepingVisual = false

    // Falling / toss physics (window-space, points per tick)
    private var isFalling = false
    private var fallVelocity = CGPoint.zero
    private static let gravityPerTick: CGFloat = 2.6
    private static let maxFallSpeed: CGFloat = 42
    private static let maxTossSpeed = CGPoint(x: 52, y: 40)
    private static let hardLandingSpeed: CGFloat = 22

    // Dragging
    private var dragStartScreen: NSPoint = .zero
    private var dragStartOrigin: NSPoint = .zero
    private var dragDidMove = false
    private var dragSamples: [(time: TimeInterval, point: NSPoint)] = []
    private var lockedHintShown = false

    private var interactionPanel: InteractionPanelWindow?
    private let bubble = SpeechBubbleWindow()

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    private var settings: Settings { SaveManager.shared.data.settings }

    init(image: NSImage?, sprites: SpriteLibrary?, controller: PetController) {
        self.petImage = image
        self.sprites = sprites
        self.controller = controller
        super.init(frame: .zero)
        controller.delegate = self
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        startTimer()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        timer?.invalidate()
        interactionPanel?.close()
        bubble.close()
    }

    // MARK: Timer / frame loop

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.frameTick()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func pauseTimer() { timer?.invalidate(); timer = nil }

    func resumeTimer() {
        guard timer == nil else { return }
        startTimer()
    }

    private func frameTick() {
        phase += 0.08
        animationTick += 1
        controller.tick(now: ProcessInfo.processInfo.systemUptime)
        updateMotion()

        safetyCheckCountdown -= 1
        if safetyCheckCountdown <= 0 {
            safetyCheckCountdown = 60
            validatePosition()
        }

        if bubble.isVisible, let window {
            bubble.reposition(above: window.frame, on: window.screen)
        }

        let signature = renderSignature()
        if signature != lastRenderSignature {
            lastRenderSignature = signature
            needsDisplay = true
        }
    }

    /// Cheap hash of everything that affects pixels; redrawing is skipped
    /// when it doesn't change so an idle pet costs almost nothing.
    private func renderSignature() -> Int {
        var hasher = Hasher()
        if sprites == nil {
            hasher.combine(animationTick)   // vector/custom-image mode animates continuously
        } else {
            hasher.combine(activeAnimName ?? (sleepingVisual ? "sleep" : "idle"))
            hasher.combine(currentSpriteFrameIndex())
            hasher.combine(Int(currentWindowLift))
            if sleepingVisual { hasher.combine(animationTick / 8) }
            if thunderTicksRemaining > 0 { hasher.combine(animationTick / 2) }
            hasher.combine(runDistanceRemaining > 0)
            hasher.combine(facingDirection > 0)
        }
        return hasher.finalize()
    }

    private func currentSpriteFrameIndex() -> Int {
        guard let sprites else { return 0 }
        if sleepingVisual { return 0 }
        guard let name = activeAnimName, let anim = sprites.animation(name) else {
            return sprites.animation("Idle")?.frameIndex(at: animationTick) ?? 0
        }
        return anim.frameIndex(at: animationTick)
    }

    // MARK: Motion update

    private func updateMotion() {
        if thunderTicksRemaining > 0 { thunderTicksRemaining -= 1 }

        if actionTicksRemaining > 0 {
            actionTicksRemaining -= 1
            if actionTicksRemaining == 0 && runDistanceRemaining <= 0 && jumpTicksRemaining <= 0 {
                finishMechanics()
            }
        }

        if jumpTicksRemaining > 0 {
            jumpTick += 1
            jumpTicksRemaining -= 1
            if jumpTicksRemaining == 0 {
                jumpTick = 0
                if actionTicksRemaining == 0 && runDistanceRemaining <= 0 {
                    finishMechanics()
                }
            }
        }

        guard let window else { return }

        if isFalling {
            stepFalling(window: window)
            return
        }

        var frame = window.frame
        let baseY = frame.origin.y - currentWindowLift
        let targetLift = currentMotionLift()
        frame.origin.y = baseY + targetLift
        currentWindowLift = targetLift

        guard runDistanceRemaining > 0 else {
            if frame.origin != window.frame.origin {
                window.setFrameOrigin(frame.origin)
            }
            return
        }

        let visibleFrame = screenVisibleFrame(for: window)
        let step = min(15, runDistanceRemaining) * runDirection
        let minX = visibleFrame.minX + 8
        let maxX = visibleFrame.maxX - frame.width - 8
        let nextX = min(max(frame.origin.x + step, minX), maxX)
        let moved = abs(nextX - frame.origin.x)

        if moved < 0.5 {
            runDistanceRemaining = 0
            window.setFrameOrigin(frame.origin)
            finishMechanics()
            return
        }

        frame.origin.x = nextX
        runDistanceRemaining -= moved
        window.setFrameOrigin(frame.origin)
        if runDistanceRemaining <= 0 {
            finishMechanics()
        }
    }

    private func finishMechanics() {
        activeAnimName = nil
        actionTicksRemaining = 0
        runDistanceRemaining = 0
        jumpTick = 0
        jumpTicksRemaining = 0
        thunderTicksRemaining = 0
        animationTick = 0
        controller.actionFinished()
        coordinator?.savePetPosition()
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

    // MARK: Falling / gravity

    private func groundY(for window: NSWindow) -> CGFloat {
        screenVisibleFrame(for: window).minY + 2
    }

    private func screenVisibleFrame(for window: NSWindow) -> NSRect {
        (window.screen ?? screenContaining(window.frame) ?? NSScreen.main)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
    }

    private func screenContaining(_ frame: NSRect) -> NSScreen? {
        NSScreen.screens.first { $0.frame.intersects(frame) }
    }

    private func beginFalling(velocity: CGPoint) {
        isFalling = true
        fallVelocity = CGPoint(
            x: min(max(velocity.x, -PetView.maxTossSpeed.x), PetView.maxTossSpeed.x),
            y: min(max(velocity.y, -PetView.maxTossSpeed.y), PetView.maxTossSpeed.y)
        )
        activeAnimName = nil
        actionTicksRemaining = 0
        jumpTicksRemaining = 0
        jumpTick = 0
        runDistanceRemaining = 0
        currentWindowLift = 0
    }

    private func stepFalling(window: NSWindow) {
        var frame = window.frame
        let visible = screenVisibleFrame(for: window)
        let ground = groundY(for: window)

        fallVelocity.y = max(fallVelocity.y - PetView.gravityPerTick, -PetView.maxFallSpeed)
        fallVelocity.x *= 0.985

        frame.origin.x += fallVelocity.x
        frame.origin.y += fallVelocity.y

        // Bounce softly off the side edges instead of escaping the screen.
        if frame.origin.x < visible.minX + 2 {
            frame.origin.x = visible.minX + 2
            fallVelocity.x = abs(fallVelocity.x) * 0.4
        } else if frame.origin.x > visible.maxX - frame.width - 2 {
            frame.origin.x = visible.maxX - frame.width - 2
            fallVelocity.x = -abs(fallVelocity.x) * 0.4
        }

        if frame.origin.y <= ground {
            frame.origin.y = ground
            let impact = abs(fallVelocity.y)
            isFalling = false
            fallVelocity = .zero
            window.setFrameOrigin(frame.origin)
            controller.landed(hard: impact >= PetView.hardLandingSpeed)
            coordinator?.savePetPosition()
            return
        }

        window.setFrameOrigin(frame.origin)
    }

    /// Drops the pet to the ground if gravity is on and it's floating.
    func applyGravityIfNeeded() {
        guard settings.gravityEnabled, !settings.positionLocked, let window else { return }
        guard !isFalling, controller.state == .idle || controller.state == .sleeping else { return }
        guard window.frame.origin.y > groundY(for: window) + 2 else { return }
        controller.dragEnded(willFall: true)
        beginFalling(velocity: .zero)
    }

    /// Safety net: if the window escaped every screen, bring it back.
    func validatePosition() {
        guard let window else { return }
        let frame = window.frame
        let onSomeScreen = NSScreen.screens.contains { screen in
            screen.visibleFrame.insetBy(dx: -40, dy: -40).intersects(frame)
        }
        guard !onSomeScreen else { return }

        let target = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let safe = NSPoint(
            x: target.maxX - frame.width - 90,
            y: settings.gravityEnabled ? target.minY + 2 : target.minY + 80
        )
        isFalling = false
        fallVelocity = .zero
        currentWindowLift = 0
        window.setFrameOrigin(safe)
        controller.recoveredFromOffscreen()
        coordinator?.savePetPosition()
    }

    func recallToMainScreen() {
        guard let window else { return }
        let target = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        settleVerticalMotion()
        isFalling = false
        window.setFrameOrigin(NSPoint(
            x: target.maxX - window.frame.width - 90,
            y: settings.gravityEnabled ? target.minY + 2 : target.minY + 80
        ))
        coordinator?.savePetPosition()
    }

    // MARK: PetControllerDelegate

    func petPerform(_ command: PetCommand) {
        switch command {
        case .playAnim(let name, let ticks):
            startOneShot(animName: name, duration: ticks)
        case .jump:
            jumpInPlace()
        case .run(let direction, let maxDistance):
            startRunning(maxDistance: maxDistance, forcedDirection: direction)
        case .setSleeping(let sleeping):
            setSleepingVisual(sleeping)
        case .showBubble(let text):
            showBubbleText(text)
        case .thunder(let ticks):
            startThunder(ticks: ticks)
        }
    }

    private func startOneShot(animName: String, duration: Int) {
        guard sprites != nil else {
            jumpInPlace()
            return
        }
        settleVerticalMotion()
        activeAnimName = animName
        actionTicksRemaining = max(1, duration)
        animationTick = 0
        runDistanceRemaining = 0
        jumpTicksRemaining = 0
        jumpTick = 0
    }

    private func jumpInPlace() {
        settleVerticalMotion()
        activeAnimName = "Hop"
        actionTicksRemaining = sprites?.animation("Hop")?.totalDuration ?? 26
        animationTick = 0
        jumpTick = 0
        jumpTicksRemaining = 26
    }

    private func startThunder(ticks: Int) {
        settleVerticalMotion()
        activeAnimName = "Swing"
        actionTicksRemaining = max(1, ticks)
        thunderTicksRemaining = settings.effectsEnabled ? max(1, ticks) : 0
        animationTick = 0
        runDistanceRemaining = 0
        jumpTicksRemaining = 0
        jumpTick = 0
    }

    private func startRunning(maxDistance: CGFloat, forcedDirection: CGFloat?) {
        guard let window else {
            jumpInPlace()
            return
        }

        let visibleFrame = screenVisibleFrame(for: window)
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
        activeAnimName = "Walk"
        actionTicksRemaining = 0
        animationTick = 0
        runDistanceRemaining = min(maxDistance, correctedAvailable)
        jumpTick = 0
        jumpTicksRemaining = 0
    }

    private func setSleepingVisual(_ sleeping: Bool) {
        sleepingVisual = sleeping
        if sleeping {
            settleVerticalMotion()
            activeAnimName = nil
            actionTicksRemaining = 0
            runDistanceRemaining = 0
            jumpTicksRemaining = 0
            jumpTick = 0
            thunderTicksRemaining = 0
        }
        needsDisplay = true
    }

    private func showBubbleText(_ text: String) {
        guard let window else { return }
        bubble.show(
            text: text,
            above: window.frame,
            on: window.screen,
            duration: settings.bubbleSeconds
        )
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()

        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()

        let usingSprites = sprites != nil
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

        if thunderTicksRemaining > 0 {
            drawThunderEffect(in: petRect)
        }

        if let sprites {
            drawActiveSprite(sprites, in: petRect)
        } else if let petImage {
            drawPetImage(petImage, in: petRect)
        } else {
            drawBuiltInPet(in: petRect)
        }

        if sleepingVisual {
            drawSleepIndicator(in: petRect)
        }

        context.restoreGState()
    }

    private func drawActiveSprite(_ sprites: SpriteLibrary, in rect: NSRect) {
        if sleepingVisual {
            if let idle = sprites.animation("Idle") {
                drawSprite(idle, in: rect, facing: .front, fixedFrame: 0)
            }
            return
        }

        guard let name = activeAnimName, let anim = sprites.animation(name) else {
            if let idle = sprites.animation("Idle") {
                drawSprite(idle, in: rect, facing: .front)
            }
            return
        }

        let facing: Facing
        if name == "Walk" {
            facing = runDirection > 0 ? .right : .left
        } else {
            facing = .front
        }
        drawSprite(anim, in: rect, facing: facing)
    }

    private func drawSprite(
        _ animation: SpriteAnimation,
        in rect: NSRect,
        facing: Facing,
        fixedFrame: Int? = nil
    ) {
        guard animation.image.size.width > 0, animation.image.size.height > 0 else { return }

        let frameIndex = fixedFrame ?? animation.frameIndex(at: animationTick)
        let row = animation.row(for: facing)
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

    private func drawSleepIndicator(in rect: NSRect) {
        let bob = sin(phase * 0.6) * 3
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .bold),
            .foregroundColor: NSColor(calibratedRed: 0.45, green: 0.55, blue: 0.95, alpha: 0.9),
        ]
        ("Z z z" as NSString).draw(
            at: NSPoint(x: rect.midX + 8, y: rect.minY + 2 + bob),
            withAttributes: attributes
        )
    }

    private func drawThunderEffect(in rect: NSRect) {
        let flicker: CGFloat
        if settings.reduceFlashing {
            flicker = 0.30   // photosensitivity option: steady soft glow, no strobing
        } else {
            flicker = 0.25 + 0.2 * abs(sin(CGFloat(animationTick) * 0.9))
        }

        let glowRect = rect.insetBy(dx: -4, dy: -2)
        let glow = NSBezierPath(ovalIn: glowRect)
        NSColor(calibratedRed: 1.0, green: 0.92, blue: 0.35, alpha: flicker).setFill()
        glow.fill()

        guard !settings.reduceFlashing else { return }

        // Small zigzag bolts around the pet; bounded to the window, brief.
        let boltColor = NSColor(calibratedRed: 1.0, green: 0.85, blue: 0.1, alpha: 0.9)
        boltColor.setStroke()
        let seeds: [(CGFloat, CGFloat)] = [(0.12, 0.2), (0.85, 0.25), (0.2, 0.75), (0.9, 0.7)]
        for (index, seed) in seeds.enumerated() {
            guard (animationTick / 3 + index) % 2 == 0 else { continue }
            let startX = rect.minX + seed.0 * rect.width
            let startY = rect.minY + seed.1 * rect.height
            let bolt = NSBezierPath()
            bolt.move(to: NSPoint(x: startX, y: startY))
            bolt.line(to: NSPoint(x: startX + 6, y: startY + 7))
            bolt.line(to: NSPoint(x: startX + 1, y: startY + 9))
            bolt.line(to: NSPoint(x: startX + 8, y: startY + 18))
            bolt.lineWidth = 2
            bolt.stroke()
        }
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

    // MARK: Mouse input

    override func mouseDown(with event: NSEvent) {
        controller.markInteraction()
        window?.makeFirstResponder(self)

        if event.modifierFlags.contains(.option) {
            showInteractionPanel()
            dragDidMove = true
            return
        }

        closeInteractionPanel()
        dragStartScreen = NSEvent.mouseLocation
        dragStartOrigin = window?.frame.origin ?? .zero
        dragDidMove = false
        dragSamples = [(ProcessInfo.processInfo.systemUptime, NSEvent.mouseLocation)]
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let current = NSEvent.mouseLocation
        let delta = NSPoint(x: current.x - dragStartScreen.x, y: current.y - dragStartScreen.y)

        if settings.positionLocked {
            if hypot(delta.x, delta.y) > 6 && !lockedHintShown {
                lockedHintShown = true
                controller.emitBubble(category: "locked", now: ProcessInfo.processInfo.systemUptime)
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                    self?.lockedHintShown = false
                }
            }
            return
        }

        if hypot(delta.x, delta.y) > 6 && !dragDidMove {
            dragDidMove = true
            settleVerticalMotion()
            isFalling = false
            fallVelocity = .zero
            runDistanceRemaining = 0
            jumpTicksRemaining = 0
            jumpTick = 0
            actionTicksRemaining = 0
            thunderTicksRemaining = 0
            activeAnimName = nil
            controller.dragBegan()
        }

        guard dragDidMove else { return }

        let now = ProcessInfo.processInfo.systemUptime
        dragSamples.append((now, current))
        dragSamples.removeAll { now - $0.time > 0.15 }

        window.setFrameOrigin(NSPoint(x: dragStartOrigin.x + delta.x, y: dragStartOrigin.y + delta.y))
    }

    override func mouseUp(with event: NSEvent) {
        if dragDidMove {
            endDrag()
            return
        }
        handleClick(event)
    }

    private func endDrag() {
        guard let window else { return }

        var velocity = CGPoint.zero
        if let first = dragSamples.first, let last = dragSamples.last, last.time > first.time {
            let dt = CGFloat(last.time - first.time)
            velocity = CGPoint(
                x: (last.point.x - first.point.x) / dt / 30,
                y: (last.point.y - first.point.y) / dt / 30
            )
        }
        dragSamples.removeAll()

        let shouldFall = settings.gravityEnabled
            && window.frame.origin.y > groundY(for: window) + 4

        if shouldFall {
            controller.dragEnded(willFall: true)
            beginFalling(velocity: velocity)
        } else {
            controller.dragEnded(willFall: false)
            clampIntoVisibleScreen()
            coordinator?.savePetPosition()
        }
    }

    /// After a drag the window must stay reachable on some screen.
    private func clampIntoVisibleScreen() {
        guard let window else { return }
        var frame = window.frame
        let visible = screenVisibleFrame(for: window)
        frame.origin.x = min(max(frame.origin.x, visible.minX - frame.width * 0.4), visible.maxX - frame.width * 0.6)
        frame.origin.y = min(max(frame.origin.y, visible.minY - 4), visible.maxY - frame.height * 0.5)
        if frame.origin != window.frame.origin {
            window.setFrameOrigin(frame.origin)
        }
    }

    private func handleClick(_ event: NSEvent) {
        if event.clickCount >= 2 {
            controller.handleDoubleClick()
            return
        }
        let location = convert(event.locationInWindow, from: nil)
        let region: PetController.ClickRegion = location.y < bounds.height * 0.45 ? .head : .body
        controller.handleClick(region: region)
    }

    override func rightMouseDown(with event: NSEvent) {
        controller.markInteraction()
        showContextMenu(with: event)
    }

    // MARK: Context menu

    private func showContextMenu(with event: NSEvent) {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let interact = NSMenu()
        interact.autoenablesItems = false
        interact.addItem(makeItem("抚摸") { [weak self] in self?.controller.handleClick(region: .head) })
        interact.addItem(makeItem("喂食（树果）") { [weak self] in self?.controller.feed() })
        interact.addItem(makeItem("玩耍（跳跃）") { [weak self] in self?.controller.userAction("hop") })
        interact.addItem(makeItem("随机动作") { [weak self] in self?.controller.randomUserAction() })
        menu.addItem(submenu("互动", interact))

        let actions = NSMenu()
        actions.autoenablesItems = false
        actions.addItem(makeItem("鞠躬") { [weak self] in self?.controller.userAction("nod") })
        actions.addItem(makeItem("摆姿势") { [weak self] in self?.controller.userAction("pose") })
        actions.addItem(makeItem("张望") { [weak self] in self?.controller.userAction("lookup") })
        actions.addItem(makeItem("十万伏特 ⚡️") { [weak self] in self?.controller.userAction("thunder") })
        actions.addItem(makeItem(controller.isSleeping ? "起床" : "睡觉") { [weak self] in self?.controller.userAction("sleep") })
        actions.addItem(makeItem("向左跑") { [weak self] in self?.controller.userAction("runLeft") })
        actions.addItem(makeItem("向右跑") { [weak self] in self?.controller.userAction("runRight") })
        menu.addItem(submenu("动作", actions))

        if let coordinator {
            let modes = NSMenu()
            modes.autoenablesItems = false
            modes.addItem(toggleItem("安静模式", isOn: settings.quietMode) { coordinator.toggleQuietMode() })
            modes.addItem(toggleItem("锁定位置", isOn: settings.positionLocked) { coordinator.toggleLockPosition() })
            modes.addItem(toggleItem("鼠标穿透", isOn: settings.clickThrough) { coordinator.toggleClickThrough() })
            modes.addItem(toggleItem("重力", isOn: settings.gravityEnabled) { coordinator.toggleGravity() })
            modes.addItem(toggleItem("气泡", isOn: settings.bubblesEnabled) { coordinator.toggleBubbles() })
            modes.addItem(toggleItem("自动睡眠", isOn: settings.autoSleepEnabled) { coordinator.toggleAutoSleep() })
            modes.addItem(toggleItem("特效防闪烁", isOn: settings.reduceFlashing) { coordinator.toggleReduceFlashing() })
            modes.addItem(toggleItem("窗口置顶", isOn: settings.alwaysOnTop) { coordinator.toggleAlwaysOnTop() })
            menu.addItem(submenu("模式", modes))

            let tools = NSMenu()
            tools.autoenablesItems = false
            tools.addItem(makeItem(coordinator.pomodoro.menuTitle) { coordinator.togglePomodoro() })
            tools.addItem(makeItem("今日状态") { coordinator.showStatusBubble() })
            tools.addItem(makeItem("回到主屏幕") { [weak self] in self?.recallToMainScreen() })
            menu.addItem(submenu("工具", tools))

            menu.addItem(NSMenuItem.separator())
            menu.addItem(makeItem("控制面板") { [weak self] in self?.showInteractionPanel() })
            menu.addItem(makeItem("隐藏皮卡丘") { coordinator.hidePet() })
            menu.addItem(makeItem("退出") { NSApp.terminate(nil) })
        }

        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    private func makeItem(_ title: String, action: @escaping () -> Void) -> NSMenuItem {
        let item = ClosureMenuItem(title: title, closure: action)
        item.isEnabled = true
        return item
    }

    private func toggleItem(_ title: String, isOn: Bool, action: @escaping () -> Void) -> NSMenuItem {
        let item = makeItem(title, action: action)
        item.state = isOn ? .on : .off
        return item
    }

    private func submenu(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        guard let key = event.charactersIgnoringModifiers?.lowercased().first else {
            super.keyDown(with: event)
            return
        }

        switch key {
        case "w": controller.userAction("hop")
        case "a": controller.userAction("runLeft")
        case "d": controller.userAction("runRight")
        case "b": controller.userAction("nod")
        case "p": controller.userAction("pose")
        case "s": controller.userAction("trip")
        case "e": controller.userAction("thunder")
        case "z": controller.userAction("sleep")
        default: super.keyDown(with: event)
        }
    }

    // MARK: Interaction panel

    func showInteractionPanel() {
        if let interactionPanel, interactionPanel.isVisible {
            closeInteractionPanel()
            return
        }

        closeInteractionPanel()

        let panel = InteractionPanelWindow(
            isAlwaysOnTop: settings.alwaysOnTop,
            statusProvider: { [weak self] in
                guard let self else { return "" }
                let stats = SaveManager.shared.data.stats
                return "\(self.controller.mood.emoji) \(self.controller.mood.displayName) · ⚡️\(Int(stats.energy)) · 🍎\(Int(100 - stats.hunger)) · 💛\(Int(stats.affection))"
            },
            onJump: { [weak self] in self?.panelAction("hop") },
            onBow: { [weak self] in self?.panelAction("nod") },
            onPose: { [weak self] in self?.panelAction("pose") },
            onTrip: { [weak self] in self?.panelAction("trip") },
            onRunLeft: { [weak self] in self?.panelAction("runLeft") },
            onRunRight: { [weak self] in self?.panelAction("runRight") },
            onSmaller: { [weak self] in
                self?.controller.markInteraction()
                self?.resizeWindow(by: 0.88)
            },
            onBigger: { [weak self] in
                self?.controller.markInteraction()
                self?.resizeWindow(by: 1.12)
            },
            onToggleTop: { [weak self] in
                self?.coordinator?.toggleAlwaysOnTop()
                return self?.settings.alwaysOnTop ?? true
            },
            onQuit: { NSApp.terminate(nil) }
        )

        panel.setFrameOrigin(preferredInteractionPanelOrigin(for: InteractionPanelWindow.panelSize))
        panel.orderFront(nil)
        interactionPanel = panel
    }

    private func panelAction(_ id: String) {
        controller.userAction(id)
        closeInteractionPanel()
    }

    func closeInteractionPanel() {
        interactionPanel?.orderOut(nil)
        interactionPanel = nil
    }

    func setPanelLevel(alwaysOnTop: Bool) {
        interactionPanel?.level = alwaysOnTop ? .floating : .normal
    }

    private func preferredInteractionPanelOrigin(for panelSize: NSSize) -> NSPoint {
        guard let window else {
            return NSPoint(x: 120, y: 120)
        }

        let visibleFrame = screenVisibleFrame(for: window)
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

    private func resizeWindow(by factor: CGFloat) {
        guard let window else { return }
        settleVerticalMotion()
        let old = window.frame
        let width = min(420, max(60, old.width * factor))
        let height = min(500, max(70, old.height * factor))
        let newFrame = NSRect(
            x: old.midX - width / 2,
            y: settings.gravityEnabled ? old.origin.y : old.midY - height / 2,
            width: width,
            height: height
        )
        window.setFrame(newFrame, display: true, animate: true)
        coordinator?.savePetPosition()
    }

    // MARK: Built-in vector Pikachu fallback (unchanged from the original)

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
}

// MARK: - Closure-backed menu item

final class ClosureMenuItem: NSMenuItem {
    private let closure: () -> Void

    init(title: String, closure: @escaping () -> Void) {
        self.closure = closure
        super.init(title: title, action: #selector(invoke), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func invoke() {
        closure()
    }
}
