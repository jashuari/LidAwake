import Foundation
import IOKit.ps

/// Outcome of a privileged `pmset` call.
enum PrivResult: Sendable {
    case ok
    case cancelled
    case failed(String)
}

/// Reads and changes the system-wide `disablesleep` flag via /usr/bin/pmset.
/// All functions are synchronous and blocking; call them off the main thread
/// unless blocking is acceptable (e.g. during termination).
enum PowerControl {
    static let pmset = "/usr/bin/pmset"

    /// Actual state from `pmset -g`: the `SleepDisabled` line is only printed
    /// when the flag is set. Returns nil if pmset could not be run.
    static func isSleepDisabled() -> Bool? {
        guard let r = run(pmset, ["-g"]), r.status == 0 else { return nil }
        for line in r.out.split(separator: "\n") {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            if parts.first == "SleepDisabled" { return parts.last == "1" }
        }
        return false
    }

    /// Runs `pmset -a disablesleep 0|1` as root. Tries passwordless sudo first
    /// (works only if the optional sudoers rule is installed), then falls back to
    /// the standard macOS administrator password prompt.
    static func setSleepDisabled(_ on: Bool) -> PrivResult {
        let value = on ? "1" : "0"
        if let r = run("/usr/bin/sudo", ["-n", pmset, "-a", "disablesleep", value]), r.status == 0 {
            return .ok
        }
        let prompt = on
            ? "LidAwake wants to keep your Mac awake with the lid closed."
            : "LidAwake wants to restore normal sleep."
        let script = "do shell script \"\(pmset) -a disablesleep \(value)\" "
            + "with prompt \"\(prompt)\" with administrator privileges"
        guard let r = run("/usr/bin/osascript", ["-e", script]) else {
            return .failed("Could not run /usr/bin/osascript.")
        }
        if r.status == 0 { return .ok }
        if r.err.contains("-128") { return .cancelled } // errAEUserCanceled
        return .failed(r.err.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func run(_ path: String, _ args: [String]) -> (status: Int32, out: String, err: String)? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let o = out.fileHandleForReading.readDataToEndOfFile()
        let e = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: o, as: UTF8.self), String(decoding: e, as: UTF8.self))
    }
}

struct BatteryInfo: Sendable {
    let percent: Int
    let onBattery: Bool
}

enum Battery {
    /// Internal battery state via IOKit power sources; nil on Macs without one.
    static func read() -> BatteryInfo? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  let cur = desc[kIOPSCurrentCapacityKey] as? Int,
                  let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0
            else { continue }
            if let type = desc[kIOPSTypeKey] as? String, type != kIOPSInternalBatteryType { continue }
            let state = desc[kIOPSPowerSourceStateKey] as? String
            return BatteryInfo(percent: cur * 100 / max, onBattery: state == kIOPSBatteryPowerValue)
        }
        return nil
    }
}
