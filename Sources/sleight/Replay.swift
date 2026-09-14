import Foundation

/// Runs a recording through a fresh Pipeline and reports what fires, compared to the label if any.
enum Replay {
    struct Fire { let t: Double; let gesture: Gesture; let label: String?; let firedAtRecordTime: String? }

    /// `csv` writes one row per frame of what the *current* pipeline derives, and nothing else,
    /// so `replay f.jsonl --csv > f.csv` is the input for any offline measurement across fixtures.
    /// The `d` fields inside a recording are what fired at record time under that day's config;
    /// they go stale with every threshold change, this does not.
    static func run(file: URL, config: Config, verbose: Bool, csv: Bool = false) throws -> Int32 {
        let (header, frames) = try Recording.load(file)
        let pipeline = Pipeline(config: config)
        var fires: [Fire] = []
        var handFrames = 0

        if csv { print("t,hand,pose,gated,speed,palm,extent,span,tips,upright,hold,candidate,fired") }
        for f in frames {
            let hand = f.hand?.hand
            if hand != nil { handFrames += 1 }
            let r = pipeline.process(hand, at: f.t)
            if csv {
                let ft = r.features ?? hand.flatMap(pipeline.features)
                func n(_ v: CGFloat?) -> String { v.map { String(format: "%.4f", Double($0)) } ?? "" }
                print([String(format: "%.4f", f.t), hand == nil ? "0" : "1", r.features?.gesture?.rawValue ?? "",
                       r.gated ? "1" : "0", String(format: "%.4f", Double(r.speed)), n(ft?.palm), n(ft?.extent), n(ft?.span),
                       n(ft?.tipReach), n(ft?.upright), "\(r.holdCount)", r.candidate?.rawValue ?? "", r.fired?.rawValue ?? ""].joined(separator: ","))
            } else if verbose, let ft = r.features {
                print(String(format: "%7.3f  pose=%-10@ I%d M%d R%d L%d curl=%d tips=%.2f T%d(s%d c%d u%d) ext=%.2f palm=%.2f span=%.2f up=%.2f%@ hold=%d/%d speed=%.2f%@",
                             f.t, ft.gesture?.rawValue ?? "-", ft.index ? 1 : 0, ft.middle ? 1 : 0, ft.ring ? 1 : 0, ft.little ? 1 : 0, ft.curled, Double(ft.tipReach),
                             ft.thumb ? 1 : 0, ft.thumbStraight ? 1 : 0, ft.thumbClear ? 1 : 0, ft.thumbUp ? 1 : 0,
                             Double(ft.extent), Double(ft.palm), Double(ft.span), Double(ft.upright), ft.tooSmall ? " SMALL" : ft.angled ? " ANGLED" : "",
                             r.holdCount, pipeline.holdFrames, Double(r.speed), r.gated ? " GATED" : ""))
            }
            if let g = r.fired {
                fires.append(Fire(t: f.t, gesture: g, label: f.label, firedAtRecordTime: f.d.fired))
            }
        }
        if csv { return 0 }

        // Fires that happened at record time but not in this replay (config drift).
        let recordedFires = frames.filter { $0.d.fired != nil }
        let recordedSet = Set(recordedFires.map { "\($0.t)" })
        let replaySet = Set(fires.map { "\($0.t)" })

        print("recording: \(file.lastPathComponent)")
        if let h = header {
            print("camera: \(h.camera)   recorded: \(h.recorded)   label: \(h.label ?? "—")")
        }
        print("frames: \(frames.count)   with hand: \(handFrames)   duration: \(String(format: "%.1fs", frames.last?.t ?? 0))")
        print("")
        print("fires in replay (current config):")
        if fires.isEmpty { print("  none") }
        for f in fires {
            var mark = ""
            if let l = f.label { mark = l == f.gesture.rawValue ? "  ✓" : (l == "none" ? "  ✗ (nothing expected)" : "  ✗ (label \(l))") }
            let new = recordedSet.contains("\(f.t)") ? "" : "  [new vs. recording]"
            print(String(format: "  %7.3f  %@%@%@", f.t, f.gesture.rawValue, mark, new))
        }
        let lost = recordedFires.filter { !replaySet.contains("\($0.t)") }
        if !lost.isEmpty {
            print("fires at record time that no longer fire:")
            for f in lost { print(String(format: "  %7.3f  %@", f.t, f.d.fired!)) }
        }

        if let label = header?.label ?? frames.first?.label {
            if label == "none" {
                print("")
                print("label none: \(fires.count) fires (expected 0)")
                return fires.isEmpty ? 0 : 1
            }
            let correct = fires.filter { $0.gesture.rawValue == label }.count
            let wrong = fires.count - correct
            print("")
            print("label \(label): \(correct) correct, \(wrong) wrong")
            return wrong == 0 && correct > 0 ? 0 : 1
        }
        return 0
    }
}
