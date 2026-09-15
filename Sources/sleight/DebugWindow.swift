import AppKit
import Vision

/// Mirrored camera preview with the hand skeleton, finger states, stabilizer progress and swipe trail.
final class DebugWindowController: NSWindowController, NSWindowDelegate {
    private let engine: Engine
    private let view = DebugView()

    init(engine: Engine) {
        self.engine = engine
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                         styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        w.title = "sleight debug"
        w.contentAspectRatio = NSSize(width: 4, height: 3)
        w.contentView = view
        w.isReleasedWhenClosed = false
        w.center()
        super.init(window: w)
        w.delegate = self
    }
    required init?(coder: NSCoder) { fatalError() }

    func show() {
        engine.onDebug = { [weak self] f in
            DispatchQueue.main.async { self?.view.frameData = f }
        }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        engine.onDebug = nil   // stop paying for CGImage conversion when nobody is looking
    }
}

final class DebugView: NSView {
    var frameData: DebugFrame? { didSet { needsDisplay = true } }

    private static let chains: [(finger: String, joints: [Joint])] = [
        ("thumb", [.wrist, .thumbCMC, .thumbMP, .thumbIP, .thumbTip]),
        ("index", [.wrist, .indexMCP, .indexPIP, .indexDIP, .indexTip]),
        ("middle", [.wrist, .middleMCP, .middlePIP, .middleDIP, .middleTip]),
        ("ring", [.wrist, .ringMCP, .ringPIP, .ringDIP, .ringTip]),
        ("little", [.wrist, .littleMCP, .littlePIP, .littleDIP, .littleTip]),
    ]
    private let hudFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill(); bounds.fill()
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        guard let f = frameData else {
            drawHUD(["waiting for frames…"]); return
        }

        // Aspect-fit the 4:3 image, mirrored so it behaves like a mirror.
        let img = imageRect(for: f.image)
        if let cg = f.image {
            ctx.saveGState()
            ctx.translateBy(x: img.maxX, y: img.minY)
            ctx.scaleBy(x: -1, y: 1)
            ctx.draw(cg, in: CGRect(origin: .zero, size: img.size))
            ctx.restoreGState()
        }
        func P(_ p: CGPoint) -> CGPoint { CGPoint(x: img.minX + (1 - p.x) * img.width, y: img.minY + p.y * img.height) }

        // Swipe trail (oldest → newest), fading in.
        if f.trail.count > 1 {
            for i in 1..<f.trail.count {
                let a = CGFloat(i) / CGFloat(f.trail.count)
                let path = NSBezierPath(); path.lineWidth = 3
                path.move(to: P(f.trail[i - 1])); path.line(to: P(f.trail[i]))
                NSColor.cyan.withAlphaComponent(0.2 + 0.8 * a).setStroke(); path.stroke()
            }
        }

