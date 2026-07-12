import AppKit
import Darwin

// MARK: - Pet window

final class PetWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - App coordinator: lifecycle, settings toggles, system integration

final class AppCoordinator: NSObject, NSApplicationDelegate {
    private var window: PetWindow?
    private var petView: PetView?
    private var controller: PetController?
    private var tray: TrayController?
    let pomodoro = Pomodoro()
    private var previousPomodoroPhase: Pomodoro.Phase = .idle
    private var autosaveTimer: Timer?

    private var save: SaveManager { SaveManager.shared }
    private var settings: Settings { save.data.settings }

    var isPetVisible: Bool { window?.isVisible ?? false }

    // MARK: Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        logInfo("App launched (pid \(ProcessInfo.processInfo.processIdentifier))")

        save.settleOfflineTime()
        save.update {
            $0.totals.launches += 1
            $0.daily.rolloverIfNeeded(today: todayString())
        }

        let sprites = SpriteLibrary.load()
        let petImage = sprites == nil ? loadPetImage() : nil
        let controller = PetController(sprites: sprites)
        self.controller = controller

        let petWindow = makeWindow()
        let petView = PetView(image: petImage, sprites: sprites, controller: controller)
        petView.coordinator = self
        petWindow.contentView = petView
        petWindow.makeKeyAndOrderFront(nil)
        petWindow.makeFirstResponder(petView)
        self.window = petWindow
        self.petView = petView

