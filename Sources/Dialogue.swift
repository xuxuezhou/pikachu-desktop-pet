import Foundation

// MARK: - Local dialogue templates (rule-based, no AI, fully offline)

struct DialogueLine {
    let id: String
    let text: String
    var weight: Double = 1
    var cooldownSeconds: Double = 600
    var maxDailyCount: Int = 99
    /// Inclusive hour range, supports wrap-around (e.g. 21...5).
    var hourRange: (start: Int, end: Int)? = nil

    func matchesHour(_ hour: Int) -> Bool {
        guard let hourRange else { return true }
        if hourRange.start <= hourRange.end {
            return hour >= hourRange.start && hour <= hourRange.end
        }
        return hour >= hourRange.start || hour <= hourRange.end
    }
}

final class DialogueLibrary {
    private var lastShown: [String: Double] = [:]   // line id -> uptime
    private var lastCategoryShown: [String: Double] = [:]
    private let rng: PetRandom

    init(rng: PetRandom) {
        self.rng = rng
    }

    private static let lines: [String: [DialogueLine]] = [
        "greeting_morning": [
            DialogueLine(id: "gm1", text: "皮卡皮卡！早上好，{petName}向你问好～", cooldownSeconds: 3600),
            DialogueLine(id: "gm2", text: "早安！今天也要元气满满哦⚡️", cooldownSeconds: 3600),
        ],
        "greeting_day": [
            DialogueLine(id: "gd1", text: "皮卡丘来陪你啦！", cooldownSeconds: 3600),
            DialogueLine(id: "gd2", text: "嗨！在忙什么呢？", cooldownSeconds: 3600),
        ],
        "greeting_night": [
            DialogueLine(id: "gn1", text: "这么晚还在工作吗？注意休息哦。", cooldownSeconds: 3600),
            DialogueLine(id: "gn2", text: "皮卡……夜深了，别熬太晚。", cooldownSeconds: 3600),
        ],
        "idle": [
            DialogueLine(id: "i1", text: "皮卡～", cooldownSeconds: 900, maxDailyCount: 6),
            DialogueLine(id: "i2", text: "（东张西望）", cooldownSeconds: 900, maxDailyCount: 6),
            DialogueLine(id: "i3", text: "今天天气怎么样呀？", cooldownSeconds: 1800, maxDailyCount: 3),
            DialogueLine(id: "i4", text: "要不要休息一下眼睛？", cooldownSeconds: 2700, maxDailyCount: 3),
        ],
        "petted": [
            DialogueLine(id: "p1", text: "皮卡皮卡～（很舒服）", cooldownSeconds: 60),
            DialogueLine(id: "p2", text: "嘿嘿，再摸摸～", cooldownSeconds: 60),
            DialogueLine(id: "p3", text: "（开心地眯起眼睛）", cooldownSeconds: 60),
        ],
        "fed": [
            DialogueLine(id: "f1", text: "树果！好吃！", cooldownSeconds: 60),
            DialogueLine(id: "f2", text: "皮卡～谢谢投喂！", cooldownSeconds: 60),
        ],
        "full": [
            DialogueLine(id: "fu1", text: "吃不下啦，肚子圆滚滚的～", cooldownSeconds: 120),
        ],
        "annoyed": [
            DialogueLine(id: "a1", text: "皮——卡——（脸颊开始放电）", cooldownSeconds: 120),
            DialogueLine(id: "a2", text: "别戳啦！再戳要放十万伏特了！", cooldownSeconds: 120),
        ],
        "dragged": [
            DialogueLine(id: "d1", text: "哇啊——要去哪里？", cooldownSeconds: 300, maxDailyCount: 5),
            DialogueLine(id: "d2", text: "皮卡？！（被拎起来了）", cooldownSeconds: 300, maxDailyCount: 5),
        ],
        "landed_hard": [
            DialogueLine(id: "lh1", text: "哎哟……摔疼了啦。", cooldownSeconds: 120),
        ],
        "sleepy": [
            DialogueLine(id: "s1", text: "皮卡……有点困了。", cooldownSeconds: 1800, maxDailyCount: 3, hourRange: (21, 5)),
            DialogueLine(id: "s2", text: "（揉揉眼睛）好想睡觉……", cooldownSeconds: 1800, maxDailyCount: 3),
        ],
        "wake": [
            DialogueLine(id: "w1", text: "（打了个大大的哈欠）醒啦！", cooldownSeconds: 60),
            DialogueLine(id: "w2", text: "皮卡！睡得真香～", cooldownSeconds: 60),
        ],
        "hungry": [
            DialogueLine(id: "h1", text: "肚子咕咕叫了……有树果吗？", cooldownSeconds: 2700, maxDailyCount: 4),
        ],
        "bored": [
            DialogueLine(id: "b1", text: "好无聊呀……陪我玩一会儿嘛。", cooldownSeconds: 2700, maxDailyCount: 3),
        ],
        "thunder": [
            DialogueLine(id: "t1", text: "十万伏特！！⚡️⚡️⚡️", cooldownSeconds: 30),
            DialogueLine(id: "t2", text: "皮～卡～丘！！！⚡️", cooldownSeconds: 30),
        ],
        "pomodoro_start": [
            DialogueLine(id: "ps1", text: "专注时间开始！我会安静陪着你的。", cooldownSeconds: 10),
        ],
        "pomodoro_done": [
            DialogueLine(id: "pd1", text: "叮！专注完成，你真棒！休息一下吧🎉", cooldownSeconds: 10),
        ],
        "pomodoro_break_done": [
            DialogueLine(id: "pb1", text: "休息结束啦，要再来一轮吗?", cooldownSeconds: 10),
        ],
        "clickthrough_on": [
            DialogueLine(id: "ct1", text: "鼠标穿透已开启，用托盘菜单或 ⌃⇧G 恢复。", cooldownSeconds: 5),
        ],
        "locked": [
            DialogueLine(id: "lk1", text: "位置已锁定，不会被拖走啦。", cooldownSeconds: 5),
        ],
        "recovered": [
            DialogueLine(id: "rc1", text: "咦？刚才差点跑丢了……回来啦！", cooldownSeconds: 60),
        ],
    ]

    /// Picks a line for the category respecting per-line cooldowns, daily
    /// caps and hour ranges. Returns nil when everything is on cooldown.
    func pick(category: String, now: Double, hour: Int, daily: inout DailyFlags, petName: String) -> String? {
        guard let candidates = DialogueLibrary.lines[category] else { return nil }

        // Category-level anti-spam: same category at most every 20s.
        if let last = lastCategoryShown[category], now - last < 20 { return nil }

        let eligible = candidates.filter { line in
            guard line.matchesHour(hour) else { return false }
            if let last = lastShown[line.id], now - last < line.cooldownSeconds { return false }
            if daily.bubbleCounts[line.id, default: 0] >= line.maxDailyCount { return false }
            return true
        }
        guard !eligible.isEmpty else { return nil }

        let total = eligible.reduce(0) { $0 + $1.weight }
        var roll = rng.double(in: 0...total)
        var chosen = eligible[0]
        for line in eligible {
            roll -= line.weight
            if roll <= 0 { chosen = line; break }
        }

        lastShown[chosen.id] = now
        lastCategoryShown[category] = now
        daily.bubbleCounts[chosen.id, default: 0] += 1

        return chosen.text.replacingOccurrences(of: "{petName}", with: petName)
    }
}
