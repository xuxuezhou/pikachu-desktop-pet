import Foundation
import CoreGraphics

// MARK: - Action definitions (data-driven catalog; engine knows kinds, not Pikachu)

enum ActionKind {
    case anim(String)            // one-shot sprite animation by sheet name
    case jump                    // hop animation + window lift arc
    case run(direction: CGFloat?, maxDistance: CGFloat)  // nil direction = away from center
    case sleepToggle
    case thunder                 // special: Swing animation + electric glow effect
}

struct ActionDef {
    let id: String
    let displayName: String
    let kind: ActionKind
    let priority: Int            // 100 system, 80 user command, 60 interaction reaction, 30 autonomous
    let interruptLevel: Int      // an incoming action needs priority > this to cut it off
    let cooldownSeconds: Double
    let effects: StatEffects
    let bubbleCategory: String?
    let minimumEnergy: Double

    init(
        id: String,
        displayName: String,
        kind: ActionKind,
        priority: Int = 30,
        interruptLevel: Int = 40,
        cooldownSeconds: Double = 2,
        effects: StatEffects = .none,
        bubbleCategory: String? = nil,
        minimumEnergy: Double = 0
    ) {
        self.id = id
        self.displayName = displayName
        self.kind = kind
        self.priority = priority
        self.interruptLevel = interruptLevel
        self.cooldownSeconds = cooldownSeconds
        self.effects = effects
        self.bubbleCategory = bubbleCategory
        self.minimumEnergy = minimumEnergy
    }
}

enum ActionPriority {
    static let system = 100
    static let user = 80
    static let reaction = 60
    static let autonomous = 30
}

enum ActionCatalog {
    static let all: [String: ActionDef] = {
        var catalog: [String: ActionDef] = [:]
        let defs: [ActionDef] = [
            ActionDef(id: "hop", displayName: "跳跃", kind: .jump,
                      cooldownSeconds: 1.5,
                      effects: StatEffects(energy: -0.5, mood: 1)),
            ActionDef(id: "nod", displayName: "鞠躬", kind: .anim("Nod"),
                      cooldownSeconds: 2),
            ActionDef(id: "pose", displayName: "摆姿势", kind: .anim("Pose"),
                      cooldownSeconds: 3, effects: StatEffects(mood: 1)),
            ActionDef(id: "trip", displayName: "摔倒", kind: .anim("Trip"),
                      cooldownSeconds: 4),
            ActionDef(id: "lookup", displayName: "张望", kind: .anim("LookUp"),
                      cooldownSeconds: 5),
            ActionDef(id: "wander", displayName: "散步", kind: .run(direction: nil, maxDistance: 200),
                      cooldownSeconds: 4, effects: StatEffects(energy: -0.8), minimumEnergy: 10),
            ActionDef(id: "runLeft", displayName: "向左跑", kind: .run(direction: -1, maxDistance: 340),
                      cooldownSeconds: 0.5, effects: StatEffects(energy: -1), minimumEnergy: 5),
            ActionDef(id: "runRight", displayName: "向右跑", kind: .run(direction: 1, maxDistance: 340),
                      cooldownSeconds: 0.5, effects: StatEffects(energy: -1), minimumEnergy: 5),
            ActionDef(id: "thunder", displayName: "十万伏特", kind: .thunder,
                      interruptLevel: 70, cooldownSeconds: 12,
                      effects: StatEffects(energy: -4, mood: 3),
                      bubbleCategory: "thunder", minimumEnergy: 15),
            ActionDef(id: "sleep", displayName: "睡觉", kind: .sleepToggle,
                      cooldownSeconds: 5),
            ActionDef(id: "pet_response", displayName: "被抚摸", kind: .anim("Nod"),
                      priority: ActionPriority.reaction, cooldownSeconds: 0.4,
                      effects: StatEffects(mood: 3, affection: 0.8, stress: -3),
                      bubbleCategory: "petted"),
            ActionDef(id: "feed", displayName: "吃树果", kind: .anim("Nod"),
                      priority: ActionPriority.reaction, cooldownSeconds: 3,
                      effects: StatEffects(energy: 5, hunger: -30, mood: 4, affection: 0.5),
                      bubbleCategory: "fed"),
            ActionDef(id: "annoyed_zap", displayName: "生气放电", kind: .anim("Trip"),
                      priority: ActionPriority.reaction, interruptLevel: 65,
                      cooldownSeconds: 5, effects: StatEffects(mood: -2),
                      bubbleCategory: "annoyed"),
            ActionDef(id: "celebrate", displayName: "庆祝", kind: .anim("Pose"),
                      priority: ActionPriority.reaction, cooldownSeconds: 1,
                      effects: StatEffects(mood: 5)),
        ]
        for def in defs { catalog[def.id] = def }
        return catalog
    }()

    static func action(_ id: String) -> ActionDef? { all[id] }
}

// MARK: - Cooldown tracking

final class CooldownTracker {
    private var readyAt: [String: Double] = [:]

    func isReady(_ id: String, now: Double) -> Bool {
        now >= (readyAt[id] ?? 0)
    }

    func trigger(_ def: ActionDef, now: Double) {
        readyAt[def.id] = now + def.cooldownSeconds
    }

    func reset() {
        readyAt.removeAll()
    }
}
