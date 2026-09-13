import XCTest
@testable import gesturecam

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

    func testSwipeSurvivesDetectionDropouts() {
        // Vision loses the hand for several frames mid-swipe; samples must persist across the gap.
        var d = SwipeDetector()
        var fired: Gesture?
        for i in 0...9 where !(3...6).contains(i) {   // frames 3–6 missing
            if let g = d.push(CGPoint(x: 0.3 + 0.04 * CGFloat(i), y: 0.5), at: TimeInterval(i) / 30) { fired = g }
        }
        XCTAssertEqual(fired, .swipeLeft)
    }

    func testRecentSpeedReflectsMotion() {
        var d = SwipeDetector()
        for i in 0..<10 { _ = d.push(CGPoint(x: 0.5, y: 0.5), at: TimeInterval(i) / 30) }
        XCTAssertEqual(d.recentSpeed(at: 9.0 / 30), 0, accuracy: 0.001)
        for i in 10..<20 { _ = d.push(CGPoint(x: 0.5 + 0.02 * CGFloat(i - 9), y: 0.5), at: TimeInterval(i) / 30) }
        XCTAssertGreaterThan(d.recentSpeed(at: 19.0 / 30), 0.4)
    }
}