        // Skeleton, colored by finger state.
        if let hand = f.hand {
            for chain in Self.chains {
                let color = fingerColor(chain.finger, f.features, gated: f.gated)
                color.setStroke(); color.setFill()
                let pts = chain.joints.compactMap { hand[$0] }.map(P)
                let path = NSBezierPath(); path.lineWidth = 3
                for (i, p) in pts.enumerated() { i == 0 ? path.move(to: p) : path.line(to: p) }
                path.stroke()
                for p in pts { NSBezierPath(ovalIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)).fill() }
            }
            if let c = hand.palmCenter {
                let p = P(c)
                NSColor.systemBlue.setFill()
                NSBezierPath(ovalIn: CGRect(x: p.x - 7, y: p.y - 7, width: 14, height: 14)).fill()
            }
        }

        drawHUD(hudLines(f))
    }

    private func imageRect(for cg: CGImage?) -> CGRect {
        let ar = cg.map { CGFloat($0.width) / CGFloat($0.height) } ?? 4.0 / 3.0
        var r = bounds
        if r.width / r.height > ar { r.size.width = r.height * ar; r.origin.x = (bounds.width - r.width) / 2 }
        else { r.size.height = r.width / ar; r.origin.y = (bounds.height - r.height) / 2 }
        return r
    }

    private func fingerColor(_ finger: String, _ f: HandFeatures?, gated: Bool) -> NSColor {
        guard let f else { return gated ? .systemYellow : .lightGray }
        let ext: Bool
        switch finger {
        case "thumb": ext = f.thumb
        case "index": ext = f.index
        case "middle": ext = f.middle
        case "ring": ext = f.ring
        default: ext = f.little
        }
        return ext ? .systemGreen : .systemRed
    }

    private func hudLines(_ f: DebugFrame) -> [String] {
        func mark(_ b: Bool) -> String { b ? "✓" : "✗" }
        var lines: [String] = []
        if f.hand == nil {
            lines.append("no hand")
        } else if f.gated {
            lines.append("moving — static gestures gated")
        } else if let ft = f.features {
            let why = ft.tooSmall ? "  TOO SMALL (open ≥ \(f.minOpenExtent), closed ≥ \(f.minClosedExtent))"
                : ft.angled ? "  ANGLED (span ≤ \(GestureClassifier.maxPalmSpan))" : ""
            lines.append(String(format: "pose:   %@   extent %.2f   span %.2f%@", ft.gesture?.rawValue ?? "—", ft.extent, ft.span, why))
            lines.append("finger: I\(mark(ft.index)) M\(mark(ft.middle)) R\(mark(ft.ring)) L\(mark(ft.little))   thumb \(mark(ft.thumb)) (straight \(mark(ft.thumbStraight)) clear \(mark(ft.thumbClear)) up \(mark(ft.thumbUp)))")
        } else {
            lines.append("pose:   landmarks incomplete (\(f.hand!.points.count)/21)")
        }
        let filled = min(f.holdCount, f.holdFrames)
        let bar = String(repeating: "█", count: filled) + String(repeating: "░", count: max(0, f.holdFrames - filled))
        lines.append("hold:   \(bar) \(filled)/\(f.holdFrames) \(f.candidate?.rawValue ?? "")")

        var swipe = ""
        if let a = f.trail.first, let b = f.trail.last {
            let dx = b.x - a.x
            let frac = min(1, abs(dx) / f.swipeMinDistance)
            let n = Int(frac * 10)
            let dir = dx < 0 ? "→" : (dx > 0 ? "←" : " ")   // user's direction (mirrored)
            swipe = " \(dir) " + String(repeating: "▮", count: n) + String(repeating: "▯", count: 10 - n)
        }
        lines.append(String(format: "speed:  %.2f / still %.2f%@", f.speed, f.stillSpeed, swipe))

        if let d = f.drag {
            lines.append(String(format: "grab:   dx %+.2f  dy %+.2f   open the hand to drop", d.x, d.y))
        }
        var status = "fps:    \(f.fps)"
        if let last = f.lastFired {
            status += String(format: "   fired %@ %.1fs ago", last.gesture.rawValue, Date().timeIntervalSince(last.at))
        }
        lines.append(status)
        return lines
    }

    private func drawHUD(_ lines: [String]) {
        let attrs: [NSAttributedString.Key: Any] = [.font: hudFont, .foregroundColor: NSColor.white]
        let lineH: CGFloat = 18
        let pad: CGFloat = 8
        let widest = lines.map { ($0 as NSString).size(withAttributes: attrs).width }.max() ?? 0
        let box = CGRect(x: 10, y: bounds.height - 10 - (lineH * CGFloat(lines.count) + pad * 2),
                         width: widest + pad * 2, height: lineH * CGFloat(lines.count) + pad * 2)
        NSColor.black.withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6).fill()
        for (i, line) in lines.enumerated() {
            let y = box.maxY - pad - lineH * CGFloat(i + 1) + 3
            (line as NSString).draw(at: CGPoint(x: box.minX + pad, y: y), withAttributes: attrs)
        }
    }
}
