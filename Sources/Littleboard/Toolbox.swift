import AppKit
import Foundation

/// Real system utilities behind the Toolbox widget. Every action is a plain,
/// local system call — caffeinate, Finder defaults, volume settings, disk ejects.
@MainActor
enum Toolbox {
    // MARK: - Stay awake (caffeinate child process)

    private static var caffeinateProcess: Process?
    private static var stayAwakeUntil: Date?

    static var stayAwakeRemaining: Int? {
        guard let stayAwakeUntil else { return nil }
        let seconds = Int(stayAwakeUntil.timeIntervalSinceNow.rounded())
        return seconds > 0 ? seconds : nil
    }

    static func setStayAwake(minutes: Int?) {
        cancelStayAwake()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        process.arguments = ["-ims"] + (minutes.map { ["-t", String($0 * 60)] } ?? [])
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return }
        caffeinateProcess = process
        stayAwakeUntil = minutes.map { Date.now.addingTimeInterval(Double($0) * 60) }
    }

    static func cancelStayAwake() {
        caffeinateProcess?.terminate()
        caffeinateProcess = nil
        stayAwakeUntil = nil
    }

    static func toggleStayAwake(minutes: Int?) {
        if caffeinateProcess?.isRunning == true { cancelStayAwake() } else { setStayAwake(minutes: minutes) }
    }

    // MARK: - Dark Mode (System Events AppleScript, one-time automation prompt)

    static func toggleDarkMode() {
        let script = """
        tell application "System Events"
            tell appearance preferences to set dark mode to not dark mode
        end tell
        """
        Task.detached(priority: .utility) { _ = await LiveFeed.runCommand(executable: "/usr/bin/osascript", arguments: ["-e", script], timeout: 8) }
    }

    // MARK: - Finder desktop toggles (defaults + brief Finder restart)

    nonisolated static func isDesktopHidden() -> Bool {
        readDefault("com.apple.finder", "CreateDesktop") == "0"
    }

    static func setDesktopHidden(_ hidden: Bool) {
        writeDefault("com.apple.finder", "CreateDesktop", hidden ? "0" : "1")
        restartFinder()
    }

    nonisolated static func isShowingHiddenFiles() -> Bool {
        readDefault("com.apple.finder", "AppleShowAllFiles") == "1"
    }

    static func setShowHiddenFiles(_ show: Bool) {
        writeDefault("com.apple.finder", "AppleShowAllFiles", show ? "1" : "0")
        restartFinder()
    }

    nonisolated private static func readDefault(_ domain: String, _ key: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["read", domain, key]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return "" }
        process.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    nonisolated private static func writeDefault(_ domain: String, _ key: String, _ value: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["write", domain, key, "-bool", value]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return }
        process.waitUntilExit()
    }

    nonisolated private static func restartFinder() {
        Task.detached(priority: .utility) {
            _ = await LiveFeed.runCommand(executable: "/usr/bin/killall", arguments: ["Finder"], timeout: 5)
        }
    }

    // MARK: - Mute

    static func toggleMute() {
        Task.detached(priority: .utility) { _ = await LiveFeed.runCommand(executable: "/usr/bin/osascript", arguments: ["-e", "set volume output muted (not (output muted of (get volume settings)))"], timeout: 6) }
    }

    static func isMuted() async -> Bool {
        guard let output = await LiveFeed.runCommand(executable: "/usr/bin/osascript", arguments: ["-e", "output muted of (get volume settings)"], timeout: 6) else { return false }
        return output.contains("true")
    }

    // MARK: - One-shot actions

    static func ejectAll() {
        Task.detached(priority: .utility) {
            _ = await LiveFeed.runCommand(executable: "/usr/bin/osascript", arguments: ["-e", "tell application \"Finder\" to eject (every disk whose ejectable is true)"], timeout: 20)
        }
    }

    static func displayOff() {
        Task.detached(priority: .utility) {
            _ = await LiveFeed.runCommand(executable: "/usr/bin/pmset", arguments: ["displaysleepnow"], timeout: 6)
        }
    }

    static func startScreenSaver() {
        Task.detached(priority: .utility) {
            _ = await LiveFeed.runCommand(executable: "/usr/bin/open", arguments: ["/System/Library/CoreServices/ScreenSaverEngine.app"], timeout: 6)
        }
    }

    static func takeScreenshot() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let path = NSString(string: "~/Desktop/Screenshot \(formatter.string(from: .now)).png").expandingTildeInPath
        Task.detached(priority: .utility) {
            _ = await LiveFeed.runCommand(executable: "/usr/sbin/screencapture", arguments: ["-x", path], timeout: 10)
        }
    }
}
