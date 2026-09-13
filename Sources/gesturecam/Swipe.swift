import Foundation

/// Detects fast horizontal palm motion. Directions are in the user's frame
/// (camera frames are not mirrored, so user-right is image-left).
struct SwipeDetector {
    var minDistance: CGFloat = 0.25      // fraction of frame width
    var window: TimeInterval = 0.5       // seconds the motion may take
    var maxVerticalRatio: CGFloat = 0.6  // |dy| must stay below this * |dx|

    private var samples: [(t: TimeInterval, p: CGPoint)] = []
    private var suppressUntil: TimeInterval = 0

    /// Feed the palm center each frame; returns a swipe on the frame it completes.
    mutating func push(_ p: CGPoint, at t: TimeInterval) -> Gesture? {
        samples.append((t, p))
        samples.removeAll { t - $0.t > window }
        guard t >= suppressUntil, let first = samples.first else { return nil }
        let dx = p.x - first.p.x, dy = p.y - first.p.y
        guard abs(dx) >= minDistance, abs(dy) <= abs(dx) * maxVerticalRatio else { return nil }
        samples.removeAll()
        suppressUntil = t + window
        return dx < 0 ? .swipeRight : .swipeLeft
    }

    /// Speed over the most recent ~150ms, in frame widths per second. Used to gate static gestures.
    func recentSpeed(at t: TimeInterval) -> CGFloat {
        guard let last = samples.last,
              let ref = samples.last(where: { t - $0.t >= 0.15 }) ?? samples.first,
              last.t > ref.t else { return 0 }
        return hypot(last.p.x - ref.p.x, last.p.y - ref.p.y) / CGFloat(last.t - ref.t)
    }

    mutating func reset() { samples.removeAll() }
}
