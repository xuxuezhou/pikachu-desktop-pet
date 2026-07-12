import Foundation
import CoreGraphics

// MARK: - Pet state machine

enum PetTopState: Equatable {
    case idle
    case acting(String)      // action id
    case running
    case sleeping
    case dragged
    case falling
    case hidden
}

// MARK: - Commands the controller sends to the view layer

enum PetCommand {
    case playAnim(name: String, ticks: Int)
    case jump
    case run(direction: CGFloat?, maxDistance: CGFloat)
    case setSleeping(Bool)
    case showBubble(String)
    case thunder(ticks: Int)
}

protocol PetControllerDelegate: AnyObject {
    func petPerform(_ command: PetCommand)
}

// MARK: - Controller: owns state, stats, behavior, cooldowns. UI-free.

final class PetController {
    weak var delegate: PetControllerDelegate?

    private(set) var state: PetTopState = .idle
    private(set) var mood: Mood = .neutral

    let sprites: SpriteLibrary?
    let dialogue: DialogueLibrary
    let rng: PetRandom
    private let cooldowns = CooldownTracker()

    var focusMode = false          // pomodoro running: stay quiet, minimal movement

    private var currentPriority = 0
    private var currentInterruptLevel = 0

    private var lastInteractionAt: Double
    private var nextAutonomousAt: Double
    private var statAccumulator: Double = 0
    private var lastTickAt: Double
    private var greeted = false
    private var launchAt: Double
    private var clickTimestamps: [Double] = []
    private var sleepStartedAt: Double = 0

    private var save: SaveManager { SaveManager.shared }
    private var settings: Settings { save.data.settings }

    init(sprites: SpriteLibrary?) {
        self.sprites = sprites
        let seed = SaveManager.shared.data.settings.behaviorSeed
        let rng = PetRandom(seed: seed)
        self.rng = rng
        self.dialogue = DialogueLibrary(rng: rng)
        let now = ProcessInfo.processInfo.systemUptime
        lastInteractionAt = now
        nextAutonomousAt = now + 12
        lastTickAt = now
        launchAt = now
        if seed != nil { logInfo("Behavior RNG seeded with \(seed!)") }
    }

    private var currentHour: Int {
        Calendar.current.component(.hour, from: Date())
    }

    private func minutesSinceInteraction(_ now: Double) -> Double {
        (now - lastInteractionAt) / 60
    }

    // MARK: Tick (called at 30 Hz by the view's timer)

    func tick(now: Double) {
        let dt = min(1.0, max(0, now - lastTickAt))
        lastTickAt = now
        statAccumulator += dt

        if statAccumulator >= 5 {
            let minutes = statAccumulator / 60
            statAccumulator = 0
            save.update { data in
                data.stats.tick(minutes: minutes, sleeping: self.state == .sleeping)
                data.daily.rolloverIfNeeded(today: todayString())
            }
            refreshMood(now: now)
        }

        if !greeted, now - launchAt > 2 {
            greeted = true
            greet(now: now)
        }

        switch state {
        case .sleeping:
            autoWakeIfNeeded(now: now)
        case .idle:
            maybeActAutonomously(now: now)
        default:
            break
        }
    }

    private func refreshMood(now: Double) {
        mood = deriveMood(
            stats: save.data.stats,
            minutesSinceInteraction: minutesSinceInteraction(now),
            hour: currentHour
        )
    }

    private func greet(now: Double) {
        let hour = currentHour
        let category: String
        switch hour {
        case 5..<11: category = "greeting_morning"
        case 11..<19: category = "greeting_day"
        default: category = "greeting_night"
        }
        save.update { $0.daily.rolloverIfNeeded(today: todayString()) }
        if !save.data.daily.greeted {
            save.update { $0.daily.greeted = true }
        }
        emitBubble(category: category, now: now)
    }

    // MARK: Autonomous behavior

    private func maybeActAutonomously(now: Double) {
        guard now >= nextAutonomousAt else { return }
        guard settings.autonomyLevel > 0.01, !focusMode else {
            scheduleNextAutonomous(now: now, range: 20...40)
            return
        }
        guard now - lastInteractionAt >= 10 else {
            scheduleNextAutonomous(now: now, range: 4...8)
            return
        }

        refreshMood(now: now)
        let context = BehaviorContext(
            stats: save.data.stats,
            mood: mood,
            hour: currentHour,
            personality: save.data.personality,
            quietMode: settings.quietMode,
            autoSleepEnabled: settings.autoSleepEnabled,
            effectsEnabled: settings.effectsEnabled,
            minutesSinceInteraction: minutesSinceInteraction(now)
        )
        let chosen = BehaviorSelector.choose(
            context: context,
            cooldownReady: { self.cooldowns.isReady($0, now: now) },
            rng: rng
        )

        if let chosen {
            if chosen == "bubble_idle" {
                emitBubble(category: BehaviorSelector.idleBubbleCategory(for: mood), now: now)
            } else {
                startAction(chosen, priority: ActionPriority.autonomous, now: now)
            }
        }

        let base: ClosedRange<Double> = 6...14
        let scale = max(0.25, min(4, 1.0 / max(0.25, settings.autonomyLevel)))
        scheduleNextAutonomous(now: now, range: (base.lowerBound * scale)...(base.upperBound * scale))
    }

