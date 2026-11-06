import AppKit
import CoreLocation
import Network
import SwiftUI

@MainActor
final class BoardModel: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published var widgets: [WidgetInstance] { didSet { save(); if !savingPanelPosition { syncPanels() } } }
    @Published var theme: BoardTheme = .midnight { didSet { save() } }
    @Published var lookGlassStyle: GlassStyle = .frosted { didSet { save(); syncPanels() } }
    @Published var lookCornerRadius: Double = 22 { didSet { save(); syncPanels() } }
    @Published var uniformColors = true { didSet { save(); syncPanels() } }
    @Published var profileName = "Everyday" { didSet { save() } }
    @Published var profiles: [String] = ["Everyday"] { didSet { save() } }
    @Published var selectedSection: LibrarySection = .all
    @Published var selectedWidget: UUID?
    @Published var widgetSettingsID: UUID?
    @Published var search = ""
    @Published var message: String?
    @Published var networkStatus = "Checking…"
    @Published var networkInterface = ""
    @Published var networkType = ""
    @Published var networkIsExpensive = false
    @Published var locationStatus = ""
    @Published var systemIsDark = true
    @Published var lockScreenSettings = LockScreenSettings() {
        didSet {
            if let data = try? JSONEncoder().encode(lockScreenSettings) { UserDefaults.standard.set(data, forKey: "Littleboard.LockScreenSettings") }
            lockScreenOverlay?.refresh()
        }
    }
    private let networkMonitor = NWPathMonitor()
    private let networkQueue = DispatchQueue(label: "littleboard.network-monitor")
    private let locationManager = CLLocationManager()
    private var locationWidgetID: UUID?
    private var panels: [UUID: DesktopWidgetController] = [:]
    private var isLoading = false
    private var savingPanelPosition = false
    private var saveWorkItem: DispatchWorkItem?
    private var appearanceObserver: NSKeyValueObservation?
    private var lockScreenOverlay: LockScreenOverlayController?

    private var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Littleboard", isDirectory: true)
    }
    private var stateURL: URL { folder.appendingPathComponent("board.json") }

    override init() {
        widgets = []
        super.init()
        locationManager.delegate = self
        load()
        if let data = UserDefaults.standard.data(forKey: "Littleboard.LockScreenSettings"), let saved = try? JSONDecoder().decode(LockScreenSettings.self, from: data) { lockScreenSettings = saved }
        lockScreenOverlay = LockScreenOverlayController(model: self)
        lockScreenOverlay?.startObserving()
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.networkStatus = path.status == .satisfied ? "Connected" : (path.status == .requiresConnection ? "Waiting for connection" : "Offline")
                self?.networkInterface = path.availableInterfaces.first?.name ?? "No active interface"
                self?.networkType = path.availableInterfaces.first.map { Self.interfaceLabel($0.type) } ?? ""
                self?.networkIsExpensive = path.isExpensive
            }
        }
        networkMonitor.start(queue: networkQueue)
        AppUsageMonitor.shared.start()
        // Widgets keep their dark card design, so light mode darkens their
        // backgrounds instead. Watch the system appearance so the switch is live.
        appearanceObserver = NSApp.observe(\.effectiveAppearance, options: [.initial]) { [weak self] application, _ in
            Task { @MainActor in
                let match = application.effectiveAppearance.bestMatch(from: [NSAppearance.Name("NSAppearanceNameAqua"), NSAppearance.Name("NSAppearanceNameDarkAqua")])
                self?.systemIsDark = match == NSAppearance.Name("NSAppearanceNameDarkAqua")
            }
        }
        if widgets.isEmpty {
            widgets = [.init(kind: .clock), .init(kind: .calendar), .init(kind: .weather), .init(kind: .stickyNote)]
            widgets[0].size = .tile2x2
            widgets[1].size = .tile1x1
            widgets[2].size = .tile2x1
            widgets[3].size = .tile2x1
            widgets[3].note = "Make the desktop yours."
        }
        selectedWidget = widgets.first?.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.syncPanels() }
    }

    var filteredKinds: [WidgetKind] {
        let kinds = selectedSection.kinds
        guard !search.isEmpty else { return kinds }
        return kinds.filter { $0.rawValue.localizedCaseInsensitiveContains(search) }
    }
    var current: WidgetInstance? { widgets.first(where: { $0.id == selectedWidget }) }

    func select(_ kind: WidgetKind) {
        if let existing = widgets.first(where: { $0.kind == kind }) { selectedWidget = existing.id }
        else { let item = WidgetInstance(kind: kind); widgets.append(item); selectedWidget = item.id }
    }
    func addCurrentToDesktop() {
        guard let id = selectedWidget, let i = widgets.firstIndex(where: { $0.id == id }) else { return }
        var item = widgets[i]
        let index = widgets.filter(\.isOnDesktop).count
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let offset = Double(index % 5) * 34
        item.isOnDesktop = true
        item.x = visible.minX + 36 + offset
        item.y = visible.maxY - item.size.dimensions.height - 48 - offset
        widgets[i] = item
        syncPanels()
        panels[id]?.bringToFront()
        message = "Added to desktop"
    }
    func removeFromDesktop(_ id: UUID) {
        guard let i = widgets.firstIndex(where: { $0.id == id }) else { return }
        widgets[i].isOnDesktop = false
    }
    func moveWidget(_ id: UUID, dx: Double, dy: Double) {
        guard let i = widgets.firstIndex(where: { $0.id == id }), widgets[i].isOnDesktop, !widgets[i].positionLocked else { return }
        let item = widgets[i]
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: item.x, y: item.y)) }) ?? NSScreen.main
        let bounds = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        widgets[i].x = min(max(item.x + dx, bounds.minX), bounds.maxX - item.size.dimensions.width)
        widgets[i].y = min(max(item.y + dy, bounds.minY), bounds.maxY - item.size.dimensions.height)
    }
    func setWidgetPosition(_ id: UUID, x: Double, y: Double) {
        guard let i = widgets.firstIndex(where: { $0.id == id }), widgets[i].isOnDesktop else { return }
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: widgets[i].x, y: widgets[i].y)) }) ?? NSScreen.main
        let bounds = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        widgets[i].x = min(max(x, bounds.minX), bounds.maxX - widgets[i].size.dimensions.width)
        widgets[i].y = min(max(y, bounds.minY), bounds.maxY - widgets[i].size.dimensions.height)
    }
    func savePanelPosition(_ id: UUID, x: Double, y: Double) {
        guard let i = widgets.firstIndex(where: { $0.id == id }) else { return }
        savingPanelPosition = true
        widgets[i].x = x
        widgets[i].y = y
        savingPanelPosition = false
    }
    func requestWeatherLocation(_ id: UUID) {
        locationWidgetID = id
        locationStatus = "Requesting location access…"
        switch locationManager.authorizationStatus {
        case .notDetermined: locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways: locationManager.requestLocation()
        case .denied, .restricted: locationStatus = "Allow Littleboard in System Settings, or choose a city."
        @unknown default: locationStatus = "Location access is unavailable."
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedAlways { manager.requestLocation() }
        else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted { locationStatus = "Allow Littleboard in System Settings, or choose a city." }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, let id = locationWidgetID else { return }
        CLGeocoder().reverseGeocodeLocation(location) { [weak self] places, _ in
            Task { @MainActor in
                guard let self else { return }
                let place = places?.first
                let name = [place?.locality, place?.administrativeArea].compactMap { $0 }.joined(separator: ", ")
                self.update(id) {
                    $0.weatherUsesCurrentLocation = true
                    $0.weatherLatitude = location.coordinate.latitude
                    $0.weatherLongitude = location.coordinate.longitude
                    $0.weatherLocationName = name.isEmpty ? "Current Location" : name
                }
                self.locationStatus = name.isEmpty ? "Using current location." : "Using \(name)."
            }
        }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationStatus = "Could not get your location. Check location permissions or choose a city."
    }
    func placeWidget(_ id: UUID, anchor: String) {
        guard let i = widgets.firstIndex(where: { $0.id == id }), widgets[i].isOnDesktop else { return }
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: widgets[i].x, y: widgets[i].y)) }) ?? NSScreen.main
        let bounds = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let size = widgets[i].size.dimensions
        let inset: CGFloat = 24
        let x: CGFloat = anchor.contains("Left") ? bounds.minX + inset : anchor.contains("Right") ? bounds.maxX - size.width - inset : bounds.midX - size.width / 2
        let y: CGFloat = anchor.contains("Top") ? bounds.maxY - size.height - inset : anchor.contains("Bottom") ? bounds.minY + inset : bounds.midY - size.height / 2
        setWidgetPosition(id, x: x, y: y)
    }
    func showWidgetSettings(_ id: UUID) {
        selectedWidget = id
        widgetSettingsID = id
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { $0.title == "Littleboard" })?.makeKeyAndOrderFront(nil)
    }
    func timerSeconds(_ id: UUID, at date: Date = .now) -> Int {
        guard let item = widgets.first(where: { $0.id == id }) else { return 0 }
        if item.kind == .stopwatch, item.timerRunning, let started = item.timerEndsAt {
            return max(0, item.timerRemaining + Int(date.timeIntervalSince(started)))
        }
        if item.timerRunning, let end = item.timerEndsAt { return max(0, Int(ceil(end.timeIntervalSince(date)))) }
        return max(0, item.timerRemaining)
    }
    func toggleTimer(_ id: UUID) {
        guard let i = widgets.firstIndex(where: { $0.id == id }) else { return }
        if widgets[i].timerRunning {
            widgets[i].timerRemaining = timerSeconds(id)
            widgets[i].timerEndsAt = nil
            widgets[i].timerRunning = false
        } else {
            if widgets[i].kind == .stopwatch {
                widgets[i].timerEndsAt = Date.now.addingTimeInterval(-TimeInterval(widgets[i].timerRemaining))
            } else {
                if widgets[i].timerRemaining <= 0 { widgets[i].timerRemaining = widgets[i].timerDuration }
                widgets[i].timerEndsAt = Date.now.addingTimeInterval(TimeInterval(widgets[i].timerRemaining))
            }
            widgets[i].timerRunning = true
        }
    }
    func resetTimer(_ id: UUID) {
        guard let i = widgets.firstIndex(where: { $0.id == id }) else { return }
        widgets[i].timerRemaining = widgets[i].kind == .stopwatch ? 0 : widgets[i].timerDuration
        widgets[i].timerEndsAt = nil
        widgets[i].timerRunning = false
    }
    func calculatorPress(_ id: UUID, key: String) {
        guard let i = widgets.firstIndex(where: { $0.id == id }) else { return }
        if key == "AC" { widgets[i].calculatorDisplay = "0"; widgets[i].calculatorStoredValue = nil; widgets[i].calculatorOperation = nil; widgets[i].calculatorStartsNew = false; return }
        if ["+", "−", "×", "÷"].contains(key) {
            widgets[i].calculatorStoredValue = Double(widgets[i].calculatorDisplay)
            widgets[i].calculatorOperation = key
            widgets[i].calculatorStartsNew = true
            return
        }
        if key == "=" {
            guard let lhs = widgets[i].calculatorStoredValue, let rhs = Double(widgets[i].calculatorDisplay), let op = widgets[i].calculatorOperation else { return }
            let result: Double
            switch op { case "+": result = lhs + rhs; case "−": result = lhs - rhs; case "×": result = lhs * rhs; case "÷": result = rhs == 0 ? 0 : lhs / rhs; default: return }
            widgets[i].calculatorDisplay = result.isFinite ? String(format: "%.8g", result) : "0"
            widgets[i].calculatorStoredValue = nil; widgets[i].calculatorOperation = nil; widgets[i].calculatorStartsNew = true
            return
        }
        if key == "." {
            if widgets[i].calculatorStartsNew { widgets[i].calculatorDisplay = "0"; widgets[i].calculatorStartsNew = false }
            if !widgets[i].calculatorDisplay.contains(".") { widgets[i].calculatorDisplay += "." }
            return
        }
        if widgets[i].calculatorStartsNew || widgets[i].calculatorDisplay == "0" { widgets[i].calculatorDisplay = key; widgets[i].calculatorStartsNew = false }
        else if widgets[i].calculatorDisplay.count < 12 { widgets[i].calculatorDisplay += key }
    }
    func toggleReminder(_ id: UUID, index: Int) {
        guard let i = widgets.firstIndex(where: { $0.id == id }), widgets[i].reminderCompleted.indices.contains(index) else { return }
        widgets[i].reminderCompleted[index].toggle()
    }
    func addReminder(_ id: UUID) {
        guard let i = widgets.firstIndex(where: { $0.id == id }) else { return }
        widgets[i].reminderItems.append("New reminder")
        widgets[i].reminderCompleted.append(false)
    }
    func adjustCalendarMonth(_ id: UUID, by amount: Int) {
        guard let i = widgets.firstIndex(where: { $0.id == id }) else { return }
        widgets[i].calendarMonthOffset = min(max(widgets[i].calendarMonthOffset + amount, -120), 120)
    }
    func nextQuote(_ id: UUID) {
        guard let i = widgets.firstIndex(where: { $0.id == id }) else { return }
        widgets[i].quoteIndex = (widgets[i].quoteIndex + 1) % 5
    }
    func update(_ id: UUID, _ change: (inout WidgetInstance) -> Void) {
        guard let i = widgets.firstIndex(where: { $0.id == id }) else { return }
        change(&widgets[i])
    }
    func addProfile() {
        let name = "Profile \(profiles.count + 1)"
        profiles.append(name); profileName = name
    }
    func showLockPreview() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 510, height: 210), styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        panel.title = "Lock Screen Preview"
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: LockScreenPreview(theme: theme))
        panel.center(); panel.makeKeyAndOrderFront(nil)
    }
    func ensureLockScreenWidget(_ option: LockScreenWidgetKind) {
        if !widgets.contains(where: { $0.kind == option.kind }) { widgets.append(WidgetInstance(kind: option.kind)) }
    }
    func setLockScreenWidget(_ option: LockScreenWidgetKind, enabled: Bool) {
        var updated = lockScreenSettings
        if enabled {
            if !updated.widgets.contains(option) { updated.widgets.append(option) }
            ensureLockScreenWidget(option)
        } else {
            updated.widgets.removeAll { $0 == option }
        }
        lockScreenSettings = updated
    }
    func setMessage(_ value: String) {
        message = value
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.message = nil }
    }
    private func load() {
        guard let data = try? Data(contentsOf: stateURL), let saved = try? JSONDecoder().decode(SavedBoard.self, from: data) else { return }
        isLoading = true
        widgets = saved.widgets
        theme = saved.theme
        lookGlassStyle = saved.lookGlassStyle ?? .frosted
        lookCornerRadius = saved.lookCornerRadius ?? 22
        uniformColors = saved.uniformColors ?? true
        profiles = saved.profiles.isEmpty ? ["Everyday"] : saved.profiles
        profileName = saved.profileName
        isLoading = false
    }
    private func save() {
        guard !isLoading else { return }
        // Coalesce bursts (drag moves, typing, usage ticks) into one write.
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.performSave() }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }
    private func performSave() {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let data = try JSONEncoder.pretty.encode(SavedBoard(widgets: widgets, theme: theme, profiles: profiles, profileName: profileName, lookGlassStyle: lookGlassStyle, lookCornerRadius: lookCornerRadius, uniformColors: uniformColors))
            try data.write(to: stateURL, options: .atomic)
        } catch { NSLog("Littleboard could not save its board: %@", error.localizedDescription) }
    }
    private func syncPanels() {
        let active = widgets.filter(\.isOnDesktop)
        let removedIDs = panels.keys.filter { id in !active.contains(where: { $0.id == id }) }
        for id in removedIDs { panels[id]?.close(); panels[id] = nil }
        for item in active {
            if let panel = panels[item.id] { panel.refresh() }
            else { panels[item.id] = DesktopWidgetController(model: self, id: item.id) }
        }
    }
    static func dayStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    static func interfaceLabel(_ type: NWInterface.InterfaceType) -> String {
        switch type {
        case .wifi: return "Wi-Fi"
        case .wiredEthernet: return "Ethernet"
        case .cellular: return "Cellular"
        case .loopback: return "Loopback"
        case .other: return "Network"
        @unknown default: return "Network"
        }
    }
}

private struct SavedBoard: Codable {
    var widgets: [WidgetInstance]
    var theme: BoardTheme
    var profiles: [String]
    var profileName: String
    var lookGlassStyle: GlassStyle? = .frosted
    var lookCornerRadius: Double? = 22
    var uniformColors: Bool? = true
}

private extension JSONEncoder {
    static var pretty: JSONEncoder { let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; return e }
}
