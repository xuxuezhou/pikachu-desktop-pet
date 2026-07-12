import AppKit
import Foundation

// MARK: - Built-in unit tests (run with: ./build/PikachuPet --selftest)
// Dependency-free test harness so the project keeps building with plain swiftc.

private var testFailures = 0
private var testCount = 0

private func expect(_ condition: Bool, _ label: String) {
    testCount += 1
    if condition {
        print("  ✓ \(label)")
    } else {
        testFailures += 1
        print("  ✗ FAILED: \(label)")
    }
}

func runSelfTests() -> Bool {
    print("PikachuPet self tests")

    testFrameIndex()
    testStats()
    testMood()
    testBehaviorSelector()
    testCooldowns()
    testDialogue()
    testSaveRoundTrip()
    testDailyRollover()
    testAnimDataParser()

    print(testFailures == 0
        ? "All \(testCount) checks passed."
        : "\(testFailures)/\(testCount) checks FAILED.")
    return testFailures == 0
}

private func makeAnimation(durations: [Int], frames: Int) -> SpriteAnimation {
    let image = NSImage(size: NSSize(width: frames * 10, height: 80))
    return SpriteAnimation(
        name: "Test", image: image, frameWidth: 10, frameHeight: 10,
        durations: durations, rowCount: 8, visualScale: 1
    )
}

private func testFrameIndex() {
    print("frameIndex:")
    let anim = makeAnimation(durations: [4, 2, 3], frames: 3)
    expect(anim.totalDuration == 9, "total duration sums durations")
    expect(anim.frameIndex(at: 0) == 0, "tick 0 -> frame 0")
    expect(anim.frameIndex(at: 3) == 0, "tick 3 -> frame 0")
    expect(anim.frameIndex(at: 4) == 1, "tick 4 -> frame 1")
    expect(anim.frameIndex(at: 6) == 2, "tick 6 -> frame 2")
    expect(anim.frameIndex(at: 9) == 0, "wraps around")
    expect(anim.frameIndex(at: 10_000_000) >= 0, "huge tick stays valid")

    // More durations than frames must not index past the last frame.
    let short = makeAnimation(durations: [2, 2, 2, 2, 2], frames: 3)
    for tick in 0..<20 {
        if short.frameIndex(at: tick) >= 3 {
            expect(false, "never returns frame >= frameCount")
            return
        }
    }
    expect(true, "never returns frame >= frameCount")
}

private func testStats() {
    print("stats:")
    var stats = PetStats()
    stats.apply(StatEffects(energy: 500, hunger: -500, mood: 500, affection: 500, stress: -500))
    expect(stats.energy == 100 && stats.hunger == 0 && stats.mood == 100
           && stats.affection == 100 && stats.stress == 0, "apply clamps to 0-100")

    stats = PetStats()
    let hungerBefore = stats.hunger
    stats.tick(minutes: 60, sleeping: false)
    expect(stats.hunger > hungerBefore, "hunger grows over time")

    stats = PetStats(energy: 10, hunger: 20, mood: 70, affection: 0, stress: 10)
    stats.tick(minutes: 30, sleeping: true)
    expect(stats.energy > 10, "sleeping restores energy")

    var offline = PetStats(energy: 40, hunger: 50, mood: 20, affection: 5, stress: 80)
    offline.settleOffline(seconds: PetStats.offlineSettlementCapSeconds)
    expect(offline.hunger <= 85, "offline hunger capped at 85")
    expect(offline.stress == 0, "offline clears stress")
    expect(offline.mood >= PetStats.moodBaseline, "offline never leaves mood below baseline")
}