    private func scheduleNextAutonomous(now: Double, range: ClosedRange<Double>) {
        nextAutonomousAt = now + rng.double(in: range)
    }

    // MARK: Action lifecycle

    /// Entry point for user commands (keys, hotkeys, menus, panel buttons).
    @discardableResult
    func userAction(_ id: String) -> Bool {
        markInteraction()
        let now = ProcessInfo.processInfo.systemUptime
        if state == .sleeping && id != "sleep" {
            wake(now: now, forced: true)
        }
        return startAction(id, priority: ActionPriority.user, now: now)
    }

    func randomUserAction() {
        let pool = ["hop", "pose", "nod", "trip", "lookup", "wander", "thunder"]
        let available = pool.filter { ActionCatalog.action($0) != nil }
        guard !available.isEmpty else { return }
        userAction(available[rng.int(in: 0..<available.count)])
    }

    @discardableResult
    private func startAction(_ id: String, priority: Int, now: Double) -> Bool {
        guard let def = ActionCatalog.action(id) else {
            logWarn("Unknown action requested: \(id)")
            return false
        }
        switch state {
        case .dragged, .falling, .hidden:
            return false
        case .sleeping:
            guard case .sleepToggle = def.kind else { return false }
        case .acting, .running:
            guard priority > currentInterruptLevel else { return false }
        case .idle:
            break
        }
        // Autonomous actions respect cooldowns strictly; user commands only
        // for expensive ones (thunder keeps its cooldown to stay special).
        if priority < ActionPriority.user || id == "thunder" {
            guard cooldowns.isReady(id, now: now) else { return false }
        }
        if save.data.stats.energy < def.minimumEnergy {
            emitBubble(category: "sleepy", now: now)
            return false
        }

        cooldowns.trigger(def, now: now)
        save.update { $0.stats.apply(def.effects) }

        switch def.kind {
        case .anim(let sheet):
            let ticks = sprites?.animation(sheet)?.totalDuration ?? 22
            state = .acting(id)
            currentPriority = priority
            currentInterruptLevel = def.interruptLevel
            delegate?.petPerform(.playAnim(name: sheet, ticks: ticks))
        case .jump:
            state = .acting(id)
            currentPriority = priority
            currentInterruptLevel = def.interruptLevel
            save.update { $0.totals.jumps += 1 }
            delegate?.petPerform(.jump)
        case .run(let direction, let maxDistance):
            state = .running
            currentPriority = priority
            currentInterruptLevel = def.interruptLevel
            delegate?.petPerform(.run(direction: direction, maxDistance: maxDistance))
        case .sleepToggle:
            if state == .sleeping {
                wake(now: now, forced: false)
            } else {
                enterSleep(now: now)
            }
        case .thunder:
            let ticks = sprites?.animation("Swing")?.totalDuration ?? 24
            state = .acting(id)
            currentPriority = priority
            currentInterruptLevel = def.interruptLevel
            save.update { $0.totals.thunders += 1 }
            delegate?.petPerform(.thunder(ticks: ticks))
        }

        if let category = def.bubbleCategory {
            emitBubble(category: category, now: now)
        }
        return true
    }

    /// Called by the view when the mechanics of the current action finished.
    func actionFinished() {
        switch state {
        case .acting, .running:
            state = .idle
            currentPriority = 0
            currentInterruptLevel = 0
        default:
            break
        }
    }

    // MARK: Sleep

    private func enterSleep(now: Double) {
        state = .sleeping
        sleepStartedAt = now
        delegate?.petPerform(.setSleeping(true))
        logInfo("Pet entered sleep")
    }

    func wake(now: Double, forced: Bool) {
        guard state == .sleeping else { return }
        state = .idle
        currentPriority = 0
        currentInterruptLevel = 0
        delegate?.petPerform(.setSleeping(false))
        emitBubble(category: "wake", now: now)
        if forced {
            save.update { $0.stats.stress = min(100, $0.stats.stress + 4) }
        }
        logInfo("Pet woke up (forced: \(forced))")
    }

    private func autoWakeIfNeeded(now: Double) {
        let sleptMinutes = (now - sleepStartedAt) / 60
        let hour = currentHour
        let isDaytime = hour >= 7 && hour < 22
        if save.data.stats.energy >= 98 && sleptMinutes > 2 {
            wake(now: now, forced: false)
        } else if isDaytime && sleptMinutes > 45 {
            wake(now: now, forced: false)
        }
    }

    var isSleeping: Bool { state == .sleeping }

    // MARK: Mouse interaction

