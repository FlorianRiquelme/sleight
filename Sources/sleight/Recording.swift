import Foundation
import Vision

/// One line of a .jsonl recording. `hand` is the input; `d` is what the pipeline derived at the time.
struct RecordedFrame: Codable {
    struct HandData: Codable {
        var c: String              // chirality: L, R, ?
        var conf: Float
        var p: [String: [Double]]  // joint key → [x, y]

        init(_ h: Hand) {
            c = h.chirality == .left ? "L" : h.chirality == .right ? "R" : "?"
            conf = h.confidence
            p = Dictionary(uniqueKeysWithValues: h.points.map { ($0.key.rawValue.rawValue, [Double($0.value.x), Double($0.value.y)]) })
        }

        var hand: Hand {
            let pts = Dictionary(uniqueKeysWithValues: p.map {
                (Joint(rawValue: VNRecognizedPointKey(rawValue: $0.key)), CGPoint(x: $0.value[0], y: $0.value[1]))
            })
            return Hand(chirality: c == "L" ? .left : c == "R" ? .right : .unknown, points: pts, confidence: conf)
        }
    }

    struct Derived: Codable {
        var pose: String?
        var gated: Bool
        var speed: Double
        var hold: Int
        var cand: String?
        var fired: String?

        init(_ r: Pipeline.Result) {
            pose = r.features?.gesture?.rawValue
            gated = r.gated
            speed = Double(r.speed)
            hold = r.holdCount
            cand = r.candidate?.rawValue
            fired = r.fired?.rawValue
        }
    }

    var t: Double
    var label: String?
    var hand: HandData?
    var d: Derived
}

struct RecordingHeader: Codable {
    var type = "header"
    var version = 1
    var recorded: Date
    var camera: String
    var label: String?
    var config: Config
}

/// Appends frames to a .jsonl file. Header first, then one frame per line.
final class Recorder {
    let url: URL
    let label: String?
    private let handle: FileHandle
    private let encoder = JSONEncoder()
    private let start: TimeInterval
    private(set) var frameCount = 0
    private let queue = DispatchQueue(label: "sleight.recorder")
    private var closed = false

    init(url: URL, camera: String, label: String?, config: Config, start: TimeInterval) throws {
        self.url = url
        self.label = label
        self.start = start
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try FileHandle(forWritingTo: url)
        encoder.dateEncodingStrategy = .iso8601
        var line = try encoder.encode(RecordingHeader(recorded: Date(), camera: camera, label: label, config: config))
        line.append(0x0A)
        handle.write(line)
    }

    func append(hand: Hand?, at t: TimeInterval, result: Pipeline.Result) {
        let frame = RecordedFrame(t: t - start, label: label, hand: hand.map(RecordedFrame.HandData.init), d: .init(result))
        queue.async { [self] in
            guard !closed, var line = try? encoder.encode(frame) else { return }
            line.append(0x0A)
            handle.write(line)
            frameCount += 1
        }
    }

    func close() {
        queue.sync { closed = true; try? handle.close() }
    }

    static func defaultURL() -> URL {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"
        return Config.path.deletingLastPathComponent()
            .appendingPathComponent("recordings/\(f.string(from: Date())).jsonl")
    }
}

/// Ring buffer of the last `seconds` of frames, so a misfire can be saved as a labeled
/// recording after the fact without having started one in advance.
final class FrameBuffer {
    private struct Entry { let hand: Hand?; let t: TimeInterval; let result: Pipeline.Result }
    private let seconds: TimeInterval
    private let lock = NSLock()
    private var entries: [Entry] = []

    init(seconds: TimeInterval) {
        self.seconds = seconds
    }

    /// Called on the camera queue.
    func append(hand: Hand?, at t: TimeInterval, result: Pipeline.Result) {
        lock.lock(); defer { lock.unlock() }
        entries.append(Entry(hand: hand, t: t, result: result))
        let cutoff = t - seconds
        while let first = entries.first, first.t < cutoff { entries.removeFirst() }
    }

    /// Writes the buffered frames as a .jsonl recording, rebased so the first frame is t=0.
    /// Returns the frame count. Called from the main thread.
    func save(to url: URL, label: String, camera: String, config: Config) throws -> Int {
        lock.lock()
        let snapshot = entries
        lock.unlock()
        guard let first = snapshot.first else { return 0 }
        let rec = try Recorder(url: url, camera: camera, label: label, config: config, start: first.t)
        for e in snapshot { rec.append(hand: e.hand, at: e.t, result: e.result) }
        rec.close()
        return snapshot.count
    }

    static func misfireURL(label: String) -> URL {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"
        return Config.path.deletingLastPathComponent()
            .appendingPathComponent("recordings/\(label)-misfire-\(f.string(from: Date())).jsonl")
    }
}

enum Recording {
    static func load(_ url: URL) throws -> (header: RecordingHeader?, frames: [RecordedFrame]) {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        var header: RecordingHeader?
        var frames: [RecordedFrame] = []
        for line in try String(contentsOf: url, encoding: .utf8).split(separator: "\n") where !line.isEmpty {
            let data = Data(line.utf8)
            if header == nil, frames.isEmpty, let h = try? dec.decode(RecordingHeader.self, from: data), h.type == "header" {
                header = h
            } else {
                frames.append(try dec.decode(RecordedFrame.self, from: data))
            }
        }
        return (header, frames)
    }
}
