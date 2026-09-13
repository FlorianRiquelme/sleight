import AVFoundation
import Foundation

// MARK: - CLI args
let args = CommandLine.arguments
func flagValue(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

let devices = Camera.devices()
if args.contains("--list") {
    for d in devices { print("\(d.localizedName)  [\(d.deviceType.rawValue)]") }
    exit(0)
}
let wanted = flagValue("--camera")
guard let device = wanted.flatMap({ n in devices.first { $0.localizedName.localizedCaseInsensitiveContains(n) } }) ?? devices.first else {
    FileHandle.standardError.write("no camera found\n".data(using: .utf8)!)
    exit(1)
}
let verbose = args.contains("-v")

// MARK: - Pipeline
let detector = HandPoseDetector()
let classifier = GestureClassifier()
var stabilizer = GestureStabilizer()
var handVisible = false
var frames = 0
var lastReport = Date()
var camera: Camera?

func log(_ s: String) {
    let t = DateFormatter(); t.dateFormat = "HH:mm:ss.SSS"
    print("\(t.string(from: Date()))  \(s)")
    fflush(stdout)
}

func run() {
    do {
        let cam = try Camera(device: device)
        camera = cam
        log("camera: \(device.localizedName)")
        cam.onFrame = { buf in
            frames += 1
            let hand = detector.detect(buf)
            if (hand != nil) != handVisible {
                handVisible = hand != nil
                log(handVisible ? "hand in frame" : "hand lost")
                if !handVisible { _ = stabilizer.push(nil) }
            }
            let raw = hand.flatMap(classifier.classify)
            if verbose, let h = hand {
                log("raw=\(raw?.rawValue ?? "-") conf=\(String(format: "%.2f", h.confidence)) joints=\(h.points.count) \(h.chirality == .left ? "L" : h.chirality == .right ? "R" : "?")")
            }
            if let g = stabilizer.push(raw) {
                log("GESTURE  \(g.rawValue)")
            }
            let now = Date()
            if now.timeIntervalSince(lastReport) >= 5 {
                log("\(Int(Double(frames) / now.timeIntervalSince(lastReport))) fps")
                frames = 0; lastReport = now
            }
        }
        cam.start()
    } catch {
        log("camera error: \(error)")
        exit(1)
    }
}

AVCaptureDevice.requestAccess(for: .video) { granted in
    guard granted else { log("camera permission denied"); exit(1) }
    DispatchQueue.main.async(execute: run)
}
RunLoop.main.run()
