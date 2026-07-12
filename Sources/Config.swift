import Foundation

// MARK: - Settings (user-facing, persisted)

struct Settings: Codable {
    var petName: String = "皮卡丘"
    var alwaysOnTop: Bool = true
    var gravityEnabled: Bool = true
    var bubblesEnabled: Bool = true
    var quietMode: Bool = false
    var positionLocked: Bool = false
    var clickThrough: Bool = false
    var effectsEnabled: Bool = true
    var reduceFlashing: Bool = false
    var autoSleepEnabled: Bool = true
    var restorePosition: Bool = true
    var bubbleSeconds: Double = 3.5
    var autonomyLevel: Double = 1.0   // 0 = never moves on its own, 1 = default, 2 = hyperactive
    var behaviorSeed: UInt64? = nil   // fixed seed for deterministic behavior debugging

    static let `default` = Settings()
}

// MARK: - Personality (data-driven weights, Pikachu default: playful + friendly + energetic)

struct Personality: Codable {
    var playfulness: Double = 0.9
    var sociability: Double = 0.8
    var energyLevel: Double = 0.85
    var curiosity: Double = 0.75
    var patience: Double = 0.45
    var sleepPreference: Double = 0.35

    static let pikachu = Personality()
}

// MARK: - Daily flags & lifetime totals

struct DailyFlags: Codable {
    var date: String = ""             // "yyyy-MM-dd"; reset when day changes
    var greeted: Bool = false
    var pomodorosCompleted: Int = 0
    var petsToday: Int = 0
    var feedsToday: Int = 0
    var bubbleCounts: [String: Int] = [:]

    mutating func rolloverIfNeeded(today: String) {
        guard date != today else { return }
        self = DailyFlags()
        date = today
    }
}

struct LifetimeTotals: Codable {
    var launches: Int = 0
    var pets: Int = 0
    var feeds: Int = 0
    var pomodoros: Int = 0
    var jumps: Int = 0
    var thunders: Int = 0
}

// MARK: - Save data

struct SaveData: Codable {
    var version: Int = 2
    var savedAt: Date = Date()
    var stats: PetStats = PetStats()
    var settings: Settings = .default
    var personality: Personality = .pikachu
    var daily: DailyFlags = DailyFlags()
    var totals: LifetimeTotals = LifetimeTotals()
    var windowX: Double? = nil
    var windowY: Double? = nil
    var windowWidth: Double? = nil
    var windowHeight: Double? = nil
}

// MARK: - Save manager (atomic writes, backup, corruption recovery)

final class SaveManager {
    static let shared = SaveManager()

    private(set) var data: SaveData
    private var dirty = false
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        data = SaveManager.load(encoder: encoder, decoder: decoder)
    }

    private static func load(encoder: JSONEncoder, decoder: JSONDecoder) -> SaveData {
        for url in [AppPaths.saveFile, AppPaths.saveBackupFile] {
            guard let raw = try? Data(contentsOf: url) else { continue }
            do {
                var loaded = try decoder.decode(SaveData.self, from: raw)
                loaded = migrate(loaded)
                logInfo("Save loaded from \(url.lastPathComponent) (v\(loaded.version))")
                return loaded
            } catch {
                logError("Save file \(url.lastPathComponent) corrupted: \(error.localizedDescription)")
            }
        }
        logInfo("No save found, starting fresh")
        return SaveData()
    }

    private static func migrate(_ input: SaveData) -> SaveData {
        var data = input
        if data.version < 2 {
            // v1 -> v2: nothing structural yet; bump version for forward compatibility.
            data.version = 2
        }
        return data
    }

    func markDirty() { dirty = true }

    func update(_ mutate: (inout SaveData) -> Void) {
        mutate(&data)
        dirty = true
    }

    /// Applies capped offline settlement and returns seconds that were settled.
    @discardableResult
    func settleOfflineTime() -> Double {
        let elapsed = Date().timeIntervalSince(data.savedAt)
        guard elapsed > 60 else { return 0 }
        let capped = min(elapsed, PetStats.offlineSettlementCapSeconds)
        data.stats.settleOffline(seconds: capped)
        dirty = true
        logInfo("Offline settlement: \(Int(elapsed))s elapsed, \(Int(capped))s applied")
        return capped
    }

    @discardableResult
    func saveIfNeeded(force: Bool = false) -> Bool {
        guard dirty || force else { return false }
        data.savedAt = Date()
        do {
            let encoded = try encoder.encode(data)
            let fm = FileManager.default
            // Keep the previous good save as a backup before replacing it.
            if fm.fileExists(atPath: AppPaths.saveFile.path) {
                try? fm.removeItem(at: AppPaths.saveBackupFile)
                try? fm.copyItem(at: AppPaths.saveFile, to: AppPaths.saveBackupFile)
            }
            try encoded.write(to: AppPaths.saveFile, options: .atomic)
            dirty = false
            return true
        } catch {
            logError("Save failed: \(error.localizedDescription)")
            return false
        }
    }
}

func todayString(_ date: Date = Date()) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
}
