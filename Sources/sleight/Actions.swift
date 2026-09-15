import AppKit
import Carbon.HIToolbox

enum ActionError: Error, CustomStringConvertible {
    case unknownKey(String), unknownMediaKey(String), unknownSpotifyCommand(String), appleScript(String)
    var description: String {
        switch self {
        case .unknownKey(let k): return "unknown key '\(k)'"
        case .unknownMediaKey(let k): return "unknown media key '\(k)'"
        case .unknownSpotifyCommand(let k): return "unknown spotify command '\(k)'"
        case .appleScript(let m): return "AppleScript: \(m)"
        }
    }
}

enum ActionRunner {
    static func run(_ action: Action) throws {
        switch action {
        case .key(let combo): try pressKeys(combo)
        case .media(let name): try pressMedia(name)
        case .shell(let cmd): shell(cmd)
        case .spotify(let cmd): try spotify(cmd)
        case .window: break   // handled by Engine's grab/drag, not a one-shot action
        case .none: break
        }
    }

    // MARK: Spotify via Apple Events (targets Spotify regardless of which app macOS thinks is "now playing")

    private static let spotifyCommands: [String: String] = [
        "playpause": "playpause", "play": "play", "pause": "pause",
        "next": "next track", "previous": "previous track", "prev": "previous track",
    ]

    static func spotify(_ command: String) throws {
        guard let verb = spotifyCommands[command.lowercased()] else { throw ActionError.unknownSpotifyCommand(command) }
        var error: NSDictionary?
        NSAppleScript(source: "tell application \"Spotify\" to \(verb)")?.executeAndReturnError(&error)
        if let error, let msg = error[NSAppleScript.errorMessage] as? String {
            throw ActionError.appleScript(msg)
        }
    }

    // MARK: key combos, e.g. "cmd+shift+m", "ctrl+alt+space"

