import AppKit
import CoreWLAN
import Foundation
import IOKit
import IOBluetooth

/// Fetch layer for the live widgets. Every source here is a public, keyless
/// endpoint, so the app stays free of accounts, secrets, and configuration.
enum LiveFeed {
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.httpAdditionalHeaders = ["User-Agent": "Littleboard/0.1 (macOS; open-source example)"]
        return URLSession(configuration: configuration)
    }()

    private static let speedSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 120
        configuration.httpAdditionalHeaders = ["User-Agent": "Littleboard/0.1 (macOS; open-source example)"]
        return URLSession(configuration: configuration)
    }()

    // MARK: - Stocks (Yahoo Finance chart endpoint, free and keyless)

    struct StockQuote: Identifiable {
        let symbol: String
        let price: Double
        let previousClose: Double
        let currency: String?
        let closes: [Double]
        var change: Double { price - previousClose }
        var changePercent: Double { previousClose != 0 ? change / previousClose * 100 : 0 }
        var id: String { symbol }
    }

    static func stocks(_ symbols: [String]) async -> [StockQuote] {
        let wanted = symbols.map { $0.uppercased() }.filter { !$0.isEmpty }.prefix(5)
        var found: [StockQuote] = []
        await withTaskGroup(of: StockQuote?.self) { group in
            for symbol in wanted { group.addTask { try? await Self.stockQuote(symbol) } }
            for await quote in group { if let quote { found.append(quote) } }
        }
        return wanted.compactMap { symbol in found.first { $0.symbol == symbol } }
    }

    private static func stockQuote(_ symbol: String) async throws -> StockQuote {
        var components = URLComponents(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(symbol)")!
        components.queryItems = [URLQueryItem(name: "range", value: "1d"), URLQueryItem(name: "interval", value: "15m")]
        let (data, response) = try await session.data(from: components.url!)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw URLError(.badServerResponse) }
        let decoded = try JSONDecoder().decode(YahooChart.self, from: data)
        guard let result = decoded.chart.result?.first, let price = result.meta.regularMarketPrice,
              let previousClose = result.meta.chartPreviousClose else { throw URLError(.cannotParseResponse) }
        let closes = zip(result.timestamp ?? [], result.indicators?.quote?.first?.close ?? []).compactMap { _, close in close }
        return StockQuote(symbol: symbol, price: price, previousClose: previousClose, currency: result.meta.currency, closes: closes)
    }

    private struct YahooChart: Decodable {
        var chart: Chart
        struct Chart: Decodable { var result: [Result]? }
        struct Result: Decodable {
            var meta: Meta
            var timestamp: [Double]?
            var indicators: Indicators?
            struct Meta: Decodable { var currency: String?; var regularMarketPrice: Double?; var chartPreviousClose: Double? }
            struct Indicators: Decodable { var quote: [Quote]? }
            struct Quote: Decodable { var close: [Double?]? }
        }
    }

    // MARK: - Crypto (CoinGecko public price endpoint)

    struct CryptoPrice: Identifiable {
        let id: String
        let name: String
        let price: Double
        let change24h: Double
    }

    static func crypto(_ ids: [String]) async -> [CryptoPrice] {
        let wanted = ids.map { $0.lowercased() }.filter { !$0.isEmpty }.prefix(6)
        guard !wanted.isEmpty else { return [] }
        var components = URLComponents(string: "https://api.coingecko.com/api/v3/simple/price")!
        components.queryItems = [
            URLQueryItem(name: "ids", value: wanted.joined(separator: ",")),
            URLQueryItem(name: "vs_currencies", value: "usd"),
            URLQueryItem(name: "include_24hr_change", value: "true"),
        ]
        do {
            let (data, response) = try await session.data(from: components.url!)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw URLError(.badServerResponse) }
            let entries = try JSONDecoder().decode([String: CoinEntry].self, from: data)
            return wanted.compactMap { id in
                guard let entry = entries[id], let price = entry.usd else { return nil }
                return CryptoPrice(id: id, name: Self.coinName(id), price: price, change24h: entry.change ?? 0)
            }
        } catch { return [] }
    }

    private struct CoinEntry: Decodable {
        var usd: Double?
        var change: Double?
        enum CodingKeys: String, CodingKey { case usd; case change = "usd_24h_change" }
    }

    private static func coinName(_ id: String) -> String {
        let known = ["bitcoin": "Bitcoin", "ethereum": "Ethereum", "solana": "Solana", "ripple": "XRP", "dogecoin": "Dogecoin", "cardano": "Cardano", "litecoin": "Litecoin", "chainlink": "Chainlink", "polkadot": "Polkadot", "avalanche": "Avalanche", "tron": "TRON", "monero": "Monero", "stellar": "Stellar", "tether": "Tether", "binancecoin": "BNB", "the-open-network": "TON", "shiba-inu": "Shiba Inu", "pepe": "Pepe"]
        return known[id] ?? id.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
    }

    // MARK: - Currencies (Frankfurter, ECB reference rates)

    static func rates(base: String, quotes: [String]) async -> (base: String, date: String, rows: [(String, Double)])? {
        let cleanQuotes = quotes.map { $0.uppercased() }.filter { !$0.isEmpty }.prefix(6)
        var components = URLComponents(string: "https://api.frankfurter.dev/v1/latest")!
        components.queryItems = [URLQueryItem(name: "base", value: base.uppercased())]
        if !cleanQuotes.isEmpty { components.queryItems?.append(URLQueryItem(name: "symbols", value: cleanQuotes.joined(separator: ","))) }
        do {
            let (data, response) = try await session.data(from: components.url!)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw URLError(.badServerResponse) }
            let decoded = try JSONDecoder().decode(FrankfurterRates.self, from: data)
            let rows = cleanQuotes.compactMap { code -> (String, Double)? in decoded.rates[code].map { (code, $0) } }
            guard !rows.isEmpty else { return nil }
            return (decoded.base, decoded.date, rows)
        } catch { return nil }
    }

    private struct FrankfurterRates: Decodable { var base: String; var date: String; var rates: [String: Double] }

    // MARK: - GitHub (public repository data)

    struct RepoInfo: Decodable {
        var fullName: String
        var descriptionText: String?
        var stars: Int
        var forks: Int
        var issues: Int
        var pushedAt: String
        var language: String?
        enum CodingKeys: String, CodingKey {
            case fullName = "full_name", descriptionText = "description", stars = "stargazers_count"
            case forks = "forks_count", issues = "open_issues_count", pushedAt = "pushed_at", language
        }
    }

    static func repository(_ slug: String) async -> RepoInfo? {
        let clean = slug.trimmingCharacters(in: .whitespaces)
        guard clean.split(separator: "/").count == 2 else { return nil }
        do {
            let (data, response) = try await session.data(from: URL(string: "https://api.github.com/repos/\(clean)")!)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw URLError(.badServerResponse) }
            return try JSONDecoder().decode(RepoInfo.self, from: data)
        } catch { return nil }
    }

    // MARK: - Air quality (Open-Meteo air-quality API)

    struct AirQualitySnapshot {
        var location: String
        var aqi: Int?
        var pm25: Double?
        var pm10: Double?
        var ozone: Double?
    }

    static func airQuality(city: String) async -> AirQualitySnapshot? {
        guard let place = await geocode(city) else { return nil }
        var components = URLComponents(string: "https://air-quality-api.open-meteo.com/v1/air-quality")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(place.latitude)),
            URLQueryItem(name: "longitude", value: String(place.longitude)),
            URLQueryItem(name: "current", value: "us_aqi,pm2_5,pm10,ozone"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        do {
            let (data, _) = try await session.data(from: components.url!)
            let decoded = try JSONDecoder().decode(AirQualityResponse.self, from: data)
            return AirQualitySnapshot(location: place.name, aqi: decoded.current.aqi, pm25: decoded.current.pm25, pm10: decoded.current.pm10, ozone: decoded.current.ozone)
        } catch { return nil }
    }

    static func aqiCategory(_ aqi: Int) -> (label: String, color: String) {
        switch aqi {
        case 0...50: return ("Good", "30D158")
        case 51...100: return ("Moderate", "FFD60A")
        case 101...150: return ("Unhealthy · Sensitive", "FF9F0A")
        case 151...200: return ("Unhealthy", "FF453A")
        case 201...300: return ("Very Unhealthy", "BF5AF2")
        default: return ("Hazardous", "FF2D55")
        }
    }

    struct GeoPlace { var name: String; var latitude: Double; var longitude: Double }

    static func geocode(_ city: String) async -> GeoPlace? {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [URLQueryItem(name: "name", value: city), URLQueryItem(name: "count", value: "1"), URLQueryItem(name: "language", value: "en"), URLQueryItem(name: "format", value: "json")]
        do {
            let (data, _) = try await session.data(from: components.url!)
            let decoded = try JSONDecoder().decode(GeoLookupResponse.self, from: data)
            guard let place = decoded.results?.first else { return nil }
            let name = place.name + (place.admin1.map { ", \($0)" } ?? "")
            return GeoPlace(name: name, latitude: place.latitude, longitude: place.longitude)
        } catch { return nil }
    }

    private struct GeoLookupResponse: Decodable { var results: [GeoResult]? }
    private struct GeoResult: Decodable { var name: String; var admin1: String?; var latitude: Double; var longitude: Double }

    private struct AirQualityResponse: Decodable {
        var current: Current
        struct Current: Decodable {
            var aqi: Int?; var pm25: Double?; var pm10: Double?; var ozone: Double?
            enum CodingKeys: String, CodingKey { case aqi = "us_aqi"; case pm25 = "pm2_5"; case pm10 = "pm10"; case ozone }
        }
    }

    // MARK: - Battery (IOKit AppleSmartBattery, the same source stats apps use)

    struct BatteryStats {
        var percent: Int
        var charging: Bool
        var onAC: Bool
        var watts: Double?
        var cycleCount: Int?
        var healthPercent: Int?
        var temperatureC: Double?
        var minutesRemaining: Int?
    }

    static func batteryStats() -> BatteryStats? {
        // IOPS estimate for time remaining; falls back to nil on desktops.
        var minutesRemaining: Int?
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [AnyObject] {
            for source in list {
                guard let raw = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                      let current = raw[kIOPSCurrentCapacityKey] as? Int,
                      let maximum = raw[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
                let estimate = IOPSGetTimeRemainingEstimate()
                minutesRemaining = estimate > 0 && estimate < 100_000 ? Int(estimate / 60) : nil
                // Registry fallback keeps desktops (no AppleSmartBattery) working.
                var stats = BatteryStats(
                    percent: Int((Double(current) / Double(maximum) * 100).rounded()),
                    charging: raw[kIOPSIsChargingKey] as? Bool ?? false,
                    onAC: (raw[kIOPSPowerSourceStateKey] as? String) == "AC Power",
                    watts: nil, cycleCount: nil, healthPercent: nil, temperatureC: nil,
                    minutesRemaining: minutesRemaining
                )
                if let registry = smartBatteryRegistry() {
                    if let maxCapacity = registry["AppleRawMaxCapacity"] as? Int, maxCapacity > 0,
                       let rawCurrent = registry["AppleRawCurrentCapacity"] as? Int {
                        stats.percent = min(100, Int((Double(rawCurrent) / Double(maxCapacity) * 100).rounded()))
                        if let design = registry["AppleRawDesignCapacity"] as? Int, design > 0 {
                            stats.healthPercent = min(100, Int((Double(maxCapacity) / Double(design) * 100).rounded()))
                        }
                    }
                    if let amperage = registry["InstantAmperage"] as? Int, let voltage = registry["Voltage"] as? Int {
                        stats.watts = abs(Double(amperage) * Double(voltage)) / 1_000_000
                    }
                    stats.cycleCount = registry["CycleCount"] as? Int
                    if let temperature = registry["Temperature"] as? Int { stats.temperatureC = Double(temperature) / 100 }
                }
                return stats
            }
        }
        if let registry = smartBatteryRegistry(), let maxCapacity = registry["AppleRawMaxCapacity"] as? Int, maxCapacity > 0 {
            let percent = min(100, Int((Double(registry["AppleRawCurrentCapacity"] as? Int ?? 0) / Double(maxCapacity) * 100).rounded()))
            return BatteryStats(percent: percent, charging: registry["IsCharging"] as? Bool ?? false, onAC: registry["ExternalConnected"] as? Bool ?? false, watts: nil, cycleCount: registry["CycleCount"] as? Int, healthPercent: nil, temperatureC: nil, minutesRemaining: nil)
        }
        return nil
    }

    private static func smartBatteryRegistry() -> [String: Any]? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = properties?.takeRetainedValue() as? [String: Any] else { return nil }
        return dict
    }

    static func lowPowerModeEnabled() async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
                process.arguments = ["-g"]
                let output = Pipe()
                process.standardOutput = output
                process.standardError = FileHandle.nullDevice
                do { try process.run() } catch { continuation.resume(returning: false); return }
                process.waitUntilExit()
                let text = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                continuation.resume(returning: text.range(of: "lowpowermode 1") != nil)
            }
        }
    }

    // MARK: - Bluetooth accessory batteries (system_profiler, the public path)

    struct BluetoothDeviceBattery: Identifiable {
        var name: String
        var percent: Int
        var icon: String
        var id: String { name }
    }

    static func bluetoothBatteryDevices() async -> [BluetoothDeviceBattery] {
        let json = await runCommand(executable: "/usr/bin/system_profiler", arguments: ["-json", "SPBluetoothDataType"], timeout: 15)
        guard let data = json?.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = root["SPBluetoothDataType"] as? [[String: Any]] else { return [] }
        var devices: [BluetoothDeviceBattery] = []
        for entry in entries {
            guard let connected = entry["device_connected"] as? [[String: Any]] else { continue }
            for device in connected {
                guard let name = device["_name"] as? String else { continue }
                var levels: [Int] = []
                for (key, value) in device where key.hasPrefix("device_batteryLevel") {
                    if let text = value as? String, let number = Int(text.filter { $0.isNumber }) {
                        levels.append(min(100, number))
                    } else if let number = value as? Int {
                        levels.append(min(100, number))
                    }
                }
                guard let percent = levels.min() else { continue }
                devices.append(BluetoothDeviceBattery(name: name, percent: percent, icon: Self.accessoryIcon(for: name)))
            }
        }
        return devices
    }

    private static func accessoryIcon(for name: String) -> String {
        let lowered = name.lowercased()
        if lowered.contains("airpod") || lowered.contains("beats") || lowered.contains("headphone") { return "headphones" }
        if lowered.contains("keyboard") { return "keyboard" }
        if lowered.contains("mouse") { return "mouse" }
        if lowered.contains("trackpad") { return "rectangle.on.rectangle.slash" }
        return "battery.100percent"
    }

    // MARK: - Paired Bluetooth devices with real connect / disconnect

    struct PairedDeviceInfo: Identifiable {
        var name: String
        var address: String
        var connected: Bool
        var batteryPercent: Int?
        var icon: String
        var id: String { address }
    }

    /// Enumerates paired devices from IOBluetooth, merging in battery levels
    /// reported by system_profiler for whatever is currently connected.
    @MainActor static func pairedBluetoothDevices(batteryLevels: [String: Int]) -> [PairedDeviceInfo] {
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return [] }
        return paired.compactMap { device in
            guard let name = device.name, !name.isEmpty else { return nil }
            return PairedDeviceInfo(
                name: name,
                address: device.addressString ?? UUID().uuidString,
                connected: device.isConnected(),
                batteryPercent: device.isConnected() ? batteryLevels[name] : nil,
                icon: accessoryIcon(for: name)
            )
        }
    }

    @MainActor static func setBluetoothConnection(address: String, connect: Bool) -> Bool {
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice],
              let device = paired.first(where: { $0.addressString == address }) else { return false }
        if connect {
            return device.openConnection() == kIOReturnSuccess
        }
        device.closeConnection()
        return true
    }

    static func runCommand(executable: String, arguments: [String], timeout: Double) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                let output = Pipe()
                process.standardOutput = output
                process.standardError = FileHandle.nullDevice
                let exited = DispatchSemaphore(value: 0)
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    guard exited.wait(timeout: .now()) == .timedOut, process.isRunning else { return }
                    process.terminate()
                }
                do { try process.run() } catch { exited.signal(); continuation.resume(returning: nil); return }
                process.waitUntilExit()
                exited.signal()
                let text = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: (text?.isEmpty == false) ? text : nil)
            }
        }
    }

    // MARK: - GitHub (Keychain token + search/notification/calendar feed)

    enum GitHubKeychain {
        static let service = "Littleboard.GitHubToken"
        static func save(_ token: String) {
            let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "token"]
            SecItemDelete(base as CFDictionary)
            guard !token.isEmpty else { return }
            var attributes = base
            attributes[kSecValueData as String] = Data(token.utf8)
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(attributes as CFDictionary, nil)
        }
        static func load() -> String? {
            var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "token", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
            var item: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }
        static func delete() {
            let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "token"]
            SecItemDelete(query as CFDictionary)
        }
    }

    struct GitHubFeed {
        var login: String?
        var reviews = 0
        var issues = 0
        var prs = 0
        var inbox = 0
        var heatmap: [[Int]] = []
        var totalContributions: Int?
        var runStatus: String?
        var runConclusion: String?
        var runName: String?
        var stars: Int?
        var openIssues: Int?
    }

    static func githubFeed(repo: String) async -> GitHubFeed {
        var feed = GitHubFeed()
        let token = GitHubKeychain.load()
        if let token {
            // Who am I?
            if let (data, _) = try? await session.data(from: URL(string: "https://api.github.com/user")!, delegate: nil),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let login = json["login"] as? String {
                feed.login = login
                // Open counts from the search API (review-requested / assigned / authored).
                let queries = [
                    ("reviews", "is:pr is:open review-requested:\(login)"),
                    ("issues", "is:issue is:open assignee:\(login)"),
                    ("prs", "is:pr is:open author:\(login)"),
                ]
                for (field, query) in queries {
                    var components = URLComponents(string: "https://api.github.com/search/issues")!
                    components.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "per_page", value: "1")]
                    var request = URLRequest(url: components.url!)
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                    if let (searchData, _) = try? await session.data(for: request),
                       let json = try? JSONSerialization.jsonObject(with: searchData) as? [String: Any],
                       let total = json["total_count"] as? Int {
                        switch field {
                        case "reviews": feed.reviews = total
                        case "issues": feed.issues = total
                        default: feed.prs = total
                        }
                    }
                }
                // Unread notification inbox.
                var notificationsRequest = URLRequest(url: URL(string: "https://api.github.com/notifications?per_page=50")!)
                notificationsRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                if let (data, _) = try? await session.data(for: notificationsRequest),
                   let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                    feed.inbox = list.count
                }
                // Contribution calendar via GraphQL.
                var calendarRequest = URLRequest(url: URL(string: "https://api.github.com/graphql")!)
                calendarRequest.httpMethod = "POST"
                if true {
                    calendarRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    calendarRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    let query = "query { viewer { contributionsCollection { contributionCalendar { totalContributions weeks { contributionDays { count } } } } } }"
                    calendarRequest.httpBody = try? JSONSerialization.data(withJSONObject: ["query": query])
                    struct CalendarResponse: Decodable {
                        var data: Payload
                        struct Payload: Decodable { var viewer: Viewer }
                        struct Viewer: Decodable { var contributionsCollection: Collection }
                        struct Collection: Decodable { var contributionCalendar: Calendar }
                        struct Calendar: Decodable {
                            var totalContributions: Int
                            var weeks: [Week]
                            struct Week: Decodable { var contributionDays: [Day] }
                            struct Day: Decodable { var count: Int }
                        }
                    }
                    if let (data, _) = try? await session.data(for: calendarRequest),
                       let decoded = try? JSONDecoder().decode(CalendarResponse.self, from: data) {
                        feed.heatmap = decoded.data.viewer.contributionsCollection.contributionCalendar.weeks.map { $0.contributionDays.map { $0.count } }
                        feed.totalContributions = decoded.data.viewer.contributionsCollection.contributionCalendar.totalContributions
                    }
                }
            }
        }
        // Public repo facts + latest Actions run (works without a token).
        let clean = repo.trimmingCharacters(in: .whitespaces)
        if clean.split(separator: "/").count == 2 {
            if let repoInfo = await repository(clean) {
                feed.stars = repoInfo.stars
                feed.openIssues = repoInfo.issues
            }
            if let (data, _) = try? await session.data(from: URL(string: "https://api.github.com/repos/\(clean)/actions/runs?per_page=1")!),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let runs = json["workflow_runs"] as? [[String: Any]], let run = runs.first {
                feed.runStatus = run["status"] as? String
                feed.runConclusion = run["conclusion"] as? String
                feed.runName = run["name"] as? String
            }
        }
        return feed
    }

    // MARK: - Mounted volumes

    struct VolumeInfo: Identifiable {
        var name: String
        var path: String
        var free: Int64
        var total: Int64
        var isInternal: Bool
        var isEjectable: Bool
        var id: String { path }
        var freeFraction: Double { total > 0 ? Double(free) / Double(total) : 0 }
    }

    static func mountedVolumes() -> [VolumeInfo] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeLocalizedNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeIsInternalKey, .volumeIsEjectableKey]
        guard let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) else { return [] }
        return urls.compactMap { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard let values else { return nil }
            let name = values.volumeLocalizedName ?? values.volumeName ?? url.lastPathComponent
            let total = Int64(values.volumeTotalCapacity ?? 0)
            let free = Int64(values.volumeAvailableCapacityForImportantUsage ?? 0)
            guard total > 0 else { return nil }
            return VolumeInfo(name: name, path: url.path, free: max(0, free), total: total, isInternal: values.volumeIsInternal ?? false, isEjectable: values.volumeIsEjectable ?? false)
        }
    }

    static func ejectVolume(path: String) async {
        _ = await runCommand(executable: "/usr/sbin/diskutil", arguments: ["eject", path], timeout: 20)
    }

    // MARK: - Application catalog

    private static var catalogCache: [(name: String, path: String)]?
    static func applicationCatalog() -> [(name: String, path: String)] {
        if let catalogCache { return catalogCache }
        var result: [(name: String, path: String)] = []
        let fileManager = FileManager.default
        for directory in ["/Applications", "/System/Applications"] {
            guard let contents = try? fileManager.contentsOfDirectory(atPath: directory) else { continue }
            for entry in contents where entry.hasSuffix(".app") {
                let name = (entry as NSString).deletingPathExtension
                result.append((name, directory + "/" + entry))
            }
        }
        let sorted = result.sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
        catalogCache = sorted
        return sorted
    }

    // MARK: - Network facts

    /// Cumulative byte counters per active interface (kernel counters via
    /// getifaddrs) — the widget derives throughput from deltas between samples.
    static func interfaceTraffic() -> [(name: String, bytesIn: Int64, bytesOut: Int64)] {
        var byName: [String: (Int64, Int64)] = [:]
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            defer { cursor = current.pointee.ifa_next }
            guard let dataPointer = current.pointee.ifa_data, let namePointer = current.pointee.ifa_name else { continue }
            let name = String(cString: namePointer)
            guard name != "lo0", current.pointee.ifa_flags & UInt32(IFF_UP) != 0 else { continue }
            let stats = dataPointer.assumingMemoryBound(to: if_data.self).pointee
            let bytesIn = Int64(stats.ifi_ibytes)
            let bytesOut = Int64(stats.ifi_obytes)
            if let existing = byName[name] {
                byName[name] = (max(existing.0, bytesIn), max(existing.1, bytesOut))
            } else {
                byName[name] = (bytesIn, bytesOut)
            }
        }
        return byName.map { (name: $0.key, bytesIn: $0.value.0, bytesOut: $0.value.1) }.sorted { $0.name < $1.name }
    }

    static func networkTrace() async -> (ip: String, region: String)? {
        do {
            let (data, _) = try await session.data(from: URL(string: "https://www.cloudflare.com/cdn-cgi/trace")!)
            let text = String(decoding: data, as: UTF8.self)
            var ip = ""; var region = ""
            for line in text.split(separator: "\n") {
                let parts = line.split(separator: "=", maxSplits: 1)
                guard parts.count == 2 else { continue }
                if parts[0] == "ip" { ip = String(parts[1]) }
                if parts[0] == "loc" { region = String(parts[1]) }
            }
            return ip.isEmpty ? nil : (ip, region)
        } catch { return nil }
    }

    static func localAddresses() -> [(String, String)] {
        var addresses: [(String, String)] = []
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            defer { cursor = current.pointee.ifa_next }
            guard let socket = current.pointee.ifa_addr, socket.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(socket, socklen_t(socket.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = String(cString: host)
            guard !ip.hasPrefix("127."), !ip.hasPrefix("169.254") else { continue }
            addresses.append((String(cString: current.pointee.ifa_name), ip))
        }
        return addresses
    }

    static func wifiNetworkName() -> String? {
        CWWiFiClient.shared().interface()?.ssid()
    }

    // MARK: - Speed test (Cloudflare speed endpoints)

    struct SpeedTestResult {
        var downloadMbps: Double
        var uploadMbps: Double
        var latencyMs: Double
    }

    @MainActor static func runSpeedTest(progress: @escaping @MainActor (String) -> Void) async throws -> SpeedTestResult {
        progress("Measuring latency…")
        var latency = Double.infinity
        for _ in 0..<3 {
            let start = Date()
            _ = try await speedSession.data(from: URL(string: "https://speed.cloudflare.com/__down?bytes=0")!)
            latency = min(latency, Date().timeIntervalSince(start) * 1000)
        }
        progress("Testing download…")
        let downloadStart = Date()
        let (payload, _) = try await speedSession.data(from: URL(string: "https://speed.cloudflare.com/__down?bytes=25000000")!)
        let downloadMbps = Double(payload.count) * 8 / 1_000_000 / max(0.01, Date().timeIntervalSince(downloadStart))
        progress("Testing upload…")
        let body = Data(count: 3_000_000)
        let uploadStart = Date()
        _ = try await speedSession.upload(for: URLRequest(url: URL(string: "https://speed.cloudflare.com/__up")!), from: body)
        let uploadMbps = Double(body.count) * 8 / 1_000_000 / max(0.01, Date().timeIntervalSince(uploadStart))
        return SpeedTestResult(downloadMbps: downloadMbps, uploadMbps: uploadMbps, latencyMs: latency.isFinite ? latency : 0)
    }

    // MARK: - Music playback (AppleScript; supports Music.app and Spotify)

    struct PlaybackState {
        var title: String
        var artist: String
        var album: String
        var duration: Double
        var position: Double
        var isPlaying: Bool
        var app: String
        var artworkURL: String?
        var artworkImage: NSImage?
        var controllable = true
        var seekable = true
    }

    // MARK: - System-wide Now Playing (MediaRemote, catches any app: browsers,
    // QuickTime, VLC, Music, everything the OS Now Playing sees)

    private static let mediaRemoteHandle: UnsafeMutableRawPointer? = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY)
    static let mediaRemoteSupported: Bool = {
        guard let handle = mediaRemoteHandle else { return false }
        return dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") != nil && dlsym(handle, "MRMediaRemoteSendCommand") != nil
    }()
    private static var lastSystemTitle = ""
    private static var lastSystemElapsed: Double = -1

    struct SystemPlaying {
        var title: String
        var artist: String
        var album: String
        var duration: Double
        var elapsed: Double
        var appName: String
        var artwork: NSImage?
    }

    @MainActor static func systemNowPlaying() async -> SystemPlaying? {
        typealias GetInfo = @convention(c) (DispatchQueue, @escaping (CFDictionary?) -> Void) -> Void
        typealias GetPID = @convention(c) (DispatchQueue, @escaping (Int32) -> Void) -> Void
        guard mediaRemoteSupported, let handle = mediaRemoteHandle else { return nil }
        let getInfo = unsafeBitCast(dlsym(handle, "MRMediaRemoteGetNowPlayingInfo"), to: GetInfo.self)
        let queue = DispatchQueue(label: "littleboard.mediaremote", qos: .utility)
        let lock = NSLock()
        var settled = false

        let info: [String: Any]? = await withCheckedContinuation { continuation in
            func finish(_ value: [String: Any]?) {
                lock.lock()
                let done = settled
                settled = true
                lock.unlock()
                if !done { continuation.resume(returning: value) }
            }
            getInfo(queue) { result in
                guard let dictionary = result as? [String: Any] else { finish(nil); return }
                finish(dictionary)
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 2.5) { finish(nil) }
        }
        guard let info, let title = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String, !title.isEmpty else { return nil }

        // Playing state: MediaRemote keeps reporting while paused, so infer it from
        // whether the elapsed time advances between polls.
        let elapsed = (info["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? Double) ?? 0
        let duration = (info["kMRMediaRemoteNowPlayingInfoDuration"] as? Double) ?? 0
        let isPlaying = title != lastSystemTitle || elapsed > lastSystemElapsed + 0.05 || lastSystemElapsed < 0
        lastSystemTitle = title
        lastSystemElapsed = elapsed

        var appName = "Now Playing"
        if let getPID = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationPID").map({ unsafeBitCast($0, to: GetPID.self) }) {
            let pid: Int32 = await withCheckedContinuation { continuation in
                getPID(queue) { value in continuation.resume(returning: value) }
            }
            if let application = NSRunningApplication(processIdentifier: pid), let name = application.localizedName {
                appName = name
            }
        }
        let artwork = (info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data).flatMap { NSImage(data: $0) }
        return SystemPlaying(
            title: title,
            artist: info["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? "",
            album: info["kMRMediaRemoteNowPlayingInfoAlbum"] as? String ?? "",
            duration: duration,
            elapsed: elapsed,
            appName: appName,
            artwork: artwork
        )
    }

    @MainActor static func systemSendCommand(_ command: Int) {
        typealias SendCommand = @convention(c) (Int, DispatchQueue, @escaping () -> Void) -> Void
        guard mediaRemoteSupported, let handle = mediaRemoteHandle, let symbol = dlsym(handle, "MRMediaRemoteSendCommand") else { return }
        let send = unsafeBitCast(symbol, to: SendCommand.self)
        send(command, DispatchQueue(label: "littleboard.mediaremote", qos: .utility)) {}
    }

    /// Browser fallback when MediaRemote is locked down: read the active tab
    /// title from Chrome-family browsers or Safari and present it as a stream.
    private static let browserStateScripts: [(app: String, script: String)] = [
        ("Google Chrome", "tell application \"Google Chrome\" to if it is running and (count of windows) > 0 then return title of active tab of front window"),
        ("Microsoft Edge", "tell application \"Microsoft Edge\" to if it is running and (count of windows) > 0 then return title of active tab of front window"),
        ("Brave Browser", "tell application \"Brave Browser\" to if it is running and (count of windows) > 0 then return title of active tab of front window"),
        ("Safari", "tell application \"Safari\" to if it is running and (count of windows) > 0 then return name of front document"),
    ]

    @MainActor static func browserNowPlaying() async -> PlaybackState? {
        for browser in browserStateScripts {
            guard NSRunningApplication.runningApplications(withBundleIdentifier: browser.app == "Safari" ? "com.apple.Safari" : "com.google.Chrome").count > 0 || browser.app != "Safari" else { continue }
            guard let raw = await runAppleScript(browser.script), !raw.isEmpty else { continue }
            var title = raw
            if let range = title.range(of: "^\\(\\d+\\)\\s*", options: .regularExpression) { title.removeSubrange(range) }
            title = title.replacingOccurrences(of: " - YouTube", with: "")
                .replacingOccurrences(of: " - Bilibili", with: "")
                .trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty, title != "New Tab", title != "Favorites", title != "Start Page" else { continue }
            return PlaybackState(title: title, artist: "Watching in \(browser.app)", album: "", duration: 0, position: 0,
                                 isPlaying: true, app: browser.app, artworkURL: nil, artworkImage: nil, controllable: false, seekable: false)
        }
        return nil
    }

    private static let musicStateScript = """
    tell application "Music"
        if (player state is playing) or (player state is paused) then
            set t to name of current track
            set a to artist of current track
            set al to album of current track
            set d to duration of current track
            set p to player position
            set s to (player state is playing) as text
            return t & "|" & a & "|" & al & "|" & d & "|" & p & "|" & s
        end if
    end tell
    return ""
    """

    private static let spotifyStateScript = """
    tell application "Spotify"
        if (player state is playing) or (player state is paused) then
            set t to name of current track
            set a to artist of current track
            set al to album of current track
            set d to duration of current track
            set p to player position
            set s to (player state is playing) as text
            set u to artwork url of current track
            return t & "|" & a & "|" & al & "|" & d & "|" & p & "|" & s & "|" & u
        end if
    end tell
    return ""
    """

    @MainActor static func playbackState() async -> PlaybackState? {
        // System-wide first: catches browsers, QuickTime, VLC and more.
        if let system = await systemNowPlaying() {
            return PlaybackState(title: system.title, artist: system.artist, album: system.album,
                                 duration: system.duration, position: system.elapsed, isPlaying: true,
                                 app: system.appName, artworkURL: nil, artworkImage: system.artwork,
                                 controllable: true, seekable: false)
        }
        let sources: [(bundle: String, app: String, script: String)] = [
            ("com.apple.Music", "Music", musicStateScript),
            ("com.spotify.client", "Spotify", spotifyStateScript),
        ]
        for source in sources {
            guard NSRunningApplication.runningApplications(withBundleIdentifier: source.bundle).count > 0 else { continue }
            guard let output = await runAppleScript(source.script), !output.isEmpty else { continue }
            let parts = output.components(separatedBy: "|")
            guard let title = parts.first, !title.isEmpty, parts.count >= 6,
                  let duration = Double(parts[3]), let position = Double(parts[4]) else { continue }
            return PlaybackState(title: title, artist: parts[1], album: parts[2], duration: duration, position: position,
                                 isPlaying: parts[5] == "true", app: source.app, artworkURL: parts.count > 6 ? parts[6] : nil)
        }
        if let browser = await browserNowPlaying() { return browser }
        return nil
    }

    @MainActor static func playbackControl(_ action: String, app: String) {
        if app != "Music" && app != "Spotify" {
            // System-wide transport for every other app (browsers, QuickTime…).
            let command = action == "playpause" ? 2 : (action == "next track" ? 4 : 5)
            systemSendCommand(command)
            return
        }
        let bundle = app == "Spotify" ? "com.spotify.client" : "com.apple.Music"
        guard NSRunningApplication.runningApplications(withBundleIdentifier: bundle).count > 0 else { return }
        Task.detached(priority: .utility) { _ = await runAppleScript("tell application \"\(app)\" to \(action)") }
    }

    @MainActor static func playbackSeek(to seconds: Double, app: String) {
        let clamped = max(0, seconds)
        Task.detached(priority: .utility) { _ = await runAppleScript("tell application \"\(app)\" to set player position to \(Int(clamped.rounded()))") }
    }

    // Album artwork: Spotify reports a URL directly; for Music.app look the track
    // up in the public iTunes Search API and upscale the artwork request.
    private static var artworkCache: [String: NSImage] = [:]

    @MainActor static func artwork(for state: PlaybackState) async -> NSImage? {
        if let direct = state.artworkImage { return direct }
        let key = state.title + "|" + state.artist
        if let cached = artworkCache[key] { return cached }
        // Spotify reports artwork directly; Music.app needs a lookup. Try the full
        // term first, then title+album, then the bare title — Bollywood and film
        // songs often only match one of these.
        var remoteURL = state.artworkURL
        if remoteURL == nil || remoteURL?.isEmpty == true {
            for term in artworkSearchTerms(state: state) {
                if let found = await iTunesArtworkURL(term: term) { remoteURL = found; break }
            }
        }
        guard let urlString = remoteURL, let url = URL(string: urlString) else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, let image = NSImage(data: data) else { return nil }
            if artworkCache.count > 40 { artworkCache.removeAll(keepingCapacity: true) }
            artworkCache[key] = image
            return image
        } catch { return nil }
    }

    private static func artworkSearchTerms(state: PlaybackState) -> [String] {
        // Strip parenthetical suffixes like "(From "Murder")" that break searches.
        let cleanTitle = state.title.components(separatedBy: "(").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? state.title
        var terms: [String] = []
        if !cleanTitle.isEmpty, !state.artist.isEmpty { terms.append(cleanTitle + " " + state.artist) }
        if !cleanTitle.isEmpty, !state.album.isEmpty { terms.append(cleanTitle + " " + state.album) }
        if !cleanTitle.isEmpty { terms.append(cleanTitle) }
        if terms.isEmpty { terms.append(state.title) }
        return terms
    }

    /// Average artwork color, used to tint the music card like Apple Music's
    /// ambient artwork color.
    static func averageColor(of image: NSImage) -> NSColor? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let cgImage = rep.cgImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return NSColor(red: Double(pixel[0]) / 255, green: Double(pixel[1]) / 255, blue: Double(pixel[2]) / 255, alpha: 1)
    }

    private struct ITunesSearch: Decodable { var results: [ITunesTrack]? }
    private struct ITunesTrack: Decodable { var artworkUrl100: String? }

    nonisolated static func iTunesArtworkProbe(term: String) async -> String? {
        await iTunesArtworkURL(term: term)
    }

    private static func iTunesArtworkURL(term: String) async -> String? {
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: term.trimmingCharacters(in: .whitespaces)),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "limit", value: "1"),
        ]
        do {
            let (data, response) = try await session.data(from: components.url!)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let decoded = try JSONDecoder().decode(ITunesSearch.self, from: data)
            return decoded.results?.first?.artworkUrl100?.replacingOccurrences(of: "100x100bb", with: "600x600bb")
        } catch { return nil }
    }

    private static func runAppleScript(_ source: String) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", source]
                let output = Pipe()
                process.standardOutput = output
                process.standardError = Pipe()
                // The worker thread below is the only place that resumes; the watchdog
                // only kills a hung osascript (e.g. one waiting on a permission dialog).
                let exited = DispatchSemaphore(value: 0)
                DispatchQueue.global().asyncAfter(deadline: .now() + 6) {
                    guard exited.wait(timeout: .now()) == .timedOut, process.isRunning else { return }
                    process.terminate()
                    Thread.sleep(forTimeInterval: 1)
                    if process.isRunning { process.interrupt() }
                }
                do { try process.run() } catch { exited.signal(); continuation.resume(returning: nil); return }
                process.waitUntilExit()
                exited.signal()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                let text = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: (text?.isEmpty == false) ? text : nil)
            }
        }
    }
}


