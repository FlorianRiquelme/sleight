import AppKit
import ApplicationServices

/// Snap targets on a 3×3 grid of a screen's visible frame, picked by where the window's center lands.
/// Defined in AX/y-down space: top = the half with the smaller y.
enum WindowZone: String, CaseIterable {
    case topLeft, top, topRight, left, fill, right, bottomLeft, bottom, bottomRight

    /// Zone whose grid cell contains `center`, both in the same coordinate space as `visible`.
    /// Column = thirds in x, row = thirds in y. Points outside `visible` clamp to the nearest cell.
    static func pick(center: CGPoint, in visible: CGRect) -> WindowZone {
        let colWidth = visible.width / 3
        let rowHeight = visible.height / 3
        let col = min(2, max(0, Int((center.x - visible.minX) / colWidth)))
        let row = min(2, max(0, Int((center.y - visible.minY) / rowHeight)))
        let grid: [[WindowZone]] = [
            [.topLeft, .top, .topRight],
            [.left, .fill, .right],
            [.bottomLeft, .bottom, .bottomRight]
        ]
        return grid[row][col]
    }

    /// The rect the zone occupies inside `visible` (quarters in corners, halves on edges, the whole
    /// frame for fill).
    func frame(in visible: CGRect) -> CGRect {
        let halfW = visible.width / 2
        let halfH = visible.height / 2
        let x0 = visible.minX
        let y0 = visible.minY
        switch self {
        case .fill: return visible
        case .left: return CGRect(x: x0, y: y0, width: halfW, height: visible.height)
        case .right: return CGRect(x: x0 + halfW, y: y0, width: halfW, height: visible.height)
        case .top: return CGRect(x: x0, y: y0, width: visible.width, height: halfH)
        case .bottom: return CGRect(x: x0, y: y0 + halfH, width: visible.width, height: halfH)
        case .topLeft: return CGRect(x: x0, y: y0, width: halfW, height: halfH)
        case .topRight: return CGRect(x: x0 + halfW, y: y0, width: halfW, height: halfH)
        case .bottomLeft: return CGRect(x: x0, y: y0 + halfH, width: halfW, height: halfH)
        case .bottomRight: return CGRect(x: x0 + halfW, y: y0 + halfH, width: halfW, height: halfH)
        }
    }

    var label: String {
        switch self {
        case .fill: return "fill"
        case .left: return "left half"
        case .right: return "right half"
        case .top: return "top half"
        case .bottom: return "bottom half"
        case .topLeft: return "top-left quarter"
        case .topRight: return "top-right quarter"
        case .bottomLeft: return "bottom-left quarter"
        case .bottomRight: return "bottom-right quarter"
        }
    }
}

/// Grabs the frontmost app's focused window through the Accessibility API, moves it live while the
/// hand drags, and snaps it into a zone on drop. All methods must be called on the main thread.
final class WindowMover {
    var gain: CGFloat = 2   // screen widths per frame width of hand travel; set from config
    static let deadZone: CGFloat = 0.05   // frame widths; a drop with less travel restores the original frame (cancel)

    private(set) var isGrabbing = false
    private var element: AXUIElement?
    private var originalFrame: CGRect = .zero
    private var screenVisible: CGRect = .zero
    private var smoothed: CGPoint = .zero
    private var lastWritten: CGPoint = .zero

    /// Grabs the focused window of the frontmost app. Returns false (and logs nothing) if there is
    /// none or AX refuses.
    @discardableResult
    func grab() -> Bool {
        guard let (el, frame) = WindowMover.focusedWindow() else { return false }
        guard let screen = WindowMover.screen(containing: CGPoint(x: frame.midX, y: frame.midY)) ?? NSScreen.main
        else { return false }
        element = el
        originalFrame = frame
        screenVisible = WindowMover.axVisibleFrame(screen)
        smoothed = .zero
        lastWritten = frame.origin
        isGrabbing = true
        return true
    }

    /// Moves the window live to original.origin + offset(d). Skip the AX write if the position
    /// changed < 1 pt since the last write. Apply a light exponential smoothing (alpha 0.5) to d
    /// before use, to hide landmark jitter.
    func drag(_ d: CGPoint) {
        guard isGrabbing, let el = element else { return }
        let alpha: CGFloat = 0.5
        smoothed = CGPoint(x: smoothed.x + alpha * (d.x - smoothed.x),
                            y: smoothed.y + alpha * (d.y - smoothed.y))
        let off = offset(smoothed)
        let newOrigin = CGPoint(x: originalFrame.origin.x + off.x, y: originalFrame.origin.y + off.y)
        if hypot(newOrigin.x - lastWritten.x, newOrigin.y - lastWritten.y) < 1 { return }
        var frame = originalFrame
        frame.origin = newOrigin
        WindowMover.setFrame(el, frame)
        lastWritten = newOrigin
    }