    enum ClickRegion { case head, body }

    func handleClick(region: ClickRegion) {
        markInteraction()
        let now = ProcessInfo.processInfo.systemUptime

        if state == .sleeping {
            wake(now: now, forced: true)
            return
        }

        // Continuous-click protection: too many clicks in a short window
        // stresses the pet and eventually triggers an angry zap.
        clickTimestamps.append(now)
        clickTimestamps.removeAll { now - $0 > 4 }
        if clickTimestamps.count >= 6 {
            clickTimestamps.removeAll()
            save.update { $0.stats.apply(StatEffects(mood: -4, stress: 12)) }
            refreshMood(now: now)
            startAction("annoyed_zap", priority: ActionPriority.reaction, now: now)
            return
        }

        switch region {
        case .head:
            save.update {
                $0.daily.petsToday += 1
                $0.totals.pets += 1
            }
            startAction("pet_response", priority: ActionPriority.reaction, now: now)
        case .body:
            startAction("hop", priority: ActionPriority.reaction, now: now)
        }
    }

    func handleDoubleClick() {
        markInteraction()
        let now = ProcessInfo.processInfo.systemUptime
        if state == .sleeping {
            wake(now: now, forced: true)
            return
        }
        startAction("wander", priority: ActionPriority.reaction, now: now)
    }

    func feed() {
        markInteraction()
        let now = ProcessInfo.processInfo.systemUptime
        if state == .sleeping { wake(now: now, forced: true) }
        if save.data.stats.hunger < 8 {
            emitBubble(category: "full", now: now)
            return
        }
        save.update {
            $0.daily.feedsToday += 1
            $0.totals.feeds += 1
        }
        startAction("feed", priority: ActionPriority.reaction, now: now)
    }

    // MARK: Drag / physics events

    func dragBegan() {
        markInteraction()
        let now = ProcessInfo.processInfo.systemUptime
        if state == .sleeping {
            wake(now: now, forced: true)
        }
        state = .dragged
        currentPriority = ActionPriority.system
        currentInterruptLevel = ActionPriority.system
        save.update { $0.stats.stress = min(100, $0.stats.stress + 2) }
        if rng.chance(0.35) {
            emitBubble(category: "dragged", now: now)
        }
    }

    func dragEnded(willFall: Bool) {
        state = willFall ? .falling : .idle
        currentPriority = 0
        currentInterruptLevel = 0
        markInteraction()
    }

    func landed(hard: Bool) {
        state = .idle
        currentPriority = 0
        currentInterruptLevel = 0
        let now = ProcessInfo.processInfo.systemUptime
        if hard {
            save.update { $0.stats.apply(StatEffects(mood: -2, stress: 6)) }
            emitBubble(category: "landed_hard", now: now)
            startAction("trip", priority: ActionPriority.reaction, now: now)
        }
    }

    func recoveredFromOffscreen() {
        state = .idle
        emitBubble(category: "recovered", now: ProcessInfo.processInfo.systemUptime)
        logWarn("Pet recovered from off-screen position")
    }

    func setHidden(_ hidden: Bool) {
        if hidden {
            state = .hidden
        } else if state == .hidden {
            state = .idle
        }
    }

    func markInteraction() {
        let now = ProcessInfo.processInfo.systemUptime
        lastInteractionAt = now
        nextAutonomousAt = max(nextAutonomousAt, now + rng.double(in: 12...20))
    }

    // MARK: Bubbles

    func emitBubble(category: String, now: Double) {
        guard settings.bubblesEnabled else { return }
        let essential = ["pomodoro_done", "pomodoro_start", "pomodoro_break_done",
                         "clickthrough_on", "locked", "recovered"]
        if (settings.quietMode || focusMode) && !essential.contains(category) { return }

        var text: String?
        save.update { data in
            data.daily.rolloverIfNeeded(today: todayString())
            text = self.dialogue.pick(
                category: category,
                now: now,
                hour: self.currentHour,
                daily: &data.daily,
                petName: data.settings.petName
            )
        }
        if let text {
            delegate?.petPerform(.showBubble(text))
        }
    }

    func showBubbleText(_ text: String) {
        delegate?.petPerform(.showBubble(text))
    }

    // MARK: Status summary (今日状态)

    func statusSummary() -> String {
        let stats = save.data.stats
        let daily = save.data.daily
        refreshMood(now: ProcessInfo.processInfo.systemUptime)
        return """
        \(mood.emoji) 心情：\(mood.displayName)
        ⚡️ 体力 \(Int(stats.energy)) ｜ 🍎 饱食 \(Int(100 - stats.hunger))
        💛 亲密度 \(Int(stats.affection)) ｜ 😌 压力 \(Int(stats.stress))
        今日：抚摸 \(daily.petsToday) 次 · 喂食 \(daily.feedsToday) 次 · 番茄钟 \(daily.pomodorosCompleted) 个
        """
    }
}
