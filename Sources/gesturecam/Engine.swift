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

/// Camera → hand pose → classifier → stabilizer → cooldown → onGesture.
final class Engine {
    var config: Config
    private(set) var camera: Camera?
    private let detector = HandPoseDetector()
    private let classifier = GestureClassifier()
    private var stabilizer: GestureStabilizer
    private var swipe: SwipeDetector
    private var lastFire = Date.distantPast
    private var handVisible = false
    private var frames = 0
    private var lastReport = Date()

    var onGesture: ((Gesture) -> Void)?
    var onHand: ((Bool) -> Void)?
    var onFPS: ((Int) -> Void)?
    var onRaw: ((Hand, Gesture?) -> Void)?
    var onDebug: ((DebugFrame) -> Void)?
    private var lastFPS = 0
    private var lastFired: (gesture: Gesture, at: Date)?

    var isRunning: Bool { camera?.session.isRunning ?? false }

    init(config: Config) {
        self.config = config
        self.stabilizer = GestureStabilizer(holdFrames: config.holdFrames)
        self.swipe = Engine.makeSwipe(config)
    }

    private static func makeSwipe(_ c: Config) -> SwipeDetector {
        var s = SwipeDetector()
        s.minDistance = CGFloat(c.swipeMinDistance)
        s.window = c.swipeWindowSeconds
        return s
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
        stabilizer = GestureStabilizer(holdFrames: config.holdFrames)
        swipe.reset()
        if handVisible { handVisible = false; onHand?(false) }
    }

    func apply(_ newConfig: Config) {
        config = newConfig
        stabilizer = GestureStabilizer(holdFrames: newConfig.holdFrames)
        swipe = Engine.makeSwipe(newConfig)
    }

    private func fire(_ g: Gesture) {
        let now = Date()
        guard now.timeIntervalSince(lastFire) >= config.cooldownSeconds else { return }
        lastFire = now
        lastFired = (g, now)
        onGesture?(g)
    }

    private func handle(_ buf: CMSampleBuffer) {
        frames += 1
        let hand = detector.detect(buf)
        if (hand != nil) != handVisible {
            handVisible = hand != nil
            onHand?(handVisible)
            if !handVisible { swipe.reset() }
        }

        // Dynamic: swipes on palm motion.
        let t = CACurrentMediaTime()
        var moving = false
        var swiped = false
        var speed: CGFloat = 0
        if let center = hand?.palmCenter {
            if let s = swipe.push(center, at: t) {
                _ = stabilizer.push(nil)
                fire(s)
                swiped = true
            } else {
                speed = swipe.recentSpeed(at: t)
                moving = speed > CGFloat(config.stillSpeed)
            }
        }

        // Static: only while the hand is still, so a moving open palm doesn't also fire.
        let features = (moving || swiped) ? nil : hand.flatMap(classifier.features)
        let raw = features?.gesture
        if !swiped {
            if let h = hand { onRaw?(h, raw) }
            if let g = stabilizer.push(raw) { fire(g) }
        }

        if let onDebug {
            var cg: CGImage?
            if let pb = CMSampleBufferGetImageBuffer(buf) {
                VTCreateCGImageFromCVPixelBuffer(pb, options: nil, imageOut: &cg)
            }
            onDebug(DebugFrame(
                image: cg, hand: hand, features: features, gated: moving || swiped, speed: speed,
                trail: swipe.trail, swipeMinDistance: CGFloat(config.swipeMinDistance),
                stillSpeed: CGFloat(config.stillSpeed),
                candidate: stabilizer.candidate, holdCount: stabilizer.count, holdFrames: stabilizer.holdFrames,
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
