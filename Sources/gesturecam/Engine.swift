import AVFoundation
import Foundation
import QuartzCore

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
        if let center = hand?.palmCenter {
            if let s = swipe.push(center, at: t) {
                _ = stabilizer.push(nil)
                fire(s)
                return
            }
            moving = swipe.recentSpeed(at: t) > CGFloat(config.stillSpeed)
        }

        // Static: only while the hand is still, so a moving open palm doesn't also fire.
        let raw = moving ? nil : hand.flatMap(classifier.classify)
        if let h = hand { onRaw?(h, raw) }
        if let g = stabilizer.push(raw) { fire(g) }

        let now = Date()
        let elapsed = now.timeIntervalSince(lastReport)
        if elapsed >= 5 {
            onFPS?(Int(Double(frames) / elapsed))
            frames = 0; lastReport = now
        }
    }
}