        if settings.clickThrough {
            // Persisted click-through: honor it but tell the user how to escape.
            petWindow.ignoresMouseEvents = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                self?.controller?.emitBubble(category: "clickthrough_on", now: ProcessInfo.processInfo.systemUptime)
            }
        }

        tray = TrayController(coordinator: self)
        registerHotkeys()
        wirePomodoro()
        observeSystemEvents()

        petView.applyGravityIfNeeded()

        autosaveTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            SaveManager.shared.saveIfNeeded()
        }
    }

    private func makeWindow() -> PetWindow {
        let defaultSize = NSSize(width: 115, height: 140)
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)

        var frame = NSRect(
            origin: NSPoint(x: screen.maxX - defaultSize.width - 90, y: screen.minY + 80),
            size: defaultSize
        )

        if settings.restorePosition,
           let x = save.data.windowX, let y = save.data.windowY {
            let width = save.data.windowWidth ?? Double(defaultSize.width)
            let height = save.data.windowHeight ?? Double(defaultSize.height)
            let candidate = NSRect(x: x, y: y, width: width, height: height)
            let onScreen = NSScreen.screens.contains {
                $0.visibleFrame.insetBy(dx: -20, dy: -20).intersects(candidate)
            }
            if onScreen { frame = candidate }
        }

        let petWindow = PetWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        petWindow.isOpaque = false
        petWindow.backgroundColor = .clear
        petWindow.hasShadow = true
        petWindow.level = settings.alwaysOnTop ? .floating : .normal
        petWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        petWindow.ignoresMouseEvents = false
        petWindow.isReleasedWhenClosed = false
        return petWindow
    }

    // MARK: Global hotkeys

    private func registerHotkeys() {
        let hk = HotkeyManager.shared
        hk.register(keyCode: KeyCode.p, modifiers: ctrlShift, description: "⌃⇧P 显示/隐藏") { [weak self] in
            self?.togglePetVisibility()
        }
        hk.register(keyCode: KeyCode.j, modifiers: ctrlShift, description: "⌃⇧J 跳跃") { [weak self] in
            self?.controller?.userAction("hop")
        }
        hk.register(keyCode: KeyCode.r, modifiers: ctrlShift, description: "⌃⇧R 随机动作") { [weak self] in
            self?.randomAction()
        }
        hk.register(keyCode: KeyCode.s, modifiers: ctrlShift, description: "⌃⇧S 睡觉/起床") { [weak self] in
            self?.controller?.userAction("sleep")
        }
        hk.register(keyCode: KeyCode.e, modifiers: ctrlShift, description: "⌃⇧E 十万伏特") { [weak self] in
            self?.controller?.userAction("thunder")
        }
        hk.register(keyCode: KeyCode.h, modifiers: ctrlShift, description: "⌃⇧H 回到主屏") { [weak self] in
            self?.recallToMainScreen()
        }
        hk.register(keyCode: KeyCode.l, modifiers: ctrlShift, description: "⌃⇧L 锁定位置") { [weak self] in
            self?.toggleLockPosition()
        }
        hk.register(keyCode: KeyCode.g, modifiers: ctrlShift, description: "⌃⇧G 鼠标穿透") { [weak self] in
            self?.toggleClickThrough()
        }
    }

    // MARK: Pomodoro wiring

    private func wirePomodoro() {
        pomodoro.onPhaseChange = { [weak self] phase in
            guard let self, let controller = self.controller else { return }
            let now = ProcessInfo.processInfo.systemUptime
            defer { self.previousPomodoroPhase = phase }

            switch phase {
            case .focus:
                if case .focus = self.previousPomodoroPhase { return }
                controller.focusMode = true
                controller.emitBubble(category: "pomodoro_start", now: now)
            case .rest:
                controller.focusMode = false
                controller.emitBubble(category: "pomodoro_done", now: now)
                controller.userAction("celebrate")
            case .idle:
                controller.focusMode = false
                if case .rest = self.previousPomodoroPhase {
                    controller.emitBubble(category: "pomodoro_break_done", now: now)
                }
                self.tray?.updateTitle("⚡️")
            }
        }
        pomodoro.onTick = { [weak self] phase in
            switch phase {
            case .idle:
                self?.tray?.updateTitle("⚡️")
            case .focus(let remaining):
                self?.tray?.updateTitle("🍅\(Pomodoro.format(remaining))")
            case .rest(let remaining):
                self?.tray?.updateTitle("☕️\(Pomodoro.format(remaining))")
            }
        }
    }

    // MARK: System events

    private func observeSystemEvents() {
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(
            self, selector: #selector(systemWillSleep),
            name: NSWorkspace.willSleepNotification, object: nil
        )
        workspace.addObserver(
            self, selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(activateFromOtherInstance),
            name: Notification.Name("com.pikachupet.activate"), object: nil
        )
    }

    @objc private func systemWillSleep() {
        logInfo("System going to sleep; pausing")
        petView?.pauseTimer()
        save.saveIfNeeded(force: true)
    }

    @objc private func systemDidWake() {
        logInfo("System woke up; resuming")
        petView?.resumeTimer()
        petView?.validatePosition()
    }

    @objc private func screensChanged() {
        logInfo("Screen configuration changed; revalidating position")
        petView?.validatePosition()
        petView?.applyGravityIfNeeded()
    }

    @objc private func activateFromOtherInstance() {
        logInfo("Second launch detected; showing pet")
        showPet()
    }

    // MARK: Actions exposed to menus / hotkeys

    func randomAction() {
        showPet()
        controller?.randomUserAction()
    }

    func togglePomodoro() {
        pomodoro.toggle()
    }

    func showStatusBubble() {
        guard let controller else { return }
        showPet()
        controller.showBubbleText(controller.statusSummary())
    }

    func recallToMainScreen() {
        showPet()
        petView?.recallToMainScreen()
    }

    func togglePetVisibility() {
        isPetVisible ? hidePet() : showPet()
    }

    func hidePet() {
        window?.orderOut(nil)
        petView?.closeInteractionPanel()
        controller?.setHidden(true)
    }

    func showPet() {
        guard let window else { return }
        if !window.isVisible {
            window.makeKeyAndOrderFront(nil)
            controller?.setHidden(false)
            petView?.validatePosition()
        }
    }

    func savePetPosition() {
        guard let frame = window?.frame else { return }
        save.update {
            $0.windowX = frame.origin.x
            $0.windowY = frame.origin.y
            $0.windowWidth = frame.width
            $0.windowHeight = frame.height
        }
    }

    // MARK: Settings toggles

    private func flip(_ mutate: @escaping (inout Settings) -> Void) {
        save.update { mutate(&$0.settings) }
        save.saveIfNeeded()
    }

    func toggleQuietMode() {
        flip { $0.quietMode.toggle() }
    }

    func toggleLockPosition() {
        flip { $0.positionLocked.toggle() }
        if settings.positionLocked {
            controller?.emitBubble(category: "locked", now: ProcessInfo.processInfo.systemUptime)
        }
    }

    func toggleClickThrough() {
        flip { $0.clickThrough.toggle() }
        window?.ignoresMouseEvents = settings.clickThrough
        if settings.clickThrough {
            controller?.emitBubble(category: "clickthrough_on", now: ProcessInfo.processInfo.systemUptime)
        }
    }

    func toggleGravity() {
        flip { $0.gravityEnabled.toggle() }
        petView?.applyGravityIfNeeded()
    }

    func toggleBubbles() {
        flip { $0.bubblesEnabled.toggle() }
    }

    func toggleAutoSleep() {
        flip { $0.autoSleepEnabled.toggle() }
    }

    func toggleReduceFlashing() {
        flip { $0.reduceFlashing.toggle() }
    }

    func toggleAlwaysOnTop() {
        flip { $0.alwaysOnTop.toggle() }
        window?.level = settings.alwaysOnTop ? .floating : .normal
        petView?.setPanelLevel(alwaysOnTop: settings.alwaysOnTop)
    }

    // MARK: Shutdown

    func applicationWillTerminate(_ notification: Notification) {
        savePetPosition()
        save.saveIfNeeded(force: true)
        HotkeyManager.shared.unregisterAll()
        autosaveTimer?.invalidate()
        logInfo("App terminating")
        Logger.shared.flushAndClose()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

// MARK: - Single instance lock (flock on a file in Application Support)

func acquireSingleInstanceLock() -> Bool {
    let path = AppPaths.lockFile.path
    let fd = open(path, O_CREAT | O_RDWR, 0o644)
    guard fd >= 0 else { return true }   // can't lock -> don't block launching
    if flock(fd, LOCK_EX | LOCK_NB) != 0 {
        close(fd)
        return false
    }
    // Deliberately leak fd: the lock lives for the process lifetime.
    return true
}

// MARK: - Entry point

let arguments = CommandLine.arguments

if arguments.contains("--selftest") {
    exit(runSelfTests() ? 0 : 1)
}

if !acquireSingleInstanceLock() {
    // Another instance is running: wake it up and exit quietly.
    DistributedNotificationCenter.default().postNotificationName(
        Notification.Name("com.pikachupet.activate"),
        object: nil,
        userInfo: nil,
        deliverImmediately: true
    )
    print("PikachuPet is already running; activated the existing instance.")
    exit(0)
}

let app = NSApplication.shared
let coordinator = AppCoordinator()
app.delegate = coordinator
app.run()
