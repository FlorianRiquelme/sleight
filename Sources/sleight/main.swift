import AppKit
import AVFoundation
import Foundation
import QuartzCore

// MARK: - CLI args
let args = CommandLine.arguments
func flagValue(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}
let verbose = args.contains("-v")
let noUI = args.contains("--no-ui")
let dryRun = args.contains("--dry-run")
let debugAtLaunch = args.contains("--debug")
let recordPath = flagValue("--record")
let recordLabel = flagValue("--label")
let usageInterval = flagValue("--usage-interval").flatMap(Double.init) ?? 60

func log(_ s: String) {
    let t = DateFormatter(); t.dateFormat = "HH:mm:ss.SSS"
    print("\(t.string(from: Date()))  \(s)")
    fflush(stdout)
}

let devices = Camera.devices()
if args.contains("--list") {
    for d in devices { print("\(d.localizedName)  [\(d.deviceType.rawValue)]") }
    exit(0)
}

var config: Config
if let alt = flagValue("--config") {
    config = try JSONDecoder().decode(Config.self, from: Data(contentsOf: URL(fileURLWithPath: alt)))
} else {
    do { config = try Config.load() } catch {
        log("config error at \(Config.path.path): \(error). Using defaults.")
        config = .default
    }
}

// sleight replay <file.jsonl> [--config other.json] [-v | --csv]
if args.count > 2, args[1] == "replay" {
    exit(try Replay.run(file: URL(fileURLWithPath: args[2]), config: config, verbose: verbose, csv: args.contains("--csv")))
}

if let name = flagValue("--fire") {
    guard let g = Gesture(rawValue: name) else { log("unknown gesture '\(name)'. one of: \(Gesture.allCases.map(\.rawValue).joined(separator: ", "))"); exit(2) }
    guard let action = config.action(for: g) else { log("no action mapped for \(name)"); exit(2) }
    ActionRunner.ensureAccessibility()
    do { try ActionRunner.run(action); log("fired \(name) → \(action.summary)") } catch { log("action failed: \(error)"); exit(1) }
    exit(0)
}

let wanted = flagValue("--camera") ?? config.camera
let device = wanted.flatMap({ n in devices.first { $0.localizedName.localizedCaseInsensitiveContains(n) } }) ?? devices.first
if device == nil {
    if noUI {
        FileHandle.standardError.write("no camera found\n".data(using: .utf8)!)
        exit(1)
    }
    log("no camera found")
}

// MARK: - Wiring
let engine = Engine(config: config)
var statusBar: StatusBarController?

engine.onFPS = { fps in if verbose { log("\(fps) fps") } }
engine.onHand = { visible in if verbose { log(visible ? "hand in frame" : "hand lost") } }
engine.onRaw = { h, raw in
    if verbose {
        let side = h.chirality == .left ? "L" : h.chirality == .right ? "R" : "?"
        log("raw=\(raw?.rawValue ?? "-") conf=\(String(format: "%.2f", h.confidence)) joints=\(h.points.count) \(side)")
    }
}
let firesLog = Config.path.deletingLastPathComponent().appendingPathComponent("fires.log")
let fireGesture: (Gesture) -> Void = { g in
    let action = engine.config.action(for: g)
    let summary = action?.summary ?? "no action"
    log("GESTURE  \(g.rawValue) → \(summary)\(dryRun ? " (dry run)" : "")")
    // One line per fire, wall clock, so a day can be reviewed next to usage.csv and the misfire captures.
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    if !FileManager.default.fileExists(atPath: firesLog.path) { FileManager.default.createFile(atPath: firesLog.path, contents: nil) }
    if let h = try? FileHandle(forWritingTo: firesLog) {
        h.seekToEndOfFile(); h.write("\(f.string(from: Date()))  \(g.rawValue) → \(summary)\n".data(using: .utf8)!); try? h.close()
    }
    if engine.config.notifyOnFire { ActionRunner.notify(title: "sleight: \(g.rawValue)", body: summary) }
    guard !dryRun, let action else { return }
    do { try ActionRunner.run(action) } catch { log("action failed: \(error)") }
}

if !noUI {
    NSApplication.shared.setActivationPolicy(.accessory)
    statusBar = StatusBarController(engine: engine, device: device)
    // StatusBar owns onHand/onGesture for UI; chain the action + logging behind it.
    let uiGesture = engine.onGesture
    engine.onGesture = { g in uiGesture?(g); fireGesture(g) }
    let uiHand = engine.onHand
    engine.onHand = { v in uiHand?(v); if verbose { log(v ? "hand in frame" : "hand lost") } }
} else {
    engine.onGesture = fireGesture
}

let uiCameraError = engine.onCameraError
engine.onCameraError = { msg in uiCameraError?(msg); log("camera error: \(msg)") }

if !dryRun && !ActionRunner.ensureAccessibility() {
    log("Accessibility permission missing: grant it in System Settings → Privacy & Security → Accessibility, or actions will be swallowed.")
}

engine.usage = UsageLog(url: Config.path.deletingLastPathComponent().appendingPathComponent("usage.csv"), interval: usageInterval)

if let device {
    AVCaptureDevice.requestAccess(for: .video) { granted in
        DispatchQueue.main.async {
            guard granted else {
                if noUI { log("camera permission denied"); exit(1) }
                statusBar?.reportCameraProblem("Camera permission denied", permissionDenied: true)
                return
            }
            do {
                try engine.start(device: device)
                log("camera: \(device.localizedName)  config: \(Config.path.path)")
                if let recordPath {
                    let url = URL(fileURLWithPath: recordPath)
                    engine.recorder = try Recorder(url: url, camera: device.localizedName, label: recordLabel,
                                                   config: config, start: CACurrentMediaTime())
                    log("recording to \(url.path)\(recordLabel.map { "  label=\($0)" } ?? "")")
                    signal(SIGINT) { _ in
                        engine.recorder?.close()
                        log("recording closed (\(engine.recorder?.frameCount ?? 0) frames)")
                        exit(0)
                    }
                    signal(SIGTERM) { _ in engine.recorder?.close(); exit(0) }
                }
                if debugAtLaunch { statusBar?.showDebug() }
            } catch {
                if noUI { log("camera error: \(error)"); exit(1) }
                statusBar?.reportCameraProblem("Camera error: \(error.localizedDescription)")
            }
        }
    }
}

if noUI { RunLoop.main.run() } else { NSApplication.shared.run() }