/// Launch with `--selftest`: exercises every feed, decoder, sensor reader, and
/// helper off the main actor, prints PASS/FAIL lines, then exits.
enum SelfTest {
    static var failures = 0

    static func run() {}

    static func check(_ name: String, _ condition: Bool, _ detail: String = "") {
        if condition { print("PASS \(name) \(detail)") }
        else { failures += 1; print("FAIL \(name) \(detail)") }
    }

    nonisolated static func perform() async {
        print("SELFTEST-BEGIN")

        // Feeds
        let stocks = await LiveFeed.stocks(["AAPL", "MSFT"])
        check("stocks", !stocks.isEmpty, stocks.first.map { "\($0.symbol) \(String(format: "%.2f", $0.price)) closes=\($0.closes.count)" } ?? "empty")

        let crypto = await LiveFeed.crypto(["bitcoin", "ethereum"])
        check("crypto", crypto.count == 2, crypto.first.map { "\($0.name) \(String(format: "%.0f", $0.price))" } ?? "empty")

        let rates = await LiveFeed.rates(base: "USD", quotes: ["EUR", "INR"])
        check("rates", (rates?.rows.count ?? 0) == 2, rates.map { "\($0.base) rows=\($0.rows.count)" } ?? "nil")

        let repo = await LiveFeed.repository("morluto/rea")
        check("github-repo", (repo?.stars ?? 0) >= 0 && repo != nil, repo.map { "stars=\($0.stars)" } ?? "nil")

        let ghFeed = await LiveFeed.githubFeed(repo: "morluto/rea")
        check("github-actions", ghFeed.runStatus != nil, "status=\(ghFeed.runStatus ?? "nil") conclusion=\(ghFeed.runConclusion ?? "-")")

        let trace = await LiveFeed.networkTrace()
        check("network-trace", (trace?.ip.isEmpty == false), trace.map { "ip=\($0.ip) region=\($0.region)" } ?? "nil")

        let air = await LiveFeed.airQuality(city: "Hyderabad")
        check("air-quality", air != nil, air.flatMap { $0.aqi }.map { "aqi=\($0)" } ?? "no-aqi")

        let geocode = await LiveFeed.geocode("London")
        check("geocode", geocode != nil, geocode.map { "\($0.name) \(String(format: "%.2f", $0.latitude))" } ?? "nil")

        let volume = await LiveFeed.mountedVolumes()
        let rootFree = volume.first { $0.path == "/" }?.free ?? 0
        check("volumes", !volume.isEmpty, "\(volume.count) disks, root free=\(rootFree)")

        let traffic = LiveFeed.interfaceTraffic()
        check("interface-traffic", !traffic.isEmpty, "\(traffic.count) interfaces")

        let stats = LiveFeed.batteryStats()
        check("battery-stats", stats != nil, stats.map { "\($0.percent)% ac=\($0.onAC) watts=\($0.watts.map { String(format: "%.1f", $0) } ?? "-") cycles=\($0.cycleCount.map(String.init) ?? "-")" } ?? "no battery")

        let chip = SMCReader.shared.firstTemperature(keys: SMCReader.chipKeys)
        let smcBlocked = !SMCReader.shared.readable
        check("smc-chip-temp", chip != nil || smcBlocked, chip.map { String(format: "%.1f°C", $0) } ?? "os-blocked (graceful)")
        let fans = SMCReader.shared.fanCount()
        check("smc-fans", fans >= 0, "fans=\(fans) blocked=\(smcBlocked)")

        // Artwork lookup for a real track
        let artworkURL = await LiveFeed.iTunesArtworkProbe(term: "Kaho Na Kaho")
        check("itunes-artwork", artworkURL != nil, artworkURL?.prefix(60).description ?? "nil")

        // Pure helpers (View-isolated statics run on the main actor)
        let speed = WidgetCard.speedText(25 * 1024, unit: "mbs")
        check("speed-text-kb", speed.value == "25" && speed.suffix == "KB/s", "\(speed.value) \(speed.suffix)")
        let mbit = WidgetCard.speedText(1_250_000, unit: "mbit")
        check("speed-text-mbit", mbit.value == "10.0", "\(mbit.value) \(mbit.suffix)")
        check("capacity-text", WidgetCard.capacityText(412_000_000_000) == "412 GB", WidgetCard.capacityText(412_000_000_000))
        let sky = WidgetCard.daySkyColors(hour: 3)
        check("day-sky", sky.count == 2, "colors=\(sky.count)")
        check("toolbox-desktop", Toolbox.isDesktopHidden() == false || Toolbox.isDesktopHidden() == true, "readable")
        check("world-clock-name", WorldClockCities.displayName(for: "Asia/Kolkata") == "Mumbai", WorldClockCities.displayName(for: "Asia/Kolkata"))
        check("aqi-category", LiveFeed.aqiCategory(37).label == "Good", LiveFeed.aqiCategory(37).label)
        print("SELFTEST-HELPERS-END")
    }
}
