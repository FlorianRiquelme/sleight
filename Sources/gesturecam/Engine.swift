import AVFoundation
import Foundation
import QuartzCore
import VideoToolbox

/// Snapshot of one processed frame for the debug window.
struct DebugFrame {
    let image: CGImage?
    let hand: Hand?
    let features: HandFeatures?
    let gated: Bool               // static classification suppressed because the hand is moving
    let speed: CGFloat            // palm speed, frame widths per second
    let trail: [CGPoint]          // recent palm centers (oldest first)
    let swipeMinDistance: CGFloat
    let stillSpeed: CGFloat
    let candidate: Gesture?
    let holdCount: Int
    let holdFrames: Int
    let fps: Int
    let lastFired: (gesture: Gesture, at: Date)?
}

/// Camera → hand pose → Pipeline → actions. Owns the camera and the Vision detector.
final class Engine {
    var config: Config { pipeline.config }
    private(set) var camera: Camera?
    private let detector = HandPoseDetector()
    let pipeline: Pipeline
    private var handVisible = false
    private var frames = 0
    private var lastReport = Date()
    private var lastFPS = 0
    private var lastFired: (gesture: Gesture, at: Date)?

    var onGesture: ((Gesture) -> Void)?
    var onHand: ((Bool) -> Void)?
    var onFPS: ((Int) -> Void)?
    var onRaw: ((Hand, Gesture?) -> Void)?
    var onDebug: ((DebugFrame) -> Void)?
    var recorder: Recorder?

    var isRunning: Bool { camera?.session.isRunning ?? false }

    init(config: Config) {
        pipeline = Pipeline(config: config)
    }

    func start(device: AVCaptureDevice) throws {
        stop()
        let cam = try Camera(device: device)
        cam.onFrame = { [weak self] in self?.handle($0) }
        camera = cam
        cam.start()
    }

    func stop() {
        camera?.stop()
        camera = nil
        pipeline.reset()
        if handVisible { handVisible = false; onHand?(false) }
    }

    func apply(_ newConfig: Config) { pipeline.apply(newConfig) }

    private func handle(_ buf: CMSampleBuffer) {
        frames += 1
        let hand = detector.detect(buf)
        if (hand != nil) != handVisible {
            handVisible = hand != nil
            onHand?(handVisible)
        }

        let t = CACurrentMediaTime()
        let r = pipeline.process(hand, at: t)
        if let h = hand, !r.gated { onRaw?(h, r.features?.gesture) }
        if let g = r.fired {
            lastFired = (g, Date())
            onGesture?(g)
        }
        recorder?.append(hand: hand, at: t, result: r)

        if let onDebug {
            var cg: CGImage?
            if let pb = CMSampleBufferGetImageBuffer(buf) {
                VTCreateCGImageFromCVPixelBuffer(pb, options: nil, imageOut: &cg)
            }
            onDebug(DebugFrame(
                image: cg, hand: hand, features: r.features, gated: r.gated, speed: r.speed,
                trail: r.trail, swipeMinDistance: CGFloat(config.swipeMinDistance),
                stillSpeed: CGFloat(config.stillSpeed),
                candidate: r.candidate, holdCount: r.holdCount, holdFrames: pipeline.holdFrames,
                fps: lastFPS, lastFired: lastFired))
        }

        let now = Date()
        let elapsed = now.timeIntervalSince(lastReport)
        if elapsed >= 5 {
            lastFPS = Int(Double(frames) / elapsed)
            onFPS?(lastFPS)
            frames = 0; lastReport = now
        }
    }
}
