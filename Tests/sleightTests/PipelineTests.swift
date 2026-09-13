import XCTest
import Vision
@testable import sleight

final class PipelineTests: XCTestCase {
    /// How a non-extended finger sits: folded into the palm, hanging relaxed at PIP length, or
    /// curled past its PIP but from beyond the knuckles (fingers draped over a mouse).
    enum Closed { case curled, relaxed, hanging }

    /// Synthetic upright right hand. Non-extended fingers take the `closed` style.
    private func hand(index: Bool, middle: Bool, ring: Bool, little: Bool, thumbOut: Bool, thumbUp: Bool = false, offset: CGFloat = 0, scale: CGFloat = 1, closed: Closed = .curled) -> Hand {
        let h = rawHand(index: index, middle: middle, ring: ring, little: little, thumbOut: thumbOut, thumbUp: thumbUp, offset: offset, closed: closed)
        guard scale != 1, let w = h[.wrist] else { return h }
        let pts = h.points.mapValues { CGPoint(x: w.x + ($0.x - w.x) * scale, y: w.y + ($0.y - w.y) * scale) }
        return Hand(chirality: h.chirality, points: pts, confidence: h.confidence)
    }

    private func rawHand(index: Bool, middle: Bool, ring: Bool, little: Bool, thumbOut: Bool, thumbUp: Bool, offset: CGFloat, closed: Closed) -> Hand {
        var p: [sleight.Joint: CGPoint] = [:]
        let wrist = CGPoint(x: 0.5 + offset, y: 0.3)
        p[.wrist] = wrist
        let fingers: [(sleight.Joint, sleight.Joint, sleight.Joint, sleight.Joint, CGFloat, Bool)] = [
            (.indexMCP, .indexPIP, .indexDIP, .indexTip, -0.06, index),
            (.middleMCP, .middlePIP, .middleDIP, .middleTip, -0.02, middle),
            (.ringMCP, .ringPIP, .ringDIP, .ringTip, 0.02, ring),
            (.littleMCP, .littlePIP, .littleDIP, .littleTip, 0.06, little),
        ]
        for (mcp, pip, dip, tip, dx, ext) in fingers {
            let x = wrist.x + dx
            p[mcp] = CGPoint(x: x, y: 0.45)
            // Wrist is at y 0.30, palm length 0.15. Extended: tip/PIP 1.55. Curled: tip/PIP 0.5,
            // tip 0.67 palm lengths. Relaxed: tip/PIP 1.0. Hanging: tip/PIP 0.69 but tip 1.2 palms.
            let (py, dy, ty): (CGFloat, CGFloat, CGFloat)
            switch (ext, closed) {
            case (true, _): (py, dy, ty) = (0.52, 0.58, 0.64)
            case (false, .curled): (py, dy, ty) = (0.50, 0.46, 0.40)
            case (false, .relaxed): (py, dy, ty) = (0.50, 0.51, 0.50)
            case (false, .hanging): (py, dy, ty) = (0.56, 0.53, 0.48)
            }
            p[pip] = CGPoint(x: x, y: py)
            p[dip] = CGPoint(x: x, y: dy)
            p[tip] = CGPoint(x: x, y: ty)
        }
        // Thumb: out to the side and up, or tucked over the index knuckle.
        p[.thumbCMC] = CGPoint(x: wrist.x - 0.05, y: 0.36)
        if thumbOut {
            p[.thumbMP] = CGPoint(x: wrist.x - 0.10, y: thumbUp ? 0.45 : 0.40)
            p[.thumbIP] = CGPoint(x: wrist.x - 0.13, y: thumbUp ? 0.52 : 0.42)
            p[.thumbTip] = CGPoint(x: wrist.x - 0.16, y: thumbUp ? 0.60 : 0.44)
        } else {
            p[.thumbMP] = CGPoint(x: wrist.x - 0.07, y: 0.42)
            p[.thumbIP] = CGPoint(x: wrist.x - 0.06, y: 0.45)
            p[.thumbTip] = CGPoint(x: wrist.x - 0.055, y: 0.46)
        }
        return Hand(chirality: .right, points: p, confidence: 1)
    }

    private var config: Config { .default }

