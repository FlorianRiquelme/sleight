import Foundation
import Vision

enum Gesture: String, CaseIterable {
    case openPalm, fist, twoFingers, thumbsUp
    case swipeLeft, swipeRight   // dynamic, produced by SwipeDetector
}

/// Everything the classifier derived from one hand, for the debug view.
struct HandFeatures {
    var index, middle, ring, little: Bool
    var curled: Int              // fingers folded back past their PIP (see `GestureClassifier.curlRatio`)
    var tipReach: CGFloat        // farthest fingertip from the wrist, in palm lengths
    var thumbStraight, thumbClear, thumbUp: Bool
    var extent: CGFloat          // landmark bounding-box diagonal, fraction of frame
    var tooSmall: Bool           // open-hand pose rejected because the hand is too far/foreshortened
    var thumb: Bool { thumbStraight && thumbClear }
    var extendedCount: Int { [index, middle, ring, little].filter { $0 }.count }
    /// Enough fingers extended to count as an open hand; swipes only track open hands.
    var isOpen: Bool { extendedCount >= 3 }
    var gesture: Gesture?
}

/// Rule-based static pose classifier on Vision hand landmarks.
/// All distances are normalized by hand size (wrist → middle MCP) for scale invariance.
struct GestureClassifier {
    /// Open-finger poses (open palm, two fingers) need at least this hand extent. A hand resting on
    /// the desk is farther from the camera and foreshortened: fixtures show desk-life hands top out
    /// at 0.26, an open hand held up while talking at 0.29, deliberate open palms start at 0.33.
    var minOpenExtent: CGFloat = 0.30
    /// Closed poses (fist, thumbs up) need this much. A fist is compact, about 0.6 of an open
    /// palm's extent at the same distance: deliberate fists measure 0.19–0.25, a curled hand on
    /// the far side of the desk 0.12–0.14.
    var minClosedExtent: CGFloat = 0.16

    /// A finger is extended when its tip reaches past 1.15× its PIP distance from the wrist, and
    /// curled when it folds back inside 0.85×. In between is a relaxed finger: a hand on a mouse or
    /// keyboard is all relaxed fingers (idle fixture: ratios 0.84–1.15) and used to read as a fist,
    /// while every deliberate fist, thumbs up and two-fingers frame folds its closed fingers to
    /// 0.41–0.84. Closed poses therefore require curled fingers, not merely non-extended ones.
    static let extendRatio: CGFloat = 1.15
    static let curlRatio: CGFloat = 0.85

    /// A fist also keeps every fingertip inside the palm: within this many palm lengths of the
    /// wrist (fixture fists 0.61–0.71). Fingers hanging over a mouse or keyboard curl past their
    /// PIP too, but from beyond the knuckles (0.99–1.28). Thumbs up is exempt: the hand is turned
    /// edge-on, so its folded fingers project past the knuckles (1.05–1.43).
    static let fistTipReach: CGFloat = 0.9

    func classify(_ hand: Hand) -> Gesture? { features(hand)?.gesture }

    func features(_ hand: Hand) -> HandFeatures? {
        guard let wrist = hand[.wrist], let midMCP = hand[.middleMCP] else { return nil }
        let size = dist(wrist, midMCP)
        guard size > 0.01 else { return nil }

        // Tip distance from the wrist relative to the PIP's: >1.15 extended, <0.85 curled.
        func reach(tip: Joint, pip: Joint) -> CGFloat? {
            guard let t = hand[tip], let p = hand[pip] else { return nil }
            let d = dist(p, wrist)
            return d > 0 ? dist(t, wrist) / d : nil
        }
        guard let index = reach(tip: .indexTip, pip: .indexPIP),
              let middle = reach(tip: .middleTip, pip: .middlePIP),
              let ring = reach(tip: .ringTip, pip: .ringPIP),
              let little = reach(tip: .littleTip, pip: .littlePIP),
              let thumbTip = hand[.thumbTip], let thumbIP = hand[.thumbIP],
              let indexMCP = hand[.indexMCP]
        else { return nil }
        let reaches = [index, middle, ring, little]
        let ext = reaches.map { $0 > Self.extendRatio }
        let curl = reaches.map { $0 < Self.curlRatio }
        let tipReach = [Joint.indexTip, .middleTip, .ringTip, .littleTip]
            .compactMap { hand[$0] }.map { dist($0, wrist) / size }.max() ?? 0

        // Thumb: extended when straight and clear of the index knuckle (a tucked thumb sits on it).
        let thumbStraight = dist(thumbTip, wrist) > dist(thumbIP, wrist) * 1.1
        let thumbClear = dist(thumbTip, indexMCP) / size > 0.6
        var f = HandFeatures(index: ext[0], middle: ext[1], ring: ext[2], little: ext[3],
                             curled: curl.filter { $0 }.count, tipReach: tipReach,
                             thumbStraight: thumbStraight, thumbClear: thumbClear,
                             thumbUp: thumbTip.y > indexMCP.y + 0.3 * size,
                             extent: hand.extent, tooSmall: false)
        let n = f.extendedCount
        // Open palm ignores the thumb: a relaxed palm keeps it alongside the index (measured
        // 0.26–0.47 hand-widths from the index MCP, same range as a fist), so it carries no signal.
        if n == 4 { f.gesture = .openPalm }
        else if f.curled == 4 && !f.thumb && tipReach < Self.fistTipReach { f.gesture = .fist }
        else if ext[0] && ext[1] && curl[2] && curl[3] { f.gesture = .twoFingers }
        else if f.curled == 4 && f.thumb && f.thumbUp { f.gesture = .thumbsUp }

        if let g = f.gesture {
            let floor = (g == .openPalm || g == .twoFingers) ? minOpenExtent : minClosedExtent
            if f.extent < floor { f.tooSmall = true; f.gesture = nil }
        }
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

    /// Treat `g` as already fired: it will not fire again until the pose changes away from it.
    mutating func prime(_ g: Gesture?) {
        candidate = g; current = g; count = holdFrames
    }

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
