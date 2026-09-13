import Foundation

/// What to do when a gesture fires.
/// JSON: {"type":"spotify","command":"playpause"} | {"type":"media","key":"playpause"}
///     | {"type":"key","keys":"cmd+shift+m"} | {"type":"shell","command":"..."}
enum Action: Codable, Equatable {
    case key(String)
    case media(String)
    case shell(String)
    case spotify(String)
    case none

    private enum K: String, CodingKey { case type, keys, key, command }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        switch try c.decode(String.self, forKey: .type) {
        case "key": self = .key(try c.decode(String.self, forKey: .keys))
        case "media": self = .media(try c.decode(String.self, forKey: .key))
        case "shell": self = .shell(try c.decode(String.self, forKey: .command))
        case "spotify": self = .spotify(try c.decode(String.self, forKey: .command))
        case "none": self = .none
        case let t: throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "unknown action type \(t)")
        }
    }

    func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: K.self)
        switch self {
        case .key(let k): try c.encode("key", forKey: .type); try c.encode(k, forKey: .keys)
        case .media(let k): try c.encode("media", forKey: .type); try c.encode(k, forKey: .key)
        case .shell(let s): try c.encode("shell", forKey: .type); try c.encode(s, forKey: .command)
        case .spotify(let s): try c.encode("spotify", forKey: .type); try c.encode(s, forKey: .command)
        case .none: try c.encode("none", forKey: .type)
        }
    }

    var summary: String {
        switch self {
        case .key(let k): return "keys \(k)"
        case .media(let k): return "media \(k)"
        case .shell(let s): return "shell \(s.prefix(40))"
        case .spotify(let s): return "spotify \(s)"
        case .none: return "none"
        }
    }
}

struct Config: Codable {
    var camera: String?
    var holdFrames: Int
    var cooldownSeconds: Double
    var swipeMinDistance: Double
    var swipeWindowSeconds: Double
    var stillSpeed: Double          // static gestures only fire below this palm speed (frame widths/s)
    var minOpenExtent: Double       // open palm / two fingers need this landmark extent (fraction of frame)
    var mappings: [String: Action]

    static let path = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/gesturecam/config.json")

    static let `default` = Config(
        camera: nil,
        holdFrames: 15,      // ~0.5s: a swipe wind-up pauses ~12 frames with an open hand
        cooldownSeconds: 1.0,
        swipeMinDistance: 0.25,
        swipeWindowSeconds: 0.5,
        stillSpeed: 0.4,
        minOpenExtent: 0.28,
        mappings: [
            Gesture.openPalm.rawValue: .spotify("playpause"),
            Gesture.fist.rawValue: .media("mute"),
            Gesture.twoFingers.rawValue: .spotify("next"),
            Gesture.thumbsUp.rawValue: .shell("osascript -e 'display notification \"👍\" with title \"gesturecam\"'"),
            // Natural direction: content follows the hand. Swipe left → space on the right.
            Gesture.swipeLeft.rawValue: .key("ctrl+right"),
            Gesture.swipeRight.rawValue: .key("ctrl+left"),
        ]
    )

    private enum K: String, CodingKey { case camera, holdFrames, cooldownSeconds, swipeMinDistance, swipeWindowSeconds, stillSpeed, minOpenExtent, mappings }

    init(camera: String?, holdFrames: Int, cooldownSeconds: Double, swipeMinDistance: Double, swipeWindowSeconds: Double, stillSpeed: Double, minOpenExtent: Double, mappings: [String: Action]) {
        self.camera = camera; self.holdFrames = holdFrames; self.cooldownSeconds = cooldownSeconds
        self.swipeMinDistance = swipeMinDistance; self.swipeWindowSeconds = swipeWindowSeconds
        self.stillSpeed = stillSpeed; self.minOpenExtent = minOpenExtent; self.mappings = mappings
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        let def = Config.default
        camera = try c.decodeIfPresent(String.self, forKey: .camera)
        holdFrames = try c.decodeIfPresent(Int.self, forKey: .holdFrames) ?? def.holdFrames
        cooldownSeconds = try c.decodeIfPresent(Double.self, forKey: .cooldownSeconds) ?? def.cooldownSeconds
        swipeMinDistance = try c.decodeIfPresent(Double.self, forKey: .swipeMinDistance) ?? def.swipeMinDistance
        swipeWindowSeconds = try c.decodeIfPresent(Double.self, forKey: .swipeWindowSeconds) ?? def.swipeWindowSeconds
        stillSpeed = try c.decodeIfPresent(Double.self, forKey: .stillSpeed) ?? def.stillSpeed
        minOpenExtent = try c.decodeIfPresent(Double.self, forKey: .minOpenExtent) ?? def.minOpenExtent
        // Gestures missing from the file get their default; map to {"type":"none"} to disable one.
        mappings = def.mappings.merging(try c.decodeIfPresent([String: Action].self, forKey: .mappings) ?? [:]) { $1 }
    }

    func action(for g: Gesture) -> Action? {
        if case .none? = mappings[g.rawValue] { return nil }
        return mappings[g.rawValue]
    }

    /// Loads the config, writing the default file first if none exists.
    static func load() throws -> Config {
        if !FileManager.default.fileExists(atPath: path.path) {
            try Config.default.save()
        }
        return try JSONDecoder().decode(Config.self, from: Data(contentsOf: path))
    }

    func save() throws {
        try FileManager.default.createDirectory(at: Config.path.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(self).write(to: Config.path)
    }
}
