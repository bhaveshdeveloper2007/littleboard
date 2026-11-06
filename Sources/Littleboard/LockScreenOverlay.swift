import AppKit
import CoreGraphics
import CoreBluetooth
import IOBluetooth
import SkyLightWindow
import SwiftUI

@MainActor
final class LockScreenOverlayController {
    private weak var model: BoardModel?
    private var panel: NSPanel?
    private var observers: [NSObjectProtocol] = []
    private var isLocked = false
    private var hasDelegated = false

    init(model: BoardModel) { self.model = model }

    func startObserving() {
        let center = DistributedNotificationCenter.default()
        observers.append(center.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.setLocked(true) }
        })
        observers.append(center.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.setLocked(false) }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.setLocked(false) }
        })
        if let state = CGSessionCopyCurrentDictionary() as? [String: Any] { isLocked = state["CGSSessionScreenIsLocked"] as? Bool ?? false }
        refresh()
    }

    func refresh() {
        guard isLocked, let model, model.lockScreenSettings.enabled, !model.lockScreenSettings.widgets.isEmpty else {
            panel?.orderOut(nil)
            panel?.contentView = nil
            return
        }
        guard let screen = NSScreen.main else { return }
        let width = min(900, screen.frame.width - 48)
        let height: CGFloat = 390
        let horizontal = model.lockScreenSettings.alignment
        let x: CGFloat
        switch horizontal {
        case .leading: x = screen.frame.minX + 24
        case .center: x = screen.frame.midX - width / 2
        case .trailing: x = screen.frame.maxX - width - 24
        }
        let baseY = screen.frame.midY - height / 2
        let y = min(screen.frame.maxY - height - 50, max(screen.frame.minY + 50, baseY + model.lockScreenSettings.verticalOffset))
        let frame = NSRect(x: x, y: y, width: width, height: height)
        let window = ensurePanel()
        window.setFrame(frame, display: true)
        window.contentView = NSHostingView(rootView: LockScreenDashboard(model: model))
        window.orderFrontRegardless()
    }

    func setLocked(_ locked: Bool) {
        isLocked = locked
        if locked { refresh() } else {
            panel?.orderOut(nil)
            panel?.contentView = nil
        }
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let created = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 900, height: 390), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        created.isReleasedWhenClosed = false
        created.isOpaque = false
        created.backgroundColor = .clear
        created.hasShadow = false
        created.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        created.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        created.ignoresMouseEvents = false
        created.isMovable = false
        panel = created
        if !hasDelegated {
            SkyLightOperator.shared.delegateWindow(created)
            hasDelegated = true
        }
        return created
    }
}

struct LockScreenDashboard: View {
    @ObservedObject var model: BoardModel
    private var settings: LockScreenSettings { model.lockScreenSettings }
    private var appearanceIsLight: Bool { settings.appearance == .light || (settings.appearance == .automatic && !model.systemIsDark) }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "101B2C"), Color(hex: "27385B"), Color(hex: "513D74")], startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay(alignment: .bottom) { LinearGradient(colors: [.clear, Color(hex: "10263B").opacity(0.65)], startPoint: .top, endPoint: .bottom) }
            VStack(spacing: 12) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(spacing: 4) {
                        Text(context.date, format: .dateTime.weekday(.wide).month(.wide).day()).font(.system(size: 14, weight: .medium, design: .rounded))
                        Text(context.date, format: .dateTime.hour().minute()).font(.system(size: 56, weight: .light, design: .rounded)).monospacedDigit()
                    }.foregroundStyle(appearanceIsLight ? .black : .white)
                }
                HStack(spacing: 10) { ForEach(settings.widgets) { option in LockScreenMiniWidget(model: model, option: option) } }
                    .frame(maxWidth: .infinity).frame(height: 92)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(.white.opacity(0.34), lineWidth: 1))
        .preferredColorScheme(appearanceIsLight ? .light : .dark)
    }
}

