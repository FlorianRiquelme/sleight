import XCTest
@testable import sleight

final class WindowZoneTests: XCTestCase {
    let visible = CGRect(x: 0, y: 25, width: 1200, height: 775)

    func testPickCellCenters() {
        let colWidth = visible.width / 3
        let rowHeight = visible.height / 3
        let expected: [[WindowZone]] = [
            [.topLeft, .top, .topRight],
            [.left, .fill, .right],
            [.bottomLeft, .bottom, .bottomRight]
        ]
        for row in 0..<3 {
            for col in 0..<3 {
                let center = CGPoint(
                    x: visible.minX + (CGFloat(col) + 0.5) * colWidth,
                    y: visible.minY + (CGFloat(row) + 0.5) * rowHeight
                )
                XCTAssertEqual(WindowZone.pick(center: center, in: visible), expected[row][col],
                                "row \(row) col \(col)")
            }
        }
    }

    func testPickClampsOutsidePoints() {
        XCTAssertEqual(WindowZone.pick(center: CGPoint(x: -50, y: -50), in: visible), .topLeft)
        XCTAssertEqual(WindowZone.pick(center: CGPoint(x: 2000, y: 2000), in: visible), .bottomRight)
    }

    func testFrameFill() {
        XCTAssertEqual(WindowZone.fill.frame(in: visible), visible)
    }

    func testFrameLeftHalf() {
        let f = WindowZone.left.frame(in: visible)
        XCTAssertEqual(f.origin.x, 0, accuracy: 1e-6)
        XCTAssertEqual(f.origin.y, 25, accuracy: 1e-6)
        XCTAssertEqual(f.width, 600, accuracy: 1e-6)
        XCTAssertEqual(f.height, 775, accuracy: 1e-6)
    }

    func testFrameTopHalf() {
        let f = WindowZone.top.frame(in: visible)
        XCTAssertEqual(f.origin.x, 0, accuracy: 1e-6)
        XCTAssertEqual(f.origin.y, 25, accuracy: 1e-6)
        XCTAssertEqual(f.width, 1200, accuracy: 1e-6)
        XCTAssertEqual(f.height, 387.5, accuracy: 1e-6)
    }

    func testFrameTopRightQuarter() {
        let f = WindowZone.topRight.frame(in: visible)
        XCTAssertEqual(f.origin.x, 600, accuracy: 1e-6)
        XCTAssertEqual(f.origin.y, 25, accuracy: 1e-6)
        XCTAssertEqual(f.width, 600, accuracy: 1e-6)
        XCTAssertEqual(f.height, 387.5, accuracy: 1e-6)
    }

    func testFrameBottomLeftQuarter() {
        let f = WindowZone.bottomLeft.frame(in: visible)
        XCTAssertEqual(f.origin.x, 0, accuracy: 1e-6)
        XCTAssertEqual(f.origin.y, 412.5, accuracy: 1e-6)
        XCTAssertEqual(f.width, 600, accuracy: 1e-6)
        XCTAssertEqual(f.height, 387.5, accuracy: 1e-6)
    }

    func testEveryZoneFrameIsContainedInVisible() {
        for zone in WindowZone.allCases {
            XCTAssertTrue(visible.contains(zone.frame(in: visible)), "\(zone) frame not contained")
        }
    }

    func testQuartersTileVisible() {
        let quarters: [WindowZone] = [.topLeft, .topRight, .bottomLeft, .bottomRight]
        let sum = quarters.reduce(0 as CGFloat) { $0 + $1.frame(in: visible).width * $1.frame(in: visible).height }
        XCTAssertEqual(sum, visible.width * visible.height, accuracy: 1e-6)
    }
}
