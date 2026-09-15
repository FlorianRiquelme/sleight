import XCTest
import Vision
@testable import sleight

final class GrabTests: XCTestCase {
    /// Same synthetic hand builder as PipelineTests; kept local so this file has no dependency on
    /// test execution order.
    enum Closed { case curled, relaxed, hanging }

    private func hand(index: Bool, middle: Bool, ring: Bool, little: Bool, thumbOut: Bool, thumbUp: Bool = false, offset: CGFloat = 0, closed: Closed = .curled) -> Hand {
        var p: [sleight.Joint: CGPoint] = [:]
        let wrist = CGPoint(x: 0.5 + offset, y: 0.3)
        p[.wrist] = wrist
        let fingers: [(sleight.Joint, sleight.Joint, sleight.Joint, sleight.Joint, CGFloat, Bool)] = [
            (.indexMCP, .indexPIP, .indexDIP, .indexTip, -0.035, index),
            (.middleMCP, .middlePIP, .middleDIP, .middleTip, -0.012, middle),
            (.ringMCP, .ringPIP, .ringDIP, .ringTip, 0.012, ring),
            (.littleMCP, .littlePIP, .littleDIP, .littleTip, 0.035, little),
        ]
        for (mcp, pip, dip, tip, dx, ext) in fingers {
            let x = wrist.x + dx
            p[mcp] = CGPoint(x: x, y: 0.45)
            let (py, dy, ty): (CGFloat, CGFloat, CGFloat)
            switch (ext, closed) {
            case (true, _): (py, dy, ty) = (0.52, 0.56, 0.59)
            case (false, .curled): (py, dy, ty) = (0.50, 0.46, 0.40)
            case (false, .relaxed): (py, dy, ty) = (0.50, 0.51, 0.50)
            case (false, .hanging): (py, dy, ty) = (0.56, 0.53, 0.48)
            }
            p[pip] = CGPoint(x: x, y: py)
            p[dip] = CGPoint(x: x, y: dy)
            p[tip] = CGPoint(x: x, y: ty)
        }
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

    private func fist(offset: CGFloat = 0) -> Hand {
        hand(index: false, middle: false, ring: false, little: false, thumbOut: false, offset: offset, closed: .curled)
    }

    private func openPalm(offset: CGFloat = 0) -> Hand {
        hand(index: true, middle: true, ring: true, little: true, thumbOut: true, offset: offset)
    }

    private var config: Config { .default }

    func testStillFistFiresThenDragsAndOpenHandDrops() {
        let p = Pipeline(config: config)
        var lastResult: Pipeline.Result!
        for i in 0..<config.holdFrames {
            lastResult = p.process(fist(), at: Double(i) / 30)
        }
        XCTAssertEqual(lastResult.fired, .fist)
        XCTAssertEqual(lastResult.drag, .zero)

        var lastOffset: CGFloat = 0
        for i in 0..<10 {
            lastOffset = CGFloat(i + 1) * 0.02
            let t = Double(config.holdFrames + i) / 30
            let r = p.process(fist(offset: lastOffset), at: t)
            XCTAssertNotNil(r.drag)
            XCTAssertNil(r.fired)
        }
        let dragged = p.process(fist(offset: lastOffset), at: Double(config.holdFrames + 10) / 30)
        XCTAssertEqual(dragged.drag?.x ?? 0, -0.2, accuracy: 1e-3)
        XCTAssertEqual(dragged.drag?.y ?? 0, 0, accuracy: 1e-3)

        let dropFrame = p.process(openPalm(offset: lastOffset), at: Double(config.holdFrames + 11) / 30)
        XCTAssertTrue(dropFrame.dropped)
        XCTAssertEqual(dropFrame.drag?.x ?? 0, -0.2, accuracy: 1e-3)

        var fired: [Gesture] = []
        for i in 0..<(2 * config.holdFrames) {
            let t = Double(config.holdFrames + 12 + i) / 30
            if let g = p.process(openPalm(offset: lastOffset), at: t).fired { fired.append(g) }
        }
        XCTAssertEqual(fired, [])
    }

    /// A hand that disappears mid-drag ends the grab with zero travel: the fist fixtures end by
    /// lowering the hand out of frame, and that must restore the window, not move it.
    func testHandLostDuringDragCancelsAfterTimeout() {
        let p = Pipeline(config: config)
        for i in 0..<config.holdFrames {
            _ = p.process(fist(), at: Double(i) / 30)
        }
        var t = Double(config.holdFrames) / 30
        for i in 0..<3 {
            t = Double(config.holdFrames + i) / 30
            _ = p.process(fist(offset: CGFloat(i + 1) * 0.02), at: t)
        }
        let lostStart = t
        var i = 1
        var droppedAt: Double?
        while true {
            let frameT = lostStart + Double(i) / 30
            let r = p.process(nil, at: frameT)
            if frameT - lostStart <= Pipeline.grabLostSeconds {
                XCTAssertFalse(r.dropped)
                XCTAssertEqual(r.drag?.x ?? 0, -0.06, accuracy: 1e-6)   // holds the last position meanwhile
            } else {
                XCTAssertTrue(r.dropped)
                XCTAssertEqual(r.drag, .zero)
                droppedAt = frameT
                break
            }
            i += 1
        }
        XCTAssertNotNil(droppedAt)
    }

    func testFastFistMotionWhileDraggingNeverSwipes() {
        let p = Pipeline(config: config)
        for i in 0..<config.holdFrames {
            _ = p.process(fist(), at: Double(i) / 30)
        }
        var fired: [Gesture] = []
        for i in 0..<12 {
            let t = Double(config.holdFrames + i) / 30
            let r = p.process(fist(offset: CGFloat(i + 1) * 0.05), at: t)
            if let g = r.fired { fired.append(g) }
            XCTAssertNotNil(r.drag)
        }
        XCTAssertEqual(fired, [])
    }

    func testNoDragWhenFistIsNotMappedToWindow() {
        var c = Config.default
        c.mappings["fist"] = .media("mute")
        let p = Pipeline(config: c)
        var lastResult: Pipeline.Result!
        for i in 0..<c.holdFrames {
            lastResult = p.process(fist(), at: Double(i) / 30)
        }
        XCTAssertEqual(lastResult.fired, .fist)

        var lastGated = false
        for i in 0..<10 {
            let t = Double(c.holdFrames + i) / 30
            let r = p.process(fist(offset: CGFloat(i + 1) * 0.02), at: t)
            XCTAssertNil(r.drag)
            lastGated = r.gated
        }
        XCTAssertTrue(lastGated, "sustained motion should gate a static gesture once speed catches up")
    }

    func testConfigGrabGesture() {
        XCTAssertEqual(Config.default.grabGesture, .fist)

        var muted = Config.default
        muted.mappings["fist"] = .media("mute")
        XCTAssertNil(muted.grabGesture)

        let json = """
        {"mappings":{"fist":{"type":"none"},"twoFingers":{"type":"window"}}}
        """.data(using: .utf8)!
        let decoded = try! JSONDecoder().decode(Config.self, from: json)
        XCTAssertEqual(decoded.grabGesture, .twoFingers)
    }
}