    func testClassifierOnSyntheticPoses() {
        let c = GestureClassifier()
        XCTAssertEqual(c.classify(hand(index: true, middle: true, ring: true, little: true, thumbOut: true)), .openPalm)
        XCTAssertEqual(c.classify(hand(index: true, middle: true, ring: true, little: true, thumbOut: false)), .openPalm,
                       "relaxed palm with thumb alongside the index is still an open palm")
        XCTAssertEqual(c.classify(hand(index: false, middle: false, ring: false, little: false, thumbOut: false)), .fist)
        XCTAssertEqual(c.classify(hand(index: true, middle: true, ring: false, little: false, thumbOut: false)), .twoFingers)
        XCTAssertEqual(c.classify(hand(index: false, middle: false, ring: false, little: false, thumbOut: true, thumbUp: true)), .thumbsUp)
    }

    func testSmallHandsAreRejected() {
        let c = GestureClassifier()
        let palm = hand(index: true, middle: true, ring: true, little: true, thumbOut: true)
        XCTAssertGreaterThan(palm.extent, c.minOpenExtent, "synthetic palm must be large enough to count")
        XCTAssertEqual(c.classify(palm), .openPalm)
        let far = hand(index: true, middle: true, ring: true, little: true, thumbOut: true, scale: 0.5)
        XCTAssertNil(c.classify(far))
        XCTAssertEqual(c.features(far)?.tooSmall, true)
        // A fist is compact, so its floor is lower: 0.8 scale still counts, 0.5 does not.
        let fist = hand(index: false, middle: false, ring: false, little: false, thumbOut: false)
        XCTAssertLessThan(fist.extent, c.minOpenExtent, "a fist at gesture distance is smaller than an open palm")
        XCTAssertEqual(c.classify(hand(index: false, middle: false, ring: false, little: false, thumbOut: false, scale: 0.8)), .fist)
        let farFist = hand(index: false, middle: false, ring: false, little: false, thumbOut: false, scale: 0.5)
        XCTAssertNil(c.classify(farFist))
        XCTAssertEqual(c.features(farFist)?.tooSmall, true)
    }

    func testClosedPosesNeedCurledFingers() {
        let c = GestureClassifier()
        // Fingers hanging relaxed (tip at PIP length): a hand on a mouse or keyboard, not a fist.
        let relaxed = hand(index: false, middle: false, ring: false, little: false, thumbOut: false, closed: .relaxed)
        XCTAssertNil(c.classify(relaxed))
        XCTAssertEqual(c.features(relaxed)?.curled, 0)
        XCTAssertNil(c.classify(hand(index: false, middle: false, ring: false, little: false, thumbOut: true, thumbUp: true, closed: .relaxed)))
        XCTAssertNil(c.classify(hand(index: true, middle: true, ring: false, little: false, thumbOut: false, closed: .relaxed)),
                     "two fingers needs the other two folded, not merely not extended")
        // Curled past the PIP but from beyond the knuckles (draped over a mouse): still not a fist,
        // while a thumbs up is allowed to project its folded fingers past the knuckles.
        let hanging = hand(index: false, middle: false, ring: false, little: false, thumbOut: false, closed: .hanging)
        XCTAssertEqual(c.features(hanging)?.curled, 4)
        XCTAssertGreaterThan(c.features(hanging)?.tipReach ?? 0, GestureClassifier.fistTipReach)
        XCTAssertNil(c.classify(hanging))
        XCTAssertEqual(c.classify(hand(index: false, middle: false, ring: false, little: false, thumbOut: true, thumbUp: true, closed: .hanging)), .thumbsUp)
    }

    func testClosedHandJumpingBetweenPositionsDoesNotSwipe() {
        // Vision alternating between two closed hands on the desk: the palm center teleports.
        let p = Pipeline(config: config)
        var fired: [Gesture] = []
        for i in 0..<30 {
            let h = hand(index: false, middle: false, ring: false, little: false, thumbOut: false, offset: i % 2 == 0 ? 0 : 0.3)
            if let g = p.process(h, at: Double(i) / 30).fired { fired.append(g) }
        }
        XCTAssertEqual(fired, [])
    }

    func testOpenHandLingeringAfterSwipeDoesNotFire() {
        let p = Pipeline(config: config)
        var fired: [Gesture] = []
        for i in 0..<12 {
            let h = hand(index: true, middle: true, ring: true, little: true, thumbOut: true, offset: CGFloat(i) * 0.03)
            if let g = p.process(h, at: Double(i) / 30).fired { fired.append(g) }
        }
        XCTAssertEqual(fired, [.swipeLeft])
        // Hand stays open and still for 3s after the swipe: no openPalm.
        let rest = hand(index: true, middle: true, ring: true, little: true, thumbOut: true, offset: 0.33)
        for i in 12..<100 {
            if let g = p.process(rest, at: Double(i) / 30).fired { fired.append(g) }
        }
        XCTAssertEqual(fired, [.swipeLeft])
        // Closing to a fist is a new intent and fires.
        let fist = hand(index: false, middle: false, ring: false, little: false, thumbOut: false, offset: 0.33)
        for i in 100..<120 {
            if let g = p.process(fist, at: Double(i) / 30).fired { fired.append(g) }
        }
        XCTAssertEqual(fired, [.swipeLeft, .fist])
    }