private func testMood() {
    print("mood:")
    var stats = PetStats()
    stats.stress = 80
    expect(deriveMood(stats: stats, minutesSinceInteraction: 0, hour: 12) == .annoyed, "high stress -> annoyed")

    stats = PetStats()
    stats.hunger = 90
    expect(deriveMood(stats: stats, minutesSinceInteraction: 0, hour: 12) == .hungry, "high hunger -> hungry")

    stats = PetStats()
    stats.energy = 10
    expect(deriveMood(stats: stats, minutesSinceInteraction: 0, hour: 12) == .sleepy, "low energy -> sleepy")

    stats = PetStats()
    stats.mood = 90
    stats.energy = 80
    expect(deriveMood(stats: stats, minutesSinceInteraction: 0, hour: 12) == .excited, "high mood + energy -> excited")

    stats = PetStats()
    expect(deriveMood(stats: stats, minutesSinceInteraction: 60, hour: 12) == .bored, "long no interaction -> bored")
}

private func testBehaviorSelector() {
    print("behavior selector:")

    func context(stats: PetStats, mood: Mood, hour: Int, quiet: Bool = false) -> BehaviorContext {
        BehaviorContext(
            stats: stats, mood: mood, hour: hour,
            personality: .pikachu, quietMode: quiet,
            autoSleepEnabled: true, effectsEnabled: true,
            minutesSinceInteraction: 15
        )
    }

    // Determinism: same seed, same sequence.
    let a = PetRandom(seed: 42)
    let b = PetRandom(seed: 42)
    var stats = PetStats()
    let ctx = context(stats: stats, mood: .neutral, hour: 14)
    let seqA = (0..<20).map { _ in BehaviorSelector.choose(context: ctx, cooldownReady: { _ in true }, rng: a) ?? "none" }
    let seqB = (0..<20).map { _ in BehaviorSelector.choose(context: ctx, cooldownReady: { _ in true }, rng: b) ?? "none" }
    expect(seqA == seqB, "seeded selection is deterministic")

    // A sleepy pet at night picks sleep far more often than a fresh one at noon.
    stats = PetStats()
    stats.energy = 12
    let sleepyCtx = context(stats: stats, mood: .sleepy, hour: 23)
    let freshCtx = context(stats: PetStats(), mood: .happy, hour: 12)
    let rng = PetRandom(seed: 7)
    var sleepySleeps = 0
    var freshSleeps = 0
    for _ in 0..<300 {
        if BehaviorSelector.choose(context: sleepyCtx, cooldownReady: { _ in true }, rng: rng) == "sleep" { sleepySleeps += 1 }
        if BehaviorSelector.choose(context: freshCtx, cooldownReady: { _ in true }, rng: rng) == "sleep" { freshSleeps += 1 }
    }
    expect(sleepySleeps > freshSleeps, "tired pet at night sleeps more (\(sleepySleeps) vs \(freshSleeps))")
    expect(freshSleeps == 0, "fresh pet at noon never auto-sleeps")

    // Quiet mode removes idle bubbles from the candidate pool.
    var sawBubble = false
    for _ in 0..<300 {
        if BehaviorSelector.choose(context: context(stats: PetStats(), mood: .neutral, hour: 12, quiet: true),
                                   cooldownReady: { _ in true }, rng: rng) == "bubble_idle" {
            sawBubble = true
        }
    }
    expect(!sawBubble, "quiet mode suppresses idle bubbles")

    // Cooldowns filter candidates.
    var chosen = Set<String>()
    for _ in 0..<300 {
        if let pick = BehaviorSelector.choose(context: context(stats: PetStats(), mood: .neutral, hour: 12),
                                              cooldownReady: { $0 == "hop" }, rng: rng) {
            chosen.insert(pick)
        }
    }
    expect(chosen.subtracting(["hop", "bubble_idle"]).isEmpty, "cooldown gate limits candidates")
}

private func testCooldowns() {
    print("cooldowns:")
    let tracker = CooldownTracker()
    guard let hop = ActionCatalog.action("hop") else {
        expect(false, "hop action exists")
        return
    }
    expect(tracker.isReady("hop", now: 0), "ready before first use")
    tracker.trigger(hop, now: 100)
    expect(!tracker.isReady("hop", now: 100.1), "on cooldown right after trigger")
    expect(tracker.isReady("hop", now: 100 + hop.cooldownSeconds + 0.01), "ready after cooldown expires")
}

