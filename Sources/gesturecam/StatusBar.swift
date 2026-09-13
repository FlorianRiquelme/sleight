import AppKit
import AVFoundation
import QuartzCore

/// Menu bar presence: enable toggle, live state, camera picker, config access.
final class StatusBarController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let engine: Engine
    private var device: AVCaptureDevice
    private let stateItem = NSMenuItem(title: "Idle", action: nil, keyEquivalent: "")
    private let enabledItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
    private let cameraMenu = NSMenu()
    private var flashReset: DispatchWorkItem?
    private lazy var debug = DebugWindowController(engine: engine)
    private let recordItem = NSMenuItem(title: "Start Recording", action: #selector(toggleRecording), keyEquivalent: "")

    private static let emoji: [Gesture: String] = [.openPalm: "✋", .fist: "✊", .twoFingers: "✌️", .thumbsUp: "👍", .swipeLeft: "👈", .swipeRight: "👉"]

    init(engine: Engine, device: AVCaptureDevice) {
        self.engine = engine
        self.device = device
        super.init()

        item.button?.image = NSImage(systemSymbolName: "hand.raised.fill", accessibilityDescription: "gesturecam")
        item.button?.imagePosition = .imageLeading

        let menu = NSMenu()
        stateItem.isEnabled = false
        menu.addItem(stateItem)
        menu.addItem(.separator())
        enabledItem.target = self
        enabledItem.state = .on
        menu.addItem(enabledItem)

        let camItem = NSMenuItem(title: "Camera", action: nil, keyEquivalent: "")
        camItem.submenu = cameraMenu
        rebuildCameraMenu()
        menu.addItem(camItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Debug Window", action: #selector(showDebug), keyEquivalent: "d").target = self
        recordItem.target = self
        menu.addItem(recordItem)
        menu.addItem(withTitle: "Edit Config…", action: #selector(editConfig), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Reload Config", action: #selector(reloadConfig), keyEquivalent: "r").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit gesturecam", action: #selector(quit), keyEquivalent: "q").target = self
        item.menu = menu

        engine.onHand = { [weak self] visible in
            DispatchQueue.main.async { self?.stateItem.title = visible ? "Hand visible" : "Idle" }
        }
        engine.onGesture = { [weak self] g in
            DispatchQueue.main.async { self?.flash(g) }
        }
    }

    private func rebuildCameraMenu() {
        cameraMenu.removeAllItems()
        for d in Camera.devices() {
            let mi = NSMenuItem(title: d.localizedName, action: #selector(pickCamera(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = d
            mi.state = d.uniqueID == device.uniqueID ? .on : .off
            cameraMenu.addItem(mi)
        }
    }

    private func flash(_ g: Gesture) {
        item.button?.title = " " + (Self.emoji[g] ?? g.rawValue)
        stateItem.title = "\(g.rawValue) → \(engine.config.action(for: g)?.summary ?? "no action")"
        flashReset?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.item.button?.title = "" }
        flashReset = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: w)
    }

    @objc private func toggleEnabled() {
        if engine.isRunning {
            engine.stop()
            enabledItem.state = .off
            stateItem.title = "Paused"
            item.button?.appearsDisabled = true
        } else {
            do {
                try engine.start(device: device)
                enabledItem.state = .on
                stateItem.title = "Idle"
                item.button?.appearsDisabled = false
            } catch {
                stateItem.title = "Camera error"
            }
        }
    }

    @objc private func pickCamera(_ sender: NSMenuItem) {
        guard let d = sender.representedObject as? AVCaptureDevice else { return }
        device = d
        rebuildCameraMenu()
        var cfg = engine.config
        cfg.camera = d.localizedName
        try? cfg.save()
        engine.apply(cfg)
        if engine.isRunning { try? engine.start(device: d) }
    }

    @objc func showDebug() { debug.show() }

    @objc private func toggleRecording() {
        if let rec = engine.recorder {
            engine.recorder = nil
            rec.close()
            recordItem.title = "Start Recording"
            stateItem.title = "Saved \(rec.url.lastPathComponent)"
            NSWorkspace.shared.activateFileViewerSelecting([rec.url])
        } else {
            do {
                engine.recorder = try Recorder(url: Recorder.defaultURL(), camera: device.localizedName, label: nil,
                                               config: engine.config, start: CACurrentMediaTime())
                recordItem.title = "Stop Recording"
                stateItem.title = "Recording…"
            } catch {
                stateItem.title = "Recording failed: \(error.localizedDescription)"
            }
        }
    }

    @objc private func editConfig() {
        if !FileManager.default.fileExists(atPath: Config.path.path) { try? Config.default.save() }
        NSWorkspace.shared.open(Config.path)
    }

    @objc private func reloadConfig() {
        do {
            engine.apply(try Config.load())
            stateItem.title = "Config reloaded"
        } catch {
            stateItem.title = "Config error: \(error.localizedDescription)"
        }
    }

    @objc private func quit() {
        engine.stop()
        NSApp.terminate(nil)
    }
}