    func testStillFistFiresOnceAfterHold() {
        let p = Pipeline(config: config)
        let fist = hand(index: false, middle: false, ring: false, little: false, thumbOut: false)
        var fired: [(Double, Gesture)] = []
        for i in 0..<60 {
            let t = Double(i) / 30
            if let g = p.process(fist, at: t).fired { fired.append((t, g)) }
        }
        XCTAssertEqual(fired.map(\.1), [.fist])
        XCTAssertEqual(fired.first?.0 ?? -1, Double(config.holdFrames - 1) / 30, accuracy: 0.001)
    }

    func testMovingPalmIsGatedThenSwipes() {
        let p = Pipeline(config: config)
        var fired: [Gesture] = []
        var gatedFrames = 0
        for i in 0..<12 {
            let h = hand(index: true, middle: true, ring: true, little: true, thumbOut: true, offset: CGFloat(i) * 0.03)
            let r = p.process(h, at: Double(i) / 30)
            if r.gated { gatedFrames += 1 }
            if let g = r.fired { fired.append(g) }
        }
        XCTAssertEqual(fired, [.swipeLeft])
        XCTAssertGreaterThan(gatedFrames, 3, "static classification should be suppressed while moving")
    }

    func testCooldownUsesFrameTime() {
        let p = Pipeline(config: config)
        let fist = hand(index: false, middle: false, ring: false, little: false, thumbOut: false)
        let palm = hand(index: true, middle: true, ring: true, little: true, thumbOut: true)
        var fired: [Gesture] = []
        let n = config.holdFrames + 2
        // n frames fist then n frames palm at 30fps (~1.1s total) → palm lands inside the 1s cooldown.
        for i in 0..<(2 * n) {
            if let g = p.process(i < n ? fist : palm, at: Double(i) / 30).fired { fired.append(g) }
        }
        XCTAssertEqual(fired, [.fist])
        // Same sequence at 5fps (~6.8s total) → both fire.
        let p2 = Pipeline(config: config)
        fired = []
        for i in 0..<(2 * n) {
            if let g = p2.process(i < n ? fist : palm, at: Double(i) * 0.2).fired { fired.append(g) }
        }
        XCTAssertEqual(fired, [.fist, .openPalm])
    }

    func testRecordingRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sleight-test-\(UUID().uuidString)")
        let url = dir.appendingPathComponent("rec.jsonl")
        let rec = try Recorder(url: url, camera: "test", label: "fist", config: config, start: 100)
        let fist = hand(index: false, middle: false, ring: false, little: false, thumbOut: false)
        let p = Pipeline(config: config)
        let n = config.holdFrames + 2
        for i in 0..<n {
            let t = 100 + Double(i) / 30
            rec.append(hand: fist, at: t, result: p.process(fist, at: t))
        }
        rec.append(hand: nil, at: 101, result: p.process(nil, at: 101))
        rec.close()

        let (header, frames) = try Recording.load(url)
        XCTAssertEqual(header?.label, "fist")
        XCTAssertEqual(header?.camera, "test")
        XCTAssertEqual(frames.count, n + 1)
        XCTAssertEqual(frames[0].t, 0, accuracy: 0.0001)
        XCTAssertNil(frames[n].hand)
        let fireIndex = config.holdFrames - 1
        XCTAssertEqual(frames[fireIndex].d.fired, "fist")

        // Replaying the decoded hands reproduces the fire at the same frame.
        let p2 = Pipeline(config: config)
        let refired = frames.compactMap { f in p2.process(f.hand?.hand, at: f.t).fired.map { (f.t, $0) } }
        XCTAssertEqual(refired.count, 1)
        XCTAssertEqual(refired.first?.1, .fist)
        XCTAssertEqual(refired.first?.0 ?? -1, frames[fireIndex].t, accuracy: 0.0001)
        XCTAssertEqual(frames[3].hand?.hand.points.count, fist.points.count)
        try? FileManager.default.removeItem(at: dir)
    }
}
