import AppKit
import AVFoundation
import QuartzCore
import ServiceManagement

/// Menu bar presence: enable toggle, live state, camera picker, config access.
final class StatusBarController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let engine: Engine
    private var device: AVCaptureDevice?
    private let stateItem = NSMenuItem(title: "Idle", action: nil, keyEquivalent: "")
    private let enabledItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
    private let cameraMenu = NSMenu()
    private let openCameraSettingsItem = NSMenuItem(title: "Open Camera Settings…", action: #selector(openCameraSettings), keyEquivalent: "")
    private let accessibilityWarningItem = NSMenuItem(title: "Accessibility missing – actions won't fire", action: nil, keyEquivalent: "")
    private let openAccessibilityItem = NSMenuItem(title: "Open Accessibility Settings…", action: #selector(openAccessibilitySettings), keyEquivalent: "")
    private let launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    private var flashReset: DispatchWorkItem?
    private lazy var debug = DebugWindowController(engine: engine)
    private let recordItem = NSMenuItem(title: "Start Recording", action: #selector(toggleRecording), keyEquivalent: "")

    private var handVisible = false
    private var userPaused = false
    private var cameraProblem: String?
    private var permissionDenied = false

    private static let emoji: [Gesture: String] = [.openPalm: "✋", .fist: "✊", .twoFingers: "✌️", .thumbsUp: "👍", .swipeLeft: "👈", .swipeRight: "👉"]

    init(engine: Engine, device: AVCaptureDevice?) {
        self.engine = engine
        self.device = device
        super.init()

        item.button?.imagePosition = .imageLeading

        let menu = NSMenu()
        menu.delegate = self
        stateItem.isEnabled = false
        menu.addItem(stateItem)
        openCameraSettingsItem.target = self
        openCameraSettingsItem.isHidden = true
        menu.addItem(openCameraSettingsItem)
        accessibilityWarningItem.isEnabled = false
        accessibilityWarningItem.isHidden = true
        menu.addItem(accessibilityWarningItem)
        openAccessibilityItem.target = self
        openAccessibilityItem.isHidden = true
        menu.addItem(openAccessibilityItem)
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
        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)
        updateLaunchAtLoginItem()
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit sleight", action: #selector(quit), keyEquivalent: "q").target = self
        item.menu = menu

        engine.onHand = { [weak self] visible in
            DispatchQueue.main.async {
                guard let self else { return }
                self.handVisible = visible
                self.stateItem.title = visible ? "Hand visible" : "Idle"
                self.refreshIcon()
            }
        }
        engine.onGesture = { [weak self] g in
            DispatchQueue.main.async { self?.flash(g) }
        }
        engine.onCameraError = { [weak self] msg in
            DispatchQueue.main.async { self?.reportCameraProblem("Camera error: \(msg)") }
        }

        refreshIcon()
        if device == nil { reportCameraProblem("No camera found") }
    }

    /// Derives the status bar icon and disabled appearance from current state. Only touches
    /// `image`/`appearsDisabled`; never `title` (that's owned by `flash`).
    private func refreshIcon() {
        let symbol: String
        var disabled = false
        if cameraProblem != nil {
            symbol = "video.slash"
        } else if userPaused {
            symbol = "hand.raised.slash"
            disabled = true
        } else if handVisible {
            symbol = "hand.raised.fill"
        } else {
            symbol = "hand.raised"
        }
        item.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "sleight")
        item.button?.appearsDisabled = disabled
    }

    /// Reports a camera problem (no camera, start failure, runtime error). `permissionDenied`
    /// additionally surfaces the "Open Camera Settings…" item.
    func reportCameraProblem(_ message: String, permissionDenied: Bool = false) {
        cameraProblem = message
        self.permissionDenied = permissionDenied
        stateItem.title = message
        refreshIcon()
    }

    private func rebuildCameraMenu() {
        cameraMenu.removeAllItems()
        let devices = Camera.devices()
        guard !devices.isEmpty else {
            let mi = NSMenuItem(title: "No cameras", action: nil, keyEquivalent: "")
            mi.isEnabled = false
            cameraMenu.addItem(mi)
            return
        }
        for d in devices {
            let mi = NSMenuItem(title: d.localizedName, action: #selector(pickCamera(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = d
            mi.state = d.uniqueID == device?.uniqueID ? .on : .off
            cameraMenu.addItem(mi)
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildCameraMenu()
        let trusted = AXIsProcessTrusted()
        accessibilityWarningItem.isHidden = trusted
        openAccessibilityItem.isHidden = trusted
        openCameraSettingsItem.isHidden = !permissionDenied
        updateLaunchAtLoginItem()
    }

    private func updateLaunchAtLoginItem() {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            launchAtLoginItem.isEnabled = false
            launchAtLoginItem.toolTip = "Run build/sleight.app (scripts/bundle.sh) to enable"
            launchAtLoginItem.state = .off
            return
        }
        launchAtLoginItem.isEnabled = true
        launchAtLoginItem.toolTip = nil
        launchAtLoginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
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
        guard let device else { return }
        if engine.isRunning {
            engine.stop()
            enabledItem.state = .off
            userPaused = true
            stateItem.title = "Paused"
        } else {
            do {
                try engine.start(device: device)
                enabledItem.state = .on
                userPaused = false
                cameraProblem = nil
                permissionDenied = false
                stateItem.title = "Idle"
            } catch {
                reportCameraProblem("Camera error: \(error.localizedDescription)")
            }
        }
        refreshIcon()
    }

    @objc private func pickCamera(_ sender: NSMenuItem) {
        guard let d = sender.representedObject as? AVCaptureDevice else { return }
        device = d
        var cfg = engine.config
        cfg.camera = d.localizedName
        try? cfg.save()
        engine.apply(cfg)
        if engine.isRunning || cameraProblem != nil {
            do {
                try engine.start(device: d)
                cameraProblem = nil
                permissionDenied = false
                userPaused = false
                enabledItem.state = .on
                stateItem.title = "Idle"
            } catch {
                reportCameraProblem("Camera error: \(error.localizedDescription)")
            }
            refreshIcon()
        }
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
                engine.recorder = try Recorder(url: Recorder.defaultURL(), camera: device?.localizedName ?? "unknown", label: nil,
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

    @objc private func openCameraSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
    }

    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func toggleLaunchAtLogin() {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            stateItem.title = error.localizedDescription
        }
        updateLaunchAtLoginItem()
    }

    @objc private func quit() {
        engine.stop()
        NSApp.terminate(nil)
    }
}
