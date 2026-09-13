import AVFoundation
import Foundation

/// Camera → hand pose → classifier → stabilizer → cooldown → onGesture.
final class Engine {
    var config: Config
    private(set) var camera: Camera?
    private let detector = HandPoseDetector()
    private let classifier = GestureClassifier()
    private var stabilizer: GestureStabilizer
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
        if handVisible { handVisible = false; onHand?(false) }
    }

    func apply(_ newConfig: Config) {
        config = newConfig
        stabilizer = GestureStabilizer(holdFrames: newConfig.holdFrames)
    }

    private func handle(_ buf: CMSampleBuffer) {
        frames += 1
        let hand = detector.detect(buf)
        if (hand != nil) != handVisible {
            handVisible = hand != nil
            onHand?(handVisible)
        }
        let raw = hand.flatMap(classifier.classify)
        if let h = hand { onRaw?(h, raw) }

        if let g = stabilizer.push(raw) {
            let now = Date()
            if now.timeIntervalSince(lastFire) >= config.cooldownSeconds {
                lastFire = now
                onGesture?(g)
            }
        }

        let now = Date()
        let elapsed = now.timeIntervalSince(lastReport)
        if elapsed >= 5 {
            onFPS?(Int(Double(frames) / elapsed))
            frames = 0; lastReport = now
        }
    }
}
