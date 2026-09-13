import Foundation
import Vision

/// Detects fast horizontal motion of an open hand. Directions are in the user's frame
/// (camera frames are not mirrored, so user-right is image-left).
/// Samples age out by time only: Vision drops the hand for a few frames during brisk motion,
/// and resetting on each dropout is why swipes never accumulated distance.
///
/// Two guards come from the idle fixture. Vision tracks a single hand, and with both hands on
/// the desk it alternates between them, so the palm center teleports. A swipe therefore runs
/// from the oldest sample with spread fingers in the window (real swipes wind up open and lose
/// finger joints only in the fast phase; the hands on the desk are closed or half out of frame),
/// and the buffer restarts on a step faster than any hand moves, or when the hand comes back from
/// a detection gap with the other handedness (Vision flips handedness frame to frame during brisk
/// motion, but only a different hand comes back flipped after a gap). Speed still uses every
/// sample, so a closed hand in motion gates the static poses.
struct SwipeDetector {
    var minDistance: CGFloat = 0.25      // fraction of frame width
    var window: TimeInterval = 0.5       // seconds the motion may take
    var maxVerticalRatio: CGFloat = 0.7  // |dy| must stay below this * |dx|; fixtures show real swipes arc up to ~0.5
    var maxStepSpeed: CGFloat = 6        // frame widths/s between consecutive samples; fixture swipes peak at 4.7,
                                         // a switch to the other hand shows as 6.5–9.2
    var gap: TimeInterval = 0.1          // a handedness flip across a longer detection gap is the other hand
    var returnLockout: TimeInterval = 1.5 // seconds after a swipe during which the opposite direction is the
                                         // hand coming back (fixture returns fire 1.0s after the swipe)

    private var samples: [(t: TimeInterval, p: CGPoint, open: Bool, side: VNChirality)] = []
    private var suppressUntil: TimeInterval = 0
    private var lastSwipe: (t: TimeInterval, g: Gesture)?
    /// True when the last `push` discarded the buffer because the hand jumped or changed.
    private(set) var restarted = false

    /// Feed the palm center each frame; returns a swipe on the frame it completes.
    /// `open`: the hand has at least three fingers extended. `side`: Vision's handedness.
    mutating func push(_ p: CGPoint, open: Bool = true, side: VNChirality = .unknown, at t: TimeInterval) -> Gesture? {
        if let last = samples.last, t > last.t {
            let teleport = hypot(p.x - last.p.x, p.y - last.p.y) / CGFloat(t - last.t) > maxStepSpeed
            let switched = side != last.side && side != .unknown && last.side != .unknown && t - last.t > gap
            restarted = teleport || switched   // not motion: a different hand
            if restarted { samples.removeAll() }
        }
        samples.append((t, p, open, side))
        samples.removeAll { t - $0.t > window }
        guard t >= suppressUntil, let first = samples.first(where: \.open) else { return nil }
        let dx = p.x - first.p.x, dy = p.y - first.p.y
        guard abs(dx) >= minDistance, abs(dy) <= abs(dx) * maxVerticalRatio else { return nil }
        samples.removeAll()
        suppressUntil = t + window
        let g: Gesture = dx < 0 ? .swipeRight : .swipeLeft
        if let last = lastSwipe, g != last.g, t - last.t < returnLockout { return nil }
        lastSwipe = (t, g)
        return g
    }

    /// Speed over the most recent ~150ms, in frame widths per second. Used to gate static gestures.
    func recentSpeed(at t: TimeInterval) -> CGFloat {
        guard let last = samples.last,
              let ref = samples.last(where: { t - $0.t >= 0.15 }) ?? samples.first,
              last.t > ref.t else { return 0 }
        return hypot(last.p.x - ref.p.x, last.p.y - ref.p.y) / CGFloat(last.t - ref.t)
    }

    mutating func reset() { samples.removeAll(); restarted = false; lastSwipe = nil }

    var trail: [CGPoint] { samples.map(\.p) }
}
