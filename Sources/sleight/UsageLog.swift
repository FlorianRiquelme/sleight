import Foundation
import IOKit.ps

/// Samples CPU/memory/fps/hand-visibility/battery on a timer and appends one CSV line per
/// interval, so running the app all day has a measurable cost.
final class UsageLog {
    private let url: URL
    private let interval: TimeInterval
    private let lock = NSLock()
    private var frames = 0
    private var handFrames = 0
    private var lastCPU = UsageLog.cpuTime()
    private var lastWall = Date()
    private var timer: Timer?
    private let handle: FileHandle

    init(url: URL, interval: TimeInterval = 60) {
        self.url = url
        self.interval = interval
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let needsHeader = !FileManager.default.fileExists(atPath: url.path) || (try? Data(contentsOf: url))?.isEmpty ?? true
        if needsHeader {
            let header = "time,cpu_pct,rss_mb,fps,hand_pct,battery_pct,charging\n"
            FileManager.default.createFile(atPath: url.path, contents: header.data(using: .utf8))
        }
        handle = (try? FileHandle(forWritingTo: url)) ?? FileHandle.nullDevice
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in self?.sample() }
    }

    /// Called on the camera queue.
    func note(hand: Bool) {
        lock.lock(); defer { lock.unlock() }
        frames += 1
        if hand { handFrames += 1 }
    }

    private func sample() {
        lock.lock()
        let f = frames, h = handFrames
        frames = 0; handFrames = 0
        lock.unlock()

        let now = Date()
        let cpu = UsageLog.cpuTime()
        let wallElapsed = now.timeIntervalSince(lastWall)
        let cpuPct = wallElapsed > 0 ? (cpu - lastCPU) / wallElapsed * 100 : 0
        lastCPU = cpu; lastWall = now

        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        let fps = Double(f) / interval
        let handPct = f > 0 ? Int(Double(h) / Double(f) * 100) : 0
        let (batteryPct, charging) = UsageLog.battery()

        let line = "\(df.string(from: now)),\(String(format: "%.1f", cpuPct)),\(UsageLog.residentMB()),"
            + "\(String(format: "%.1f", fps)),\(handPct),\(batteryPct),\(charging)\n"
        handle.seekToEndOfFile()
        handle.write(line.data(using: .utf8)!)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// User+system CPU time in seconds, from `getrusage`.
    private static func cpuTime() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        func seconds(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1_000_000 }
        return seconds(usage.ru_utime) + seconds(usage.ru_stime)
    }

    /// Resident memory in MB, from the Mach task basic info.
    private static func residentMB() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Int(info.resident_size / 1_048_576)
    }

    /// Battery percentage and charging state, empty if there is no battery.
    private static func battery() -> (String, String) {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              let source = sources.first,
              let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any] else {
            return ("", "")
        }
        let pct = desc[kIOPSCurrentCapacityKey] as? Int
        let isCharging = desc[kIOPSIsChargingKey] as? Bool
        return (pct.map(String.init) ?? "", isCharging.map { $0 ? "1" : "0" } ?? "")
    }
}