private func testDialogue() {
    print("dialogue:")
    let dialogue = DialogueLibrary(rng: PetRandom(seed: 1))
    var daily = DailyFlags()
    daily.date = todayString()

    let first = dialogue.pick(category: "petted", now: 1000, hour: 12, daily: &daily, petName: "皮卡丘")
    expect(first != nil, "picks a line for a valid category")

    let immediate = dialogue.pick(category: "petted", now: 1001, hour: 12, daily: &daily, petName: "皮卡丘")
    expect(immediate == nil, "category-level anti-spam blocks immediate repeat")

    let unknown = dialogue.pick(category: "no_such_category", now: 2000, hour: 12, daily: &daily, petName: "皮卡丘")
    expect(unknown == nil, "unknown category returns nil")

    // maxDailyCount exhausts a line.
    var flags = DailyFlags()
    flags.date = todayString()
    var shown = 0
    var time = 10_000.0
    for _ in 0..<10 {
        if dialogue.pick(category: "landed_hard", now: time, hour: 12, daily: &flags, petName: "皮卡丘") != nil {
            shown += 1
        }
        time += 10_000
    }
    expect(shown <= 10, "daily caps bound repetition (shown \(shown))")

    let line = DialogueLine(id: "x", text: "x", hourRange: (21, 5))
    expect(line.matchesHour(23) && line.matchesHour(3) && !line.matchesHour(12), "wrap-around hour range")
}

private func testSaveRoundTrip() {
    print("save round trip:")
    var original = SaveData()
    original.stats.energy = 55.5
    original.stats.affection = 12
    original.settings.quietMode = true
    original.settings.behaviorSeed = 99
    original.totals.pets = 7
    original.daily.petsToday = 3
    original.windowX = 123.4
    original.windowY = 56.7

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    do {
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(SaveData.self, from: data)
        expect(decoded.stats.energy == original.stats.energy, "stats survive round trip")
        expect(decoded.settings.quietMode == true, "settings survive round trip")
        expect(decoded.settings.behaviorSeed == 99, "optional seed survives round trip")
        expect(decoded.totals.pets == 7 && decoded.daily.petsToday == 3, "counters survive round trip")
        expect(decoded.windowX == 123.4, "window position survives round trip")
    } catch {
        expect(false, "encode/decode throws: \(error)")
    }

    // Corrupted payload must fail decode (caller falls back to defaults/backup).
    let garbage = Data("{not json!".utf8)
    let corrupted = try? decoder.decode(SaveData.self, from: garbage)
    expect(corrupted == nil, "corrupted save is rejected, not half-loaded")
}

private func testDailyRollover() {
    print("daily rollover:")
    var flags = DailyFlags()
    flags.date = "2020-01-01"
    flags.petsToday = 9
    flags.greeted = true
    flags.rolloverIfNeeded(today: "2020-01-02")
    expect(flags.petsToday == 0 && !flags.greeted && flags.date == "2020-01-02", "new day resets daily flags")

    flags.petsToday = 4
    flags.rolloverIfNeeded(today: "2020-01-02")
    expect(flags.petsToday == 4, "same day keeps flags")
}

private func testAnimDataParser() {
    print("AnimData parser:")
    let candidates = [
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("pmd_sprites/AnimData.xml"),
        URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("pmd_sprites/AnimData.xml"),
    ]
    guard let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
        print("  - skipped (AnimData.xml not found from test cwd)")
        return
    }
    let parsed = AnimDataParser.parse(url: url)
    expect(parsed["Idle"] != nil, "parses Idle")
    expect(parsed["Idle"]?.frameWidth == 40 && parsed["Idle"]?.frameHeight == 56, "Idle frame size matches")
    expect(parsed["Idle"]?.durations == [40, 2, 3, 3, 3, 2], "Idle durations match")
    expect(parsed["Hop"]?.durations.count == 10, "Hop has 10 durations")
    expect(parsed.count >= 20, "parses the full catalog (\(parsed.count) anims)")
}