    /// Ends the grab. Travel `hypot(d.x, d.y) < deadZone` → restore the original frame and return
    /// nil. Otherwise compute the dragged center = original.center + offset(d) (unsmoothed d), find
    /// the screen whose AX visible frame contains that center (fallback: the screen containing the
    /// original center, then NSScreen.main), pick the zone by that center in that screen's AX
    /// visible frame, set the window frame to zone.frame(in:), return the zone. Always clears the
    /// grab, even on failure.
    func drop(_ d: CGPoint) -> WindowZone? {
        defer { clearGrab() }
        guard let el = element else { return nil }
        guard hypot(d.x, d.y) >= WindowMover.deadZone else {
            WindowMover.setFrame(el, originalFrame)
            return nil
        }
        let off = offset(d)
        let originalCenter = CGPoint(x: originalFrame.midX, y: originalFrame.midY)
        let draggedCenter = CGPoint(x: originalCenter.x + off.x, y: originalCenter.y + off.y)
        let screen = WindowMover.screen(containing: draggedCenter)
            ?? WindowMover.screen(containing: originalCenter)
            ?? NSScreen.main
        guard let screen else { return nil }
        let visible = WindowMover.axVisibleFrame(screen)
        let zone = WindowZone.pick(center: draggedCenter, in: visible)
        WindowMover.setFrame(el, zone.frame(in: visible))
        return zone
    }

    /// Cancels: restores the original frame if grabbing.
    func cancel() {
        guard isGrabbing, let el = element else { clearGrab(); return }
        WindowMover.setFrame(el, originalFrame)
        clearGrab()
    }

    private func clearGrab() {
        isGrabbing = false
        element = nil
        originalFrame = .zero
        screenVisible = .zero
        smoothed = .zero
        lastWritten = .zero
    }

    /// offset(d) in AX points, using the screen the window was on at grab time. Negative y because
    /// the hand's +y is up and AX y is down.
    private func offset(_ d: CGPoint) -> CGPoint {
        CGPoint(x: d.x * gain * screenVisible.width, y: -d.y * gain * screenVisible.height)
    }

    // MARK: - Static helpers (used by the CLI too)

    static func focusedWindow() -> (element: AXUIElement, frame: CGRect)? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        var el: AXUIElement?
        if AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success,
           let value {
            el = (value as! AXUIElement)
        } else if AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
                  let windows = value as? [AXUIElement], let first = windows.first {
            el = first
        }
        guard let el, let frame = frame(of: el) else { return nil }
        return (el, frame)
    }

    static func frame(of el: AXUIElement) -> CGRect? {
        var posValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &posValue) == .success,
              AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let posValue, let sizeValue else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posValue as! AXValue, .cgPoint, &point),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }

    /// Set position, then size, then position again (apps with min sizes or constrained positions
    /// settle on the second pass).
    static func setFrame(_ el: AXUIElement, _ f: CGRect) {
        var origin = f.origin
        var size = f.size
        if let posValue = AXValueCreate(.cgPoint, &origin) {
            AXUIElementSetAttributeValue(el, kAXPositionAttribute as CFString, posValue)
        }
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(el, kAXSizeAttribute as CFString, sizeValue)
        }
        if let posValue = AXValueCreate(.cgPoint, &origin) {
            AXUIElementSetAttributeValue(el, kAXPositionAttribute as CFString, posValue)
        }
    }

    /// Grab-less one-shot for the CLI: focused window, its screen, zone frame.
    static func snapFocusedWindow(to zone: WindowZone) -> Bool {
        guard let (el, frame) = focusedWindow() else { return false }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        guard let screen = screen(containing: center) ?? NSScreen.main else { return false }
        setFrame(el, zone.frame(in: axVisibleFrame(screen)))
        return true
    }

    /// AX-space visible frame of an NSScreen: x = f.minX, y = primary.frame.maxY - f.maxY, same
    /// size, where primary = NSScreen.screens[0] (the display whose bottom-left is 0,0 in AppKit).
    static func axVisibleFrame(_ s: NSScreen) -> CGRect {
        guard let primary = NSScreen.screens.first else { return s.visibleFrame }
        let f = s.visibleFrame
        return CGRect(x: f.minX, y: primary.frame.maxY - f.maxY, width: f.width, height: f.height)
    }

    /// The screen whose AX visible frame contains `point`.
    private static func screen(containing point: CGPoint) -> NSScreen? {
        for screen in NSScreen.screens where axVisibleFrame(screen).contains(point) {
            return screen
        }
        return nil
    }
}
