import AppKit
import Foundation

/// Foreground-app usage tracking, isolated from the board model so the 15-second
/// tick no longer re-renders every widget or rewrites the whole board file.
/// Only the App Time widget reads this; persisted in its own file.
@MainActor
final class AppUsageMonitor: ObservableObject {
    static let shared = AppUsageMonitor()

    @Published private(set) var usage: [String: Int] = [:]
    @Published private(set) var bundleIDs: [String: String] = [:]
    @Published private(set) var categoryHourly: [String: [Int]] = [:]
    private(set) var day = ""

    private var timer: Timer?
    private var saveWork: DispatchWorkItem?

    private var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Littleboard", isDirectory: true)
    }
    private var file: URL { folder.appendingPathComponent("appusage.json") }

    private init() {
        load()
        let today = Self.dayStamp(.now)
        if day != today {
            day = today
            usage = [:]
            categoryHourly = [:]
        }
        start()
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer?.tolerance = 2
    }

    private func tick() {
        let today = Self.dayStamp(.now)
        if day != today {
            day = today
            usage = [:]
            categoryHourly = [:]
        }
        let frontmost = NSWorkspace.shared.frontmostApplication
        let app = frontmost?.localizedName ?? "Other"
        usage[app, default: 0] += 15
        if let bundleID = frontmost?.bundleIdentifier, !bundleID.isEmpty { bundleIDs[app] = bundleID }
        let category = Self.appCategory(name: app, bundleID: bundleIDs[app] ?? "")
        var buckets = categoryHourly[category] ?? Array(repeating: 0, count: 24)
        let hour = Calendar.current.component(.hour, from: .now)
        buckets[hour] += 15
        categoryHourly[category] = buckets
        scheduleSave()
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.performSave() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func performSave() {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let payload = SavedUsage(day: day, usage: usage, bundleIDs: bundleIDs, categoryHourly: categoryHourly)
            try JSONEncoder.prettyUsage.encode(payload).write(to: file, options: .atomic)
        } catch { NSLog("Littleboard could not save app usage: %@", error.localizedDescription) }
    }

    private func load() {
        // Migrate any usage tracked in the old board file, then persist separately.
        if let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode(SavedUsage.self, from: data) {
            day = saved.day
            usage = saved.usage
            bundleIDs = saved.bundleIDs
            categoryHourly = saved.categoryHourly
            return
        }
        let boardFile = folder.appendingPathComponent("board.json")
        guard let data = try? Data(contentsOf: boardFile), let board = try? JSONDecoder().decode(LegacyBoardUsage.self, from: data) else { return }
        day = board.appUsageDay ?? ""
        usage = board.appUsage ?? [:]
        bundleIDs = board.appBundleIDs ?? [:]
        categoryHourly = board.appCategoryHourly ?? [:]
    }

    static func dayStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static let appCategories: [(name: String, color: String)] = [
        ("Utilities", "0A84FF"), ("Productivity & Finance", "00C7BE"), ("Social", "FF2D55"), ("Entertainment", "BF5AF2"), ("Other", "FF9F0A"),
    ]

    static func appCategory(name: String, bundleID: String) -> String {
        let app = name.lowercased()
        let bundle = bundleID.lowercased()
        let productivity = ["xcode", "code", "terminal", "iterm", "warp", "notes", "mail", "calendar", "reminders", "keynote", "numbers", "pages", "excel", "word", "powerpoint", "outlook", "slack", "teams", "notion", "figma", "postman", "github", "gitlab", "chatgpt", "claude", "codex", "zcode", "cursor", "linear", "jira", "quicken", "finance"]
        let utilities = ["settings", "system preferences", "finder", "activity monitor", "console", "disk utility", "preview", "calculator", "archive utility", "battery", "keychain", "littleboard", "screenshot"]
        let social = ["messages", "whatsapp", "telegram", "discord", "signal", "twitter", "instagram", "facebook", "linkedin", "bezel"]
        let entertainment = ["music", "spotify", "youtube", "netflix", "photos", "podcasts", "tv", "steam", "minecraft", "photobooth"]
        if productivity.contains(where: { app.contains($0) || bundle.contains($0) }) { return "Productivity & Finance" }
        if social.contains(where: { app.contains($0) || bundle.contains($0) }) { return "Social" }
        if entertainment.contains(where: { app.contains($0) || bundle.contains($0) }) { return "Entertainment" }
        if utilities.contains(where: { app.contains($0) || bundle.contains($0) }) { return "Utilities" }
        return "Other"
    }
}

private struct SavedUsage: Codable {
    var day: String
    var usage: [String: Int]
    var bundleIDs: [String: String]
    var categoryHourly: [String: [Int]]
}

private struct LegacyBoardUsage: Codable {
    var appUsage: [String: Int]?
    var appUsageDay: String?
    var appBundleIDs: [String: String]?
    var appCategoryHourly: [String: [Int]]?
}

private extension JSONEncoder {
    static var prettyUsage: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
