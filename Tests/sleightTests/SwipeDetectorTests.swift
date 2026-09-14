import XCTest
import Vision
@testable import sleight

final class SwipeDetectorTests: XCTestCase {
    /// Feeds a straight-line motion at 30fps; returns the first gesture emitted.
    private func run(dx: CGFloat, dy: CGFloat, seconds: TimeInterval) -> Gesture? {
        var d = SwipeDetector()
        let frames = Int(seconds * 30)
        for i in 0...frames {
            let f = CGFloat(i) / CGFloat(frames)
            if let g = d.push(CGPoint(x: 0.5 + dx * f, y: 0.5 + dy * f), at: TimeInterval(i) / 30) { return g }
        }
        return nil
    }

    func testUserRightwardMotionIsSwipeRight() {
        // Non-mirrored camera: user-right is image-left, so x decreases.
        XCTAssertEqual(run(dx: -0.3, dy: 0, seconds: 0.3), .swipeRight)
    }

    func testUserLeftwardMotionIsSwipeLeft() {
        XCTAssertEqual(run(dx: 0.3, dy: 0.05, seconds: 0.3), .swipeLeft)
    }

    func testSlowDriftDoesNotSwipe() {
        XCTAssertNil(run(dx: 0.3, dy: 0, seconds: 2.0))
    }

    func testDiagonalMotionDoesNotSwipe() {
        XCTAssertNil(run(dx: 0.3, dy: 0.3, seconds: 0.3))
    }

    func testSecondSwipeSuppressedWithinWindow() {
        var d = SwipeDetector()
        var fired: [Gesture] = []
        // Two fast back-and-forth swipes within 0.6s: only the first should fire.
        for i in 0...18 {
            let t = TimeInterval(i) / 30
            let x: CGFloat = i <= 9 ? 0.5 + 0.035 * CGFloat(i) : 0.815 - 0.035 * CGFloat(i - 9)
            if let g = d.push(CGPoint(x: x, y: 0.5), at: t) { fired.append(g) }
        }
        XCTAssertEqual(fired, [.swipeLeft])
    }

    func testReturnStrokeAfterASwipeIsIgnored() {
        var d = SwipeDetector()
        var fired: [Gesture] = []
        // Swipe toward the user's left, come back 1.0s later at the same speed, then swipe left
        // again 2.5s after the first: only the two leftward swipes count.
        func stroke(from x0: CGFloat, dx: CGFloat, at t0: TimeInterval) {
            for i in 0...9 { if let g = d.push(CGPoint(x: x0 + dx * CGFloat(i) / 9, y: 0.5), at: t0 + TimeInterval(i) / 30) { fired.append(g) } }
        }
        stroke(from: 0.3, dx: 0.3, at: 0)
        stroke(from: 0.6, dx: -0.3, at: 1.0)
        stroke(from: 0.3, dx: 0.3, at: 2.5)
        XCTAssertEqual(fired, [.swipeLeft, .swipeLeft])
        // Past the lockout the opposite direction is a deliberate swipe again.
        stroke(from: 0.6, dx: -0.3, at: 4.5)
        XCTAssertEqual(fired, [.swipeLeft, .swipeLeft, .swipeRight])
    }

    func testSwipeSurvivesDetectionDropouts() {
        // Vision loses the hand for several frames mid-swipe; samples must persist across the gap.
        var d = SwipeDetector()
        var fired: Gesture?
        for i in 0...9 where !(3...6).contains(i) {   // frames 3–6 missing
            if let g = d.push(CGPoint(x: 0.3 + 0.04 * CGFloat(i), y: 0.5), at: TimeInterval(i) / 30) { fired = g }
        }
        XCTAssertEqual(fired, .swipeLeft)
    }

    func testSwipeStartsFromAnOpenHand() {
        var d = SwipeDetector()
        var fired: Gesture?
        for i in 0...9 {
            // Closed while still, opens only for the last frames: nothing to measure from.
            if let g = d.push(CGPoint(x: 0.3 + 0.04 * CGFloat(i), y: 0.5), open: i >= 8, at: TimeInterval(i) / 30) { fired = g }
        }
        XCTAssertNil(fired)
    }

    func testTeleportRestartsTheBuffer() {
        // An open hand standing still, then a hand a quarter frame away on the next frame: not motion.
        var d = SwipeDetector()
        var fired: Gesture?
        for i in 0...20 {
            let x: CGFloat = i < 10 ? 0.3 : 0.6
            if let g = d.push(CGPoint(x: x, y: 0.5), at: TimeInterval(i) / 30) { fired = g }
        }
        XCTAssertNil(fired)
    }

    func testHandednessFlipWithAJumpIsAnotherHand() {
        // Vision flips handedness inside real swipes with steps of 0.03–0.05 frame widths, so a
        // flip alone is motion. A flip combined with a jump is the other hand: the resting hand
        // or a half-visible one on the far side of the frame (dogfood fixtures: 0.26–0.39).
        func run(jump: CGFloat, back: VNChirality) -> Gesture? {
            var d = SwipeDetector()
            var fired: Gesture?
            for i in 0...12 {
                let side: VNChirality = i < 6 ? .left : back
                let x = 0.3 + 0.03 * CGFloat(i) + (i >= 6 ? jump : 0)
                if let g = d.push(CGPoint(x: x, y: 0.5), side: side, at: TimeInterval(i) / 30) { fired = g }
            }
            return fired
        }
        XCTAssertEqual(run(jump: 0, back: .right), .swipeLeft, "a flip without a jump is the same hand mid-swipe")
        XCTAssertEqual(run(jump: 0.17, back: .left), .swipeLeft, "a jump alone under maxStepSpeed is still motion")
        XCTAssertNil(run(jump: 0.17, back: .right), "a flip with a jump is another hand")
    }

    func testRecentSpeedReflectsMotion() {
        var d = SwipeDetector()
        for i in 0..<10 { _ = d.push(CGPoint(x: 0.5, y: 0.5), at: TimeInterval(i) / 30) }
        XCTAssertEqual(d.recentSpeed(at: 9.0 / 30), 0, accuracy: 0.001)
        for i in 10..<20 { _ = d.push(CGPoint(x: 0.5 + 0.02 * CGFloat(i - 9), y: 0.5), at: TimeInterval(i) / 30) }
        XCTAssertGreaterThan(d.recentSpeed(at: 19.0 / 30), 0.4)
    }
}
