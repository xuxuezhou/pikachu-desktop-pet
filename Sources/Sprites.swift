import AppKit
import Foundation

// MARK: - Sprite facing

enum Facing {
    case front, left, right
}

// MARK: - Sprite animation (one PMD sheet: columns = frames, rows = directions)

struct SpriteAnimation {
    let name: String
    let image: NSImage
    let frameWidth: Int
    let frameHeight: Int
    /// Durations in animation ticks (30 ticks per second), already speed-scaled.
    let durations: [Int]
    let rowCount: Int
    let visualScale: CGFloat

    // PMD sheets order direction rows bottom-up when sampled in image
    // coordinates: row 7 = facing camera, 1 = left, 5 = right.
    private static let frontRow = 7
    private static let leftRow = 1
    private static let rightRow = 5

    var frameCount: Int {
        max(1, Int(image.size.width) / frameWidth)
    }

    var totalDuration: Int {
        max(1, durations.prefix(frameCount).reduce(0, +))
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
        return max(0, min(frameCount, durations.count) - 1)
    }

    func row(for facing: Facing) -> Int {
        guard rowCount > 1 else { return 0 }
        let requested: Int
        switch facing {
        case .front: requested = SpriteAnimation.frontRow
        case .left: requested = SpriteAnimation.leftRow
        case .right: requested = SpriteAnimation.rightRow
        }
        return min(requested, rowCount - 1)
    }
}

// MARK: - AnimData.xml parsing

struct AnimMetadata {
    let name: String
    let frameWidth: Int
    let frameHeight: Int
    let durations: [Int]
}

final class AnimDataParser: NSObject, XMLParserDelegate {
    private var animations: [AnimMetadata] = []
    private var currentName = ""
    private var currentWidth = 0
    private var currentHeight = 0
    private var currentDurations: [Int] = []
    private var text = ""
    private var insideAnim = false

    static func parse(url: URL) -> [String: AnimMetadata] {
        guard let parser = XMLParser(contentsOf: url) else { return [:] }
        let delegate = AnimDataParser()
        parser.delegate = delegate
        parser.parse()
        var result: [String: AnimMetadata] = [:]
        for anim in delegate.animations {
            result[anim.name] = anim
        }
        return result
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String]) {
        text = ""
        if name == "Anim" {
            insideAnim = true
            currentName = ""
            currentWidth = 0
            currentHeight = 0
            currentDurations = []
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch name {
        case "Name" where insideAnim: currentName = value
        case "FrameWidth": currentWidth = Int(value) ?? 0
        case "FrameHeight": currentHeight = Int(value) ?? 0
        case "Duration": currentDurations.append(Int(value) ?? 1)
        case "Anim":
            insideAnim = false
            if !currentName.isEmpty, currentWidth > 0, currentHeight > 0, !currentDurations.isEmpty {
                animations.append(AnimMetadata(
                    name: currentName,
                    frameWidth: currentWidth,
                    frameHeight: currentHeight,
                    durations: currentDurations
                ))
            }
        default: break
        }
    }
}

// MARK: - Sprite library (loads every sheet present on disk, driven by AnimData.xml)

final class SpriteLibrary {
    private(set) var animations: [String: SpriteAnimation] = [:]

    /// Playback speed multipliers relative to the raw AnimData durations,
    /// tuned to keep the original app's feel (walk was intentionally 2x).
    private static let speedScales: [String: Double] = [
        "Walk": 0.5,
        "Swing": 1.5,
    ]

    private static let visualScales: [String: CGFloat] = [
        "Idle": 1.0,
        "Walk": 0.95,
        "Hop": 0.95,
        "Nod": 0.95,
        "Pose": 0.95,
        "Trip": 0.92,
        "Swing": 1.15,
        "LookUp": 0.95,
    ]

    var isEmpty: Bool { animations.isEmpty }

    subscript(name: String) -> SpriteAnimation? { animations[name] }

    /// Returns the requested animation, falling back to Idle so a missing
    /// sheet can never break an action.
    func animation(_ name: String) -> SpriteAnimation? {
        animations[name] ?? animations["Idle"]
    }

    static func load() -> SpriteLibrary? {
        guard let folder = locateSpriteFolder() else {
            logWarn("pmd_sprites folder not found")
            return nil
        }

        let metadata = AnimDataParser.parse(url: folder.appendingPathComponent("AnimData.xml"))
        guard !metadata.isEmpty else {
            logError("AnimData.xml missing or unparseable in \(folder.path)")
            return nil
        }

        let library = SpriteLibrary()
        for (name, meta) in metadata {
            let sheetURL = folder.appendingPathComponent("\(name)-Anim.png")
            guard FileManager.default.fileExists(atPath: sheetURL.path),
                  let image = NSImage(contentsOf: sheetURL),
                  image.size.width >= CGFloat(meta.frameWidth),
                  image.size.height >= CGFloat(meta.frameHeight)
            else { continue }

            let speed = speedScales[name] ?? 1.0
            let scaled = meta.durations.map { max(1, Int((Double($0) * speed).rounded())) }
            let rows = max(1, Int(image.size.height) / meta.frameHeight)
            library.animations[name] = SpriteAnimation(
                name: name,
                image: image,
                frameWidth: meta.frameWidth,
                frameHeight: meta.frameHeight,
                durations: scaled,
                rowCount: rows,
                visualScale: visualScales[name] ?? 0.95
            )
        }

        guard library.animations["Idle"] != nil else {
            logError("Idle-Anim.png missing; sprite mode disabled")
            return nil
        }

        logInfo("Sprite library loaded: \(library.animations.keys.sorted().joined(separator: ", "))")
        return library
    }

    private static func locateSpriteFolder() -> URL? {
        let fm = FileManager.default
        let current = URL(fileURLWithPath: fm.currentDirectoryPath)
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        let parent = executable.deletingLastPathComponent()

        var candidates = [
            current.appendingPathComponent("pmd_sprites"),
            executable.appendingPathComponent("pmd_sprites"),
            parent.appendingPathComponent("pmd_sprites"),
            parent.appendingPathComponent("Resources").appendingPathComponent("pmd_sprites"),
        ]
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("pmd_sprites"))
        }

        return candidates.first { fm.fileExists(atPath: $0.appendingPathComponent("AnimData.xml").path) }
    }
}
