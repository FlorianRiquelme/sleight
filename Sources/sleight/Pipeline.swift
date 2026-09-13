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
    private var classifier: GestureClassifier
    private var stabilizer: GestureStabilizer
    private var swipe: SwipeDetector
    private var lastFire: TimeInterval = -.infinity
    private var primeAfterSwipe = false
    private(set) var handVisible = false

    init(config: Config) {
        self.config = config
        classifier = GestureClassifier(minOpenExtent: CGFloat(config.minOpenExtent))
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
        classifier = GestureClassifier(minOpenExtent: CGFloat(config.minOpenExtent))
        stabilizer = GestureStabilizer(holdFrames: config.holdFrames)
        swipe = Pipeline.makeSwipe(config)
        lastFire = -.infinity
        primeAfterSwipe = false
        handVisible = false
    }

    var holdFrames: Int { stabilizer.holdFrames }

    func process(_ hand: Hand?, at t: TimeInterval) -> Result {
        // Swipe samples are kept across dropouts on purpose; they age out by time.
        handVisible = hand != nil

        var r = Result(fired: nil, features: nil, gated: false, speed: 0, trail: [], candidate: nil, holdCount: 0)
        var swiped = false
        if let center = hand?.palmCenter {
            if let s = swipe.push(center, at: t) {
                _ = stabilizer.push(nil)
                r.fired = fire(s, at: t)
                swiped = true
                primeAfterSwipe = true
            } else {
                r.speed = swipe.recentSpeed(at: t)
                r.gated = r.speed > CGFloat(config.stillSpeed)
            }
        }

        if !swiped {
            r.features = r.gated ? nil : hand.flatMap(classifier.features)
            if primeAfterSwipe, let f = r.features {
                // The pose the hand settles into after a swipe is part of the swipe, not a new intent.
                stabilizer.prime(f.gesture)
                primeAfterSwipe = false
            } else if let g = stabilizer.push(r.features?.gesture) {
                r.fired = fire(g, at: t)
            }
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
