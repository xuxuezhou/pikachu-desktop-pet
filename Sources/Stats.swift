import Foundation

// MARK: - Stat effects applied by actions

struct StatEffects {
    var energy: Double = 0
    var hunger: Double = 0
    var mood: Double = 0
    var affection: Double = 0
    var stress: Double = 0

    static let none = StatEffects()
}

// MARK: - Pet stats

struct PetStats: Codable {
    var energy: Double = 80      // 0-100, low = tired
    var hunger: Double = 20      // 0-100, high = hungry
    var mood: Double = 70        // 0-100, high = happy
    var affection: Double = 0    // 0-100, long-term bond, never drops quickly
    var stress: Double = 10      // 0-100, high = annoyed/scared

    static let offlineSettlementCapSeconds: Double = 8 * 3600

    // Per-minute passive rates (real time). Deliberately slow so the pet
    // never demands constant attention.
    static let hungerPerMinute: Double = 100.0 / (8 * 60)   // full hunger over ~8h
    static let energyRegenAwake: Double = 0.05
    static let energyRegenSleeping: Double = 2.0
    static let moodDriftPerMinute: Double = 0.15            // drift toward baseline
    static let moodBaseline: Double = 60
    static let stressDecayPerMinute: Double = 0.6

    mutating func clampAll() {
        energy = min(100, max(0, energy))
        hunger = min(100, max(0, hunger))
        mood = min(100, max(0, mood))
        affection = min(100, max(0, affection))
        stress = min(100, max(0, stress))
    }

    mutating func apply(_ effects: StatEffects) {
        energy += effects.energy
        hunger += effects.hunger
        mood += effects.mood
        affection += effects.affection
        stress += effects.stress
        clampAll()
    }

    /// Passive drift over `minutes` of real time while the app is running.
    mutating func tick(minutes: Double, sleeping: Bool) {
        hunger += PetStats.hungerPerMinute * minutes
        energy += (sleeping ? PetStats.energyRegenSleeping : PetStats.energyRegenAwake) * minutes
        if !sleeping {
            let drift = PetStats.moodDriftPerMinute * minutes
            if mood > PetStats.moodBaseline { mood = max(PetStats.moodBaseline, mood - drift) }
            else if mood < PetStats.moodBaseline { mood = min(PetStats.moodBaseline, mood + drift) }
        }
        stress = max(0, stress - PetStats.stressDecayPerMinute * minutes)
        clampAll()
    }

    /// Offline settlement: the pet "rests while you're away". Capped by the
    /// caller (see offlineSettlementCapSeconds); never punitive.
    mutating func settleOffline(seconds: Double) {
        let minutes = seconds / 60
        hunger += PetStats.hungerPerMinute * minutes * 0.5   // hunger builds at half rate offline
        hunger = min(hunger, 85)                             // never wakes up starving
        energy = min(100, energy + minutes * 0.3)            // rested after time away
        stress = 0
        if mood < PetStats.moodBaseline { mood = PetStats.moodBaseline }
        clampAll()
    }
}

// MARK: - Mood (discrete state derived from continuous stats by rules)

enum Mood: String, CaseIterable {
    case happy, excited, neutral, sleepy, hungry, bored, annoyed, sad

    var emoji: String {
        switch self {
        case .happy: return "😊"
        case .excited: return "⚡️"
        case .neutral: return "🙂"
        case .sleepy: return "😴"
        case .hungry: return "🍎"
        case .bored: return "🥱"
        case .annoyed: return "😤"
        case .sad: return "😢"
        }
    }

    var displayName: String {
        switch self {
        case .happy: return "开心"
        case .excited: return "兴奋"
        case .neutral: return "平静"
        case .sleepy: return "犯困"
        case .hungry: return "饿了"
        case .bored: return "无聊"
        case .annoyed: return "烦躁"
        case .sad: return "低落"
        }
    }
}

func deriveMood(stats: PetStats, minutesSinceInteraction: Double, hour: Int) -> Mood {
    if stats.stress > 55 { return .annoyed }
    if stats.hunger > 75 { return .hungry }
    if stats.energy < 22 || ((hour >= 23 || hour < 6) && stats.energy < 45) { return .sleepy }
    if stats.mood < 30 { return .sad }
    if stats.mood > 85 && stats.energy > 60 { return .excited }
    if stats.mood > 72 { return .happy }
    if minutesSinceInteraction > 30 { return .bored }
    return .neutral
}
