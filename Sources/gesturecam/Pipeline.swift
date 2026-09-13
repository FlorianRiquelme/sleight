import Foundation

/// Everything between "here is a hand (or not) at time t" and "a gesture fired".
/// Camera-free so recordings can be replayed through it deterministically.
final class Pipeline {
    struct Result {
        var fired: Gesture?
        var features: HandFeatures?
        var gated: Bool
        var speed: CGFloat
        var trail: [CGPoint]
        var candidate: Gesture?
        var holdCount: Int
    }

    private(set) var config: Config
    private let classifier = GestureClassifier()
    private var stabilizer: GestureStabilizer
    private var swipe: SwipeDetector
    private var lastFire: TimeInterval = -.infinity
    private(set) var handVisible = false

    init(config: Config) {
        self.config = config
        stabilizer = GestureStabilizer(holdFrames: config.holdFrames)
        swipe = Pipeline.makeSwipe(config)
    }

    private static func makeSwipe(_ c: Config) -> SwipeDetector {
        var s = SwipeDetector()
        s.minDistance = CGFloat(c.swipeMinDistance)
        s.window = c.swipeWindowSeconds
        return s
    }

    func apply(_ c: Config) {
        config = c
        reset()
    }

    func reset() {
        stabilizer = GestureStabilizer(holdFrames: config.holdFrames)
        swipe = Pipeline.makeSwipe(config)
        lastFire = -.infinity
        handVisible = false
    }

    var holdFrames: Int { stabilizer.holdFrames }

    func process(_ hand: Hand?, at t: TimeInterval) -> Result {
        if (hand != nil) != handVisible {
            handVisible = hand != nil
            if !handVisible { swipe.reset() }
        }

        var r = Result(fired: nil, features: nil, gated: false, speed: 0, trail: [], candidate: nil, holdCount: 0)
        var swiped = false
        if let center = hand?.palmCenter {
            if let s = swipe.push(center, at: t) {
                _ = stabilizer.push(nil)
                r.fired = fire(s, at: t)
                swiped = true
            } else {
                r.speed = swipe.recentSpeed(at: t)
                r.gated = r.speed > CGFloat(config.stillSpeed)
            }
        }

        if !swiped {
            r.features = r.gated ? nil : hand.flatMap(classifier.features)
            if let g = stabilizer.push(r.features?.gesture) { r.fired = fire(g, at: t) }
        } else {
            r.gated = true
        }

        r.trail = swipe.trail
        r.candidate = stabilizer.candidate
        r.holdCount = stabilizer.count
        return r
    }

    private func fire(_ g: Gesture, at t: TimeInterval) -> Gesture? {
        guard t - lastFire >= config.cooldownSeconds else { return nil }
        lastFire = t
        return g
    }
}
