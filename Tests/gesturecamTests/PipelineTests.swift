import XCTest
import Vision
@testable import gesturecam

final class PipelineTests: XCTestCase {
    /// Synthetic upright right hand. `curl` per finger folds the tip back toward the wrist.
    private func hand(index: Bool, middle: Bool, ring: Bool, little: Bool, thumbOut: Bool, thumbUp: Bool = false, offset: CGFloat = 0) -> Hand {
        var p: [gesturecam.Joint: CGPoint] = [:]
        let wrist = CGPoint(x: 0.5 + offset, y: 0.3)
        p[.wrist] = wrist
        let fingers: [(gesturecam.Joint, gesturecam.Joint, gesturecam.Joint, gesturecam.Joint, CGFloat, Bool)] = [
            (.indexMCP, .indexPIP, .indexDIP, .indexTip, -0.06, index),
            (.middleMCP, .middlePIP, .middleDIP, .middleTip, -0.02, middle),
            (.ringMCP, .ringPIP, .ringDIP, .ringTip, 0.02, ring),
            (.littleMCP, .littlePIP, .littleDIP, .littleTip, 0.06, little),
        ]
        for (mcp, pip, dip, tip, dx, ext) in fingers {
            let x = wrist.x + dx
            p[mcp] = CGPoint(x: x, y: 0.45)
            p[pip] = CGPoint(x: x, y: ext ? 0.52 : 0.50)
            p[dip] = CGPoint(x: x, y: ext ? 0.58 : 0.46)
            p[tip] = CGPoint(x: x, y: ext ? 0.64 : 0.40)
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
        // 10 frames fist, 10 frames palm, all within 0.7s → palm is inside cooldown.
        for i in 0..<20 {
            if let g = p.process(i < 10 ? fist : palm, at: Double(i) / 30).fired { fired.append(g) }
        }
        XCTAssertEqual(fired, [.fist])
        // Same sequence spread over 4s → both fire.
        let p2 = Pipeline(config: config)
        fired = []
        for i in 0..<20 {
            if let g = p2.process(i < 10 ? fist : palm, at: Double(i) * 0.2).fired { fired.append(g) }
        }
        XCTAssertEqual(fired, [.fist, .openPalm])
    }

    func testRecordingRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gesturecam-test-\(UUID().uuidString)")
        let url = dir.appendingPathComponent("rec.jsonl")
        let rec = try Recorder(url: url, camera: "test", label: "fist", config: config, start: 100)
        let fist = hand(index: false, middle: false, ring: false, little: false, thumbOut: false)
        let p = Pipeline(config: config)
        for i in 0..<10 {
            let t = 100 + Double(i) / 30
            rec.append(hand: fist, at: t, result: p.process(fist, at: t))
        }
        rec.append(hand: nil, at: 101, result: p.process(nil, at: 101))
        rec.close()

        let (header, frames) = try Recording.load(url)
        XCTAssertEqual(header?.label, "fist")
        XCTAssertEqual(header?.camera, "test")
        XCTAssertEqual(frames.count, 11)
        XCTAssertEqual(frames[0].t, 0, accuracy: 0.0001)
        XCTAssertNil(frames[10].hand)
        XCTAssertEqual(frames[7].d.fired, "fist")

        // Replaying the decoded hands reproduces the fire at the same frame.
        let p2 = Pipeline(config: config)
        let refired = frames.compactMap { f in p2.process(f.hand?.hand, at: f.t).fired.map { (f.t, $0) } }
        XCTAssertEqual(refired.count, 1)
        XCTAssertEqual(refired.first?.1, .fist)
        XCTAssertEqual(refired.first?.0 ?? -1, frames[7].t, accuracy: 0.0001)
        XCTAssertEqual(frames[3].hand?.hand.points.count, fist.points.count)
        try? FileManager.default.removeItem(at: dir)
    }
}
