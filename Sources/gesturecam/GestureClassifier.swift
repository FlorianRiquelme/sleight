import Foundation
import Vision

enum Gesture: String, CaseIterable {
    case openPalm, fist, twoFingers, thumbsUp
}

/// Rule-based static pose classifier on Vision hand landmarks.
/// All distances are normalized by hand size (wrist → middle MCP) for scale invariance.
struct GestureClassifier {
    func classify(_ hand: Hand) -> Gesture? {
        guard let wrist = hand[.wrist], let midMCP = hand[.middleMCP] else { return nil }
        let size = dist(wrist, midMCP)
        guard size > 0.01 else { return nil }

        // A finger is extended when its tip is farther from the wrist than its PIP joint.
        func extended(tip: Joint, pip: Joint) -> Bool? {
            guard let t = hand[tip], let p = hand[pip] else { return nil }
            return dist(t, wrist) > dist(p, wrist) * 1.15
        }
        guard let index = extended(tip: .indexTip, pip: .indexPIP),
              let middle = extended(tip: .middleTip, pip: .middlePIP),
              let ring = extended(tip: .ringTip, pip: .ringPIP),
              let little = extended(tip: .littleTip, pip: .littlePIP),
              let thumbTip = hand[.thumbTip], let thumbIP = hand[.thumbIP],
              let indexMCP = hand[.indexMCP]
        else { return nil }

        // Thumb: extended when straight and clear of the index knuckle (a tucked thumb sits on it).
        let thumbStraight = dist(thumbTip, wrist) > dist(thumbIP, wrist) * 1.1
        let thumbClear = dist(thumbTip, indexMCP) / size > 0.6
        let thumb = thumbStraight && thumbClear

        let fingers = [index, middle, ring, little]
        let extendedCount = fingers.filter { $0 }.count

        if extendedCount == 4 && thumb { return .openPalm }
        if extendedCount == 0 && !thumb { return .fist }
        if index && middle && !ring && !little { return .twoFingers }
        if extendedCount == 0 && thumb && thumbTip.y > indexMCP.y + 0.3 * size { return .thumbsUp }
        return nil
    }

    private func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}

/// Emits a gesture only after it has been seen for `holdFrames` consecutive frames.
struct GestureStabilizer {
    var holdFrames = 6
    private var candidate: Gesture?
    private var count = 0
    private(set) var current: Gesture?

    /// Returns the newly stabilized gesture on the frame it becomes stable, else nil.
    mutating func push(_ g: Gesture?) -> Gesture? {
        if g == candidate { count += 1 } else { candidate = g; count = 1 }
        if count >= holdFrames && candidate != current {
            current = candidate
            return current
        }
        return nil
    }
}
