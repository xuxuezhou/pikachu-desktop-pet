import Foundation

// MARK: - Paths

enum AppPaths {
    static let bundleName = "PikachuPet"

    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent(bundleName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var saveFile: URL { supportDirectory.appendingPathComponent("save.json") }
    static var saveBackupFile: URL { supportDirectory.appendingPathComponent("save.json.bak") }
    static var logFile: URL { supportDirectory.appendingPathComponent("pet.log") }
    static var lockFile: URL { supportDirectory.appendingPathComponent(".instance.lock") }
}

// MARK: - Logger

enum LogLevel: Int, Comparable {
    case debug = 0, info, warning, error

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warning: return "WARN"
        case .error: return "ERROR"
        }
    }
}

final class Logger {
    static let shared = Logger()

    var minimumLevel: LogLevel = .info
    private let queue = DispatchQueue(label: "pet.logger", qos: .utility)
    private var handle: FileHandle?
    private let formatter: DateFormatter
    private let maxLogBytes: UInt64 = 512 * 1024

    private init() {
        formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        openHandle()
    }

    private func openHandle() {
        let url = AppPaths.logFile
        let fm = FileManager.default
        if let size = try? fm.attributesOfItem(atPath: url.path)[.size] as? UInt64, size > maxLogBytes {
            try? fm.removeItem(at: url)
        }
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil)
        }
        handle = try? FileHandle(forWritingTo: url)
        _ = try? handle?.seekToEnd()
    }

    func log(_ level: LogLevel, _ message: String) {
        guard level >= minimumLevel else { return }
        let line = "[\(formatter.string(from: Date()))] [\(level.label)] \(message)\n"
        queue.async { [weak self] in
            if let data = line.data(using: .utf8) {
                try? self?.handle?.write(contentsOf: data)
            }
        }
        #if DEBUG
        print(line, terminator: "")
        #endif
    }

    func flushAndClose() {
        queue.sync {
            try? handle?.synchronize()
            try? handle?.close()
            handle = nil
        }
    }
}

func logDebug(_ message: String) { Logger.shared.log(.debug, message) }
func logInfo(_ message: String) { Logger.shared.log(.info, message) }
func logWarn(_ message: String) { Logger.shared.log(.warning, message) }
func logError(_ message: String) { Logger.shared.log(.error, message) }

// MARK: - Random source (seedable for deterministic behavior debugging)

final class PetRandom {
    private var generator: any RandomNumberGenerator

    init(seed: UInt64? = nil) {
        if let seed {
            generator = SplitMix64(seed: seed)
        } else {
            generator = SystemRandomNumberGenerator()
        }
    }

    func double(in range: ClosedRange<Double>) -> Double {
        Double.random(in: range, using: &generator)
    }

    func int(in range: Range<Int>) -> Int {
        Int.random(in: range, using: &generator)
    }

    func chance(_ probability: Double) -> Bool {
        double(in: 0...1) < probability
    }
}

struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