private struct LockScreenMiniWidget: View {
    @ObservedObject var model: BoardModel
    let option: LockScreenWidgetKind
    @State private var music: LiveFeed.PlaybackState?
    @State private var weather: WeatherSnapshot?
    @State private var weatherError = false
    @State private var bluetoothNames: [String] = []
    @State private var bluetoothStatus = "Bluetooth check needed"
    private var settings: LockScreenSettings { model.lockScreenSettings }
    private var widget: WidgetInstance? { model.widgets.first(where: { $0.kind == option.kind }) }
    private var accent: Color { Palette.accent(model.theme) }
    private var foreground: Color { settings.appearance == .light || (settings.appearance == .automatic && !model.systemIsDark) ? .black : .white }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: option.symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(accent)
                Text(option.rawValue.uppercased()).font(.system(size: 7, weight: .bold)).tracking(0.8).lineLimit(1)
                Spacer(minLength: 0)
                Circle().fill(accent).frame(width: 4, height: 4)
            }.foregroundStyle(foreground.opacity(0.78))
            Group {
                switch option {
                case .music: musicContent
                case .timer: timerContent
                case .weather: weatherContent
                case .calendar: calendarContent
                case .reminders: remindersContent
                case .battery: batteryContent
                case .devices: devicesContent
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(glassBackground, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(.white.opacity(settings.glass == .off ? 0.12 : 0.32), lineWidth: 1))
        .task(id: option) {
            if option == .music { music = await LiveFeed.playbackState() }
        }
        .task(id: weatherKey) { if option == .weather { await loadWeather() } }
    }

    private var weatherKey: String { widget.map { "\($0.city)|\($0.weatherLatitude ?? 0)|\($0.weatherLongitude ?? 0)" } ?? "weather" }
    @ViewBuilder private var musicContent: some View {
        if let music {
            VStack(alignment: .leading, spacing: 4) {
                Text(music.title).font(.system(size: 13, weight: .semibold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
                Text(music.artist.isEmpty ? music.app : music.artist).font(.system(size: 8, weight: .medium)).foregroundStyle(foreground.opacity(0.58)).lineLimit(1)
                HStack(spacing: 8) {
                    Button { LiveFeed.playbackControl("previous track", app: music.app) } label: { Image(systemName: "backward.end.fill") }
                    Button { LiveFeed.playbackControl("playpause", app: music.app) } label: { Image(systemName: music.isPlaying ? "pause.fill" : "play.fill") }
                    Button { LiveFeed.playbackControl("next track", app: music.app) } label: { Image(systemName: "forward.end.fill") }
                }.buttonStyle(.plain).font(.system(size: 9, weight: .semibold)).foregroundStyle(accent)
            }
        } else { Text("Nothing playing").font(.system(size: 12, weight: .medium)).foregroundStyle(foreground.opacity(0.68)) }
    }
    private var timerContent: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 4) {
                Text(timerText(model.timerSeconds(widget?.id ?? UUID(), at: context.date))).font(.system(size: 20, weight: .light, design: .rounded)).monospacedDigit()
                Button { if let id = widget?.id { model.toggleTimer(id) } } label: { Label(widget?.timerRunning == true ? "Pause" : "Start", systemImage: widget?.timerRunning == true ? "pause.fill" : "play.fill") }
                    .buttonStyle(.plain).font(.system(size: 8, weight: .semibold)).foregroundStyle(accent)
            }
        }
    }
    @ViewBuilder private var weatherContent: some View {
        if settings.weatherStyle == .circular {
            HStack(spacing: 10) {
                Image(systemName: WidgetCard.weatherSymbol(weather?.currentCode ?? 1)).font(.system(size: 22)).foregroundStyle(Color(hex: "FFD781"))
                VStack(alignment: .leading, spacing: 1) { Text(weather.map { WidgetCard.weatherTemperature($0.temperature, unit: widget?.weatherUnit ?? .auto) } ?? (weatherError ? "Unavailable" : "Loading")).font(.system(size: 22, weight: .light, design: .rounded)); Text(weather.map { WidgetCard.weatherDescription($0.currentCode) } ?? (weatherError ? "Check your connection" : "Forecast")).font(.system(size: 7)).foregroundStyle(foreground.opacity(0.64)).lineLimit(1) }
            }
        } else {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: WidgetCard.weatherSymbol(weather?.currentCode ?? 1)).font(.system(size: 22)).foregroundStyle(Color(hex: "FFD781"))
                VStack(alignment: .leading, spacing: 2) {
                    Text(weather.map { WidgetCard.weatherTemperature($0.temperature, unit: widget?.weatherUnit ?? .auto) } ?? (weatherError ? "Unavailable" : "Loading")).font(.system(size: 18, weight: .light, design: .rounded)).lineLimit(1).minimumScaleFactor(0.6)
                    Text(weather?.location ?? widget?.city ?? "Weather").font(.system(size: 8, weight: .medium)).foregroundStyle(foreground.opacity(0.64)).lineLimit(1)
                }
                Spacer(minLength: 0)
                if let weather { VStack(alignment: .trailing, spacing: 3) { Text("H \(WidgetCard.weatherTemperature(weather.high, unit: widget?.weatherUnit ?? .auto))").font(.system(size: 7)); Text("L \(WidgetCard.weatherTemperature(weather.low, unit: widget?.weatherUnit ?? .auto))").font(.system(size: 7)).foregroundStyle(foreground.opacity(0.58)) } }
            }
        }
    }
    private var calendarContent: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) { Text(Date.now.formatted(.dateTime.month(.abbreviated))).font(.system(size: 8, weight: .bold)).foregroundStyle(foreground.opacity(0.6)); Text(Date.now.formatted(.dateTime.day())).font(.system(size: 24, weight: .light, design: .rounded)) }
            VStack(alignment: .leading, spacing: 3) { Text("UPCOMING").font(.system(size: 7, weight: .bold)).tracking(0.7).foregroundStyle(accent); Text("Open Calendar to see events").font(.system(size: 8, weight: .medium)).foregroundStyle(foreground.opacity(0.66)).lineLimit(2); Button("Open Calendar") { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app")) }.buttonStyle(.plain).font(.system(size: 7, weight: .semibold)).foregroundStyle(accent) }
        }
    }
    private var remindersContent: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array((widget?.reminderItems ?? ["No reminders yet"]).prefix(2).enumerated()), id: \.offset) { index, title in
                HStack(spacing: 5) { Image(systemName: widget?.reminderCompleted.indices.contains(index) == true && widget!.reminderCompleted[index] ? "checkmark.circle.fill" : "circle").font(.system(size: 8)).foregroundStyle(accent); Text(title).font(.system(size: 8, weight: .medium)).lineLimit(1) }.foregroundStyle(foreground.opacity(0.8))
            }
        }
    }
    private var batteryContent: some View {
        let status = LiveFeed.batteryStats()
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) { Text(status.map { "\($0.percent)%" } ?? "—").font(.system(size: 22, weight: .light, design: .rounded)); if status?.charging == true { Image(systemName: "bolt.fill").font(.system(size: 9)).foregroundStyle(accent) } }
            ProgressView(value: Double(status?.percent ?? 0), total: 100).tint(accent)
            Text(status?.charging == true ? "Charging" : (status?.onAC == true ? "AC Power" : (status != nil ? "On battery" : "Battery status unavailable"))).font(.system(size: 7, weight: .medium)).foregroundStyle(foreground.opacity(0.62)).lineLimit(1)
        }
    }
    private var devicesContent: some View {
        VStack(alignment: .leading, spacing: 3) {
            if bluetoothStatus == "Bluetooth check needed" {
                Button("Check Bluetooth") { checkBluetoothAccess() }.font(.system(size: 8, weight: .semibold)).buttonStyle(.plain).foregroundStyle(accent)
            } else if bluetoothNames.isEmpty { Text(bluetoothStatus).font(.system(size: 8, weight: .medium)).foregroundStyle(foreground.opacity(0.65)).lineLimit(2) }
            else { ForEach(bluetoothNames, id: \.self) { name in Label(name, systemImage: "headphones").font(.system(size: 8, weight: .medium)).foregroundStyle(foreground.opacity(0.78)).lineLimit(1) } }
        }
    }
    private func checkBluetoothAccess() {
        guard Bundle.main.object(forInfoDictionaryKey: "NSBluetoothAlwaysUsageDescription") as? String != nil else {
            bluetoothStatus = "Bluetooth permission needs an app update"
            return
        }
        guard CBCentralManager.authorization == .allowedAlways else {
            bluetoothStatus = CBCentralManager.authorization == .denied ? "Allow Bluetooth in System Settings" : "Bluetooth permission unavailable"
            return
        }
        bluetoothNames = ((IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []).filter { $0.isConnected() }.prefix(2).map(\.nameOrAddress)
        bluetoothStatus = bluetoothNames.isEmpty ? "No connected devices" : ""
    }
    private var glassBackground: some ShapeStyle {
        switch settings.glass {
        case .off: return AnyShapeStyle(Color(hex: "151B26").opacity(0.92))
        case .frosted: return AnyShapeStyle(.ultraThinMaterial)
        case .clear: return AnyShapeStyle(Color.white.opacity(0.08))
        case .liquid: return AnyShapeStyle(.thinMaterial)
        }
    }
    private func loadWeather() async {
        guard let widget else { return }
        let latitude = widget.weatherUsesCurrentLocation ? widget.weatherLatitude : nil
        let longitude = widget.weatherUsesCurrentLocation ? widget.weatherLongitude : nil
        do { weather = try await WidgetCard.fetchWeather(city: widget.city, latitude: latitude, longitude: longitude, locationName: widget.weatherLocationName); weatherError = false }
        catch { weather = nil; weatherError = true }
    }
    private func timerText(_ seconds: Int) -> String { String(format: "%d:%02d", max(0, seconds) / 60, max(0, seconds) % 60) }
}
