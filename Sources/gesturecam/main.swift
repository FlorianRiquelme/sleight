import AppKit
import AVFoundation
import Foundation

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
do { config = try Config.load() } catch {
    log("config error at \(Config.path.path): \(error). Using defaults.")
    config = .default
}

if let name = flagValue("--fire") {
    guard let g = Gesture(rawValue: name) else { log("unknown gesture '\(name)'. one of: \(Gesture.allCases.map(\.rawValue).joined(separator: ", "))"); exit(2) }
    guard let action = config.action(for: g) else { log("no action mapped for \(name)"); exit(2) }
    ActionRunner.ensureAccessibility()
    do { try ActionRunner.run(action); log("fired \(name) → \(action.summary)") } catch { log("action failed: \(error)"); exit(1) }
    exit(0)
}

let wanted = flagValue("--camera") ?? config.camera
guard let device = wanted.flatMap({ n in devices.first { $0.localizedName.localizedCaseInsensitiveContains(n) } }) ?? devices.first else {
    FileHandle.standardError.write("no camera found\n".data(using: .utf8)!)
    exit(1)
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
let fireGesture: (Gesture) -> Void = { g in
    let action = engine.config.action(for: g)
    log("GESTURE  \(g.rawValue) → \(action?.summary ?? "no action")\(dryRun ? " (dry run)" : "")")
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

if !dryRun && !ActionRunner.ensureAccessibility() {
    log("Accessibility permission missing: grant it in System Settings → Privacy & Security → Accessibility, or actions will be swallowed.")
}

AVCaptureDevice.requestAccess(for: .video) { granted in
    DispatchQueue.main.async {
        guard granted else { log("camera permission denied"); exit(1) }
        do {
            try engine.start(device: device)
            log("camera: \(device.localizedName)  config: \(Config.path.path)")
            if debugAtLaunch { statusBar?.showDebug() }
        } catch {
            log("camera error: \(error)"); exit(1)
        }
    }
}

if noUI { RunLoop.main.run() } else { NSApplication.shared.run() }
