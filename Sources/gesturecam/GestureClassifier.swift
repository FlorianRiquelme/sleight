import Foundation
import Vision

enum Gesture: String, CaseIterable {
    case openPalm, fist, twoFingers, thumbsUp
    case swipeLeft, swipeRight   // dynamic, produced by SwipeDetector
}

/// Everything the classifier derived from one hand, for the debug view.
struct HandFeatures {
    var index, middle, ring, little: Bool
    var thumbStraight, thumbClear, thumbUp: Bool
    var thumb: Bool { thumbStraight && thumbClear }
    var extendedCount: Int { [index, middle, ring, little].filter { $0 }.count }
    var gesture: Gesture?
}

/// Rule-based static pose classifier on Vision hand landmarks.
/// All distances are normalized by hand size (wrist → middle MCP) for scale invariance.
struct GestureClassifier {
    func classify(_ hand: Hand) -> Gesture? { features(hand)?.gesture }

    func features(_ hand: Hand) -> HandFeatures? {
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
        var f = HandFeatures(index: index, middle: middle, ring: ring, little: little,
                             thumbStraight: thumbStraight, thumbClear: thumbClear,
                             thumbUp: thumbTip.y > indexMCP.y + 0.3 * size)
        let n = f.extendedCount
        // Open palm ignores the thumb: a relaxed palm keeps it alongside the index (measured
        // 0.26–0.47 hand-widths from the index MCP, same range as a fist), so it carries no signal.
        if n == 4 { f.gesture = .openPalm }
        else if n == 0 && !f.thumb { f.gesture = .fist }
        else if index && middle && !ring && !little { f.gesture = .twoFingers }
        else if n == 0 && f.thumb && f.thumbUp { f.gesture = .thumbsUp }
        return f
    }

    private func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}

/// Emits a gesture only after it has been seen for `holdFrames` consecutive frames.
struct GestureStabilizer {
    let holdFrames: Int
    private(set) var candidate: Gesture?
    private(set) var count = 0
    private(set) var current: Gesture?

    init(holdFrames: Int = 6) { self.holdFrames = holdFrames }

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
