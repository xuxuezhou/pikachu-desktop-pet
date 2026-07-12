import Foundation

// MARK: - Rule/weight based autonomous behavior selection (no AI)

struct BehaviorContext {
    let stats: PetStats
    let mood: Mood
    let hour: Int
    let personality: Personality
    let quietMode: Bool
    let autoSleepEnabled: Bool
    let effectsEnabled: Bool
    let minutesSinceInteraction: Double
}

enum BehaviorSelector {
    /// Scores each candidate as base × personality × mood × energy × time ×
    /// randomness and rolls a weighted pick. "none" (stay idle) is always a
    /// candidate so the pet doesn't fidget constantly.
    static func choose(
        context: BehaviorContext,
        cooldownReady: (String) -> Bool,
        rng: PetRandom
    ) -> String? {
        var scores: [(id: String, score: Double)] = []
        let p = context.personality
        let energyFactor = context.stats.energy / 100 * 0.7 + 0.3
        let isNight = context.hour >= 22 || context.hour < 6

        func add(_ id: String, _ base: Double) {
            guard base > 0, cooldownReady(id) else { return }
            if let def = ActionCatalog.action(id), context.stats.energy < def.minimumEnergy { return }
            let noise = rng.double(in: 0.8...1.2)
            scores.append((id, base * noise))
        }

        // Doing nothing is a real option, weighted by patience. Tired or
        // annoyed pets prefer to stay put.
        var idleWeight = 1.4 * (0.5 + p.patience)
        if context.mood == .annoyed || context.mood == .sad { idleWeight *= 2 }
        scores.append(("none", idleWeight))

        let moodActive: Double
        switch context.mood {
        case .excited: moodActive = 1.6
        case .happy: moodActive = 1.3
        case .bored: moodActive = 1.2
        case .neutral: moodActive = 1.0
        case .hungry: moodActive = 0.8
        case .annoyed, .sad: moodActive = 0.5
        case .sleepy: moodActive = 0.4
        }

        add("hop", 0.8 * p.playfulness * energyFactor * moodActive)
        add("pose", 0.5 * p.playfulness * moodActive)
        add("nod", 0.4 * p.sociability * moodActive)
        add("lookup", 0.7 * p.curiosity)
        add("wander", 0.9 * p.energyLevel * energyFactor * moodActive * (isNight ? 0.5 : 1))
        add("trip", 0.12 * moodActive)
        if context.effectsEnabled && context.stats.energy > 50 {
            add("thunder", 0.06 * p.playfulness * moodActive)
        }

        if context.autoSleepEnabled {
            var sleepWeight = 0.05 + p.sleepPreference * 0.1
            if context.stats.energy < 30 { sleepWeight *= 6 }
            if isNight { sleepWeight *= 3 }
            if context.mood == .sleepy { sleepWeight *= 4 }
            if context.minutesSinceInteraction < 3 { sleepWeight *= 0.3 }
            if context.stats.energy > 70 && !isNight { sleepWeight = 0 }
            add("sleep", sleepWeight)
        }

        if !context.quietMode {
            var bubbleWeight = 0.35 * p.sociability
            switch context.mood {
            case .hungry: bubbleWeight = 0.8
            case .bored: bubbleWeight = 0.7
            case .sleepy: bubbleWeight = 0.6
            default: break
            }
            add("bubble_idle", bubbleWeight)
        }

        let total = scores.reduce(0) { $0 + $1.score }
        guard total > 0 else { return nil }
        var roll = rng.double(in: 0...total)
        for entry in scores {
            roll -= entry.score
            if roll <= 0 {
                return entry.id == "none" ? nil : entry.id
            }
        }
        return nil
    }

    /// Bubble category matching the current mood, for autonomous chatter.
    static func idleBubbleCategory(for mood: Mood) -> String {
        switch mood {
        case .hungry: return "hungry"
        case .sleepy: return "sleepy"
        case .bored: return "bored"
        default: return "idle"
        }
    }
}
