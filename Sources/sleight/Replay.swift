import Foundation

/// Runs a recording through a fresh Pipeline and reports what fires, compared to the label if any.
enum Replay {
    struct Fire { let t: Double; let gesture: Gesture; let label: String?; let firedAtRecordTime: String? }

    static func run(file: URL, config: Config, verbose: Bool) throws -> Int32 {
        let (header, frames) = try Recording.load(file)
        let pipeline = Pipeline(config: config)
        var fires: [Fire] = []
        var handFrames = 0

        for f in frames {
            let hand = f.hand?.hand
            if hand != nil { handFrames += 1 }
            let r = pipeline.process(hand, at: f.t)
            if verbose, let ft = r.features {
                print(String(format: "%7.3f  pose=%-10@ I%d M%d R%d L%d curl=%d tips=%.2f T%d(s%d c%d u%d) ext=%.2f span=%.2f%@ hold=%d/%d speed=%.2f%@",
                             f.t, ft.gesture?.rawValue ?? "-", ft.index ? 1 : 0, ft.middle ? 1 : 0, ft.ring ? 1 : 0, ft.little ? 1 : 0, ft.curled, Double(ft.tipReach),
                             ft.thumb ? 1 : 0, ft.thumbStraight ? 1 : 0, ft.thumbClear ? 1 : 0, ft.thumbUp ? 1 : 0,
                             Double(ft.extent), Double(ft.span), ft.tooSmall ? " SMALL" : ft.angled ? " ANGLED" : "",
                             r.holdCount, pipeline.holdFrames, Double(r.speed), r.gated ? " GATED" : ""))
            }
            if let g = r.fired {
                fires.append(Fire(t: f.t, gesture: g, label: f.label, firedAtRecordTime: f.d.fired))
            }
        }

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