    static func pressKeys(_ combo: String) throws {
        var flags = CGEventFlags()
        var keyName: String?
        for part in combo.lowercased().split(separator: "+").map(String.init) {
            switch part {
            case "cmd", "command": flags.insert(.maskCommand)
            case "shift": flags.insert(.maskShift)
            case "alt", "option", "opt": flags.insert(.maskAlternate)
            case "ctrl", "control": flags.insert(.maskControl)
            case "fn": flags.insert(.maskSecondaryFn)
            default: keyName = part
            }
        }
        guard let name = keyName, let code = keyCodes[name] else { throw ActionError.unknownKey(keyName ?? combo) }
        for down in [true, false] {
            guard let ev = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down) else { continue }
            ev.flags = flags
            ev.post(tap: .cghidEventTap)
        }
    }

    private static let keyCodes: [String: CGKeyCode] = {
        var m: [String: CGKeyCode] = [
            "a": CGKeyCode(kVK_ANSI_A), "b": CGKeyCode(kVK_ANSI_B), "c": CGKeyCode(kVK_ANSI_C), "d": CGKeyCode(kVK_ANSI_D),
            "e": CGKeyCode(kVK_ANSI_E), "f": CGKeyCode(kVK_ANSI_F), "g": CGKeyCode(kVK_ANSI_G), "h": CGKeyCode(kVK_ANSI_H),
            "i": CGKeyCode(kVK_ANSI_I), "j": CGKeyCode(kVK_ANSI_J), "k": CGKeyCode(kVK_ANSI_K), "l": CGKeyCode(kVK_ANSI_L),
            "m": CGKeyCode(kVK_ANSI_M), "n": CGKeyCode(kVK_ANSI_N), "o": CGKeyCode(kVK_ANSI_O), "p": CGKeyCode(kVK_ANSI_P),
            "q": CGKeyCode(kVK_ANSI_Q), "r": CGKeyCode(kVK_ANSI_R), "s": CGKeyCode(kVK_ANSI_S), "t": CGKeyCode(kVK_ANSI_T),
            "u": CGKeyCode(kVK_ANSI_U), "v": CGKeyCode(kVK_ANSI_V), "w": CGKeyCode(kVK_ANSI_W), "x": CGKeyCode(kVK_ANSI_X),
            "y": CGKeyCode(kVK_ANSI_Y), "z": CGKeyCode(kVK_ANSI_Z),
            "0": CGKeyCode(kVK_ANSI_0), "1": CGKeyCode(kVK_ANSI_1), "2": CGKeyCode(kVK_ANSI_2), "3": CGKeyCode(kVK_ANSI_3),
            "4": CGKeyCode(kVK_ANSI_4), "5": CGKeyCode(kVK_ANSI_5), "6": CGKeyCode(kVK_ANSI_6), "7": CGKeyCode(kVK_ANSI_7),
            "8": CGKeyCode(kVK_ANSI_8), "9": CGKeyCode(kVK_ANSI_9),
            "space": CGKeyCode(kVK_Space), "return": CGKeyCode(kVK_Return), "enter": CGKeyCode(kVK_Return),
            "tab": CGKeyCode(kVK_Tab), "escape": CGKeyCode(kVK_Escape), "esc": CGKeyCode(kVK_Escape),
            "delete": CGKeyCode(kVK_Delete), "backspace": CGKeyCode(kVK_Delete), "forwarddelete": CGKeyCode(kVK_ForwardDelete),
            "left": CGKeyCode(kVK_LeftArrow), "right": CGKeyCode(kVK_RightArrow), "up": CGKeyCode(kVK_UpArrow), "down": CGKeyCode(kVK_DownArrow),
            "home": CGKeyCode(kVK_Home), "end": CGKeyCode(kVK_End), "pageup": CGKeyCode(kVK_PageUp), "pagedown": CGKeyCode(kVK_PageDown),
            "-": CGKeyCode(kVK_ANSI_Minus), "=": CGKeyCode(kVK_ANSI_Equal), "[": CGKeyCode(kVK_ANSI_LeftBracket), "]": CGKeyCode(kVK_ANSI_RightBracket),
            ";": CGKeyCode(kVK_ANSI_Semicolon), "'": CGKeyCode(kVK_ANSI_Quote), ",": CGKeyCode(kVK_ANSI_Comma), ".": CGKeyCode(kVK_ANSI_Period),
            "/": CGKeyCode(kVK_ANSI_Slash), "\\": CGKeyCode(kVK_ANSI_Backslash), "`": CGKeyCode(kVK_ANSI_Grave),
        ]
        let fkeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12]
        for (i, k) in fkeys.enumerated() { m["f\(i + 1)"] = CGKeyCode(k) }
        return m
    }()

    // MARK: media keys (NX_KEYTYPE_* via system-defined events)

    private static let mediaKeys: [String: Int32] = [
        "volumeup": 0, "volumedown": 1, "brightnessup": 2, "brightnessdown": 3,
        "mute": 7, "playpause": 16, "next": 17, "previous": 18, "prev": 18,
    ]

    static func pressMedia(_ name: String) throws {
        guard let key = mediaKeys[name.lowercased()] else { throw ActionError.unknownMediaKey(name) }
        for down in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xa00 : 0xb00)
            let data1 = Int((key << 16) | ((down ? 0xa : 0xb) << 8))
            NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: 0,
                               windowNumber: 0, context: nil, subtype: 8, data1: data1, data2: -1)?
                .cgEvent?.post(tap: .cghidEventTap)
        }
    }

    // MARK: shell

    /// Notification Center banner, no sound. osascript so it works unbundled; the banner is what
    /// makes a fire with a silent or unmapped action noticeable while working.
    static func notify(title: String, body: String) {
        func q(_ s: String) -> String { s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", "display notification \"\(q(body))\" with title \"\(q(title))\""]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }

    static func shell(_ command: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", command]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }

    /// Prompts for Accessibility permission if missing (needed to post synthetic input).
    @discardableResult
    static func ensureAccessibility() -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }
}
