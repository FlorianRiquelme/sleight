import XCTest
import Vision
@testable import sleight

final class FrameBufferTests: XCTestCase {
    func testSavesOnlyTheLast20Seconds() throws {
        let hand = Hand(chirality: .right, points: [
            sleight.Joint.wrist: CGPoint(x: 0.5, y: 0.5),
            sleight.Joint.indexMCP: CGPoint(x: 0.5, y: 0.5),
            sleight.Joint.middleMCP: CGPoint(x: 0.5, y: 0.5),
        ], confidence: 1)
        let result = Pipeline.Result(fired: nil, features: nil, gated: false, speed: 0, trail: [], candidate: nil, holdCount: 0, drag: nil, dropped: false)

        let buffer = FrameBuffer(seconds: 20)
        let ts = (0..<900).map { Double($0) / 30 }
        for t in ts { buffer.append(hand: hand, at: t, result: result) }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("frame-buffer-test-\(UUID()).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        let n = try buffer.save(to: url, label: "none", camera: "test", config: .default)

        let expected = ts.filter { $0 >= ts.last! - 20 }.count
        XCTAssertEqual(n, expected)

        let (header, frames) = try Recording.load(url)
        XCTAssertEqual(header?.label, "none")
        XCTAssertEqual(frames.count, expected)
        XCTAssertEqual(frames.first?.t ?? -1, 0, accuracy: 1e-6)
        XCTAssertEqual(frames.last?.t ?? -1, 20, accuracy: 0.05)
        XCTAssertTrue(frames.allSatisfy { $0.label == "none" })
    }
}
