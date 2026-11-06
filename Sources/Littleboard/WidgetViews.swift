import AppKit
import EventKit
import IOKit.ps
import SwiftUI
import WebKit

private struct CalendarEventEntry: Identifiable {
    let id: String
    let title: String
    let date: Date
    let endDate: Date
    let isAllDay: Bool
    let colorHex: String?
}

struct WidgetCard: View {
    private static let sessionStartedAt = Date.now
    @ObservedObject var model: BoardModel
    let id: UUID?
    let desktop: Bool
    @State private var clipboardText: String?
    @State private var breathingStartedAt: Date?
    @State private var weatherReading: WeatherSnapshot?
    @State private var weatherError: String?
    @State private var stocksQuotes: [LiveFeed.StockQuote]?
    @State private var stocksError: String?
    @State private var cryptoPrices: [LiveFeed.CryptoPrice]?
    @State private var cryptoError: String?
    @State private var rateRows: [(String, Double)]?
    @State private var ratesDate: String?
    @State private var ratesError: String?
    @State private var repo: LiveFeed.RepoInfo?
    @State private var repoError: String?
    @State private var speedState: SpeedTestState = .idle
    @State private var externalIP: String?
    @State private var externalRegion: String?
    @State private var localIPs: [(String, String)] = []
    @State private var wifiName: String?
    @State private var downSpeed: Double = 0
    @State private var upSpeed: Double = 0
    @State private var availableInterfaces: [String] = []
    @State private var airReading: LiveFeed.AirQualitySnapshot?
    @State private var airError: String?
    @State private var playback: LiveFeed.PlaybackState?
    @State private var playbackUpdatedAt = Date.now
    @State private var artwork: NSImage?
    @State private var artworkTint: NSColor?
    @State private var batteryLowPower = false
    @State private var bluetoothBatteries: [LiveFeed.BluetoothDeviceBattery] = []
    @State private var toolboxMuted = false
    @State private var toolboxDesktopHidden = false
    @State private var toolboxHiddenFiles = false
    @State private var pairedDevices: [LiveFeed.PairedDeviceInfo] = []
    @State private var githubFeedData = LiveFeed.GitHubFeed()
    @State private var mountedVolumes: [LiveFeed.VolumeInfo] = []
    @State private var hoveredVolume: String?
    @State private var calendarEvents: [CalendarEventEntry] = []
    @State private var calendarEventsMessage = ""
    @State private var calendarEventDays: Set<Int> = []
    var onMove: ((CGSize) -> Void)? = nil
    var onDragEnd: (() -> Void)? = nil
    var glassOverride: GlassStyle? = nil
    private var item: WidgetInstance? { model.widgets.first(where: { $0.id == id }) }
    private var weatherTaskKey: String? {
        guard let item, item.kind == .weather else { return nil }
        let latitude = item.weatherLatitude.map { String($0) } ?? ""
        let longitude = item.weatherLongitude.map { String($0) } ?? ""
        return item.city + "|" + latitude + "|" + longitude + "|" + String(item.weatherUsesCurrentLocation)
    }
    private var stocksTaskKey: String? {
        guard let item, item.kind == .stocks else { return nil }
        return "stocks|" + item.stocksSymbols.joined(separator: ",")
    }
    private var cryptoTaskKey: String? {
        guard let item, item.kind == .crypto else { return nil }
        return "crypto|" + item.cryptoCoins.joined(separator: ",")
    }
    private var ratesTaskKey: String? {
        guard let item, item.kind == .currencies else { return nil }
        return "rates|" + item.currencyBase + "|" + item.currencyQuotes.joined(separator: ",")
    }
    private var repoTaskKey: String? {
        guard let item, item.kind == .github else { return nil }
        return "repo|" + item.githubRepo
    }
    private var airTaskKey: String? {
        guard let item, item.kind == .airQuality else { return nil }
        return "air|" + item.city
    }
    private var networkTaskKey: String? {
        guard let item, item.kind == .network else { return nil }
        return "network|\(item.networkInterfaceFilter)"
    }
    private var musicTaskKey: String? {
        guard let item, [.music, .audio, .soundMixer, .ambientSound].contains(item.kind) else { return nil }
        return "music"
    }
    private var batteryTaskKey: String? {
        guard let item, item.kind == .battery else { return nil }
        return "battery|\(item.batteryStyle.rawValue)"
    }
    private var calendarTaskKey: String? {
        guard let item, item.kind == .calendar else { return nil }
        return "calendar|\(item.calendarMonthOffset)"
    }
    private var toolboxTaskKey: String? {
        guard let item, item.kind == .toolbox else { return nil }
        return "toolbox"
    }
    private var devicesTaskKey: String? {
        guard let item, item.kind == .devices else { return nil }
        return "devices|\(item.deviceSort)|\(item.showDisconnectedDevices)"
    }
    private var disksTaskKey: String? {
        guard let item, item.kind == .disks else { return nil }
        return "disks|\(item.disksShowAll)"
    }
    private var activityTaskKey: String? {
        guard let item, item.kind == .activity else { return nil }
        return "activity|\(item.showProgramList)"
    }
    private var narrow: Bool { item.map { $0.size == .tile1x1 || $0.size == .tile1x2 || $0.size == .small } ?? false }
    private var tiny: Bool { item.map { $0.size == .tile1x1 || $0.size == .small } ?? false }
    private var tall: Bool { item.map { $0.size == .tile1x2 || $0.size == .tile2x3 } ?? false }
    private var wide: Bool { item.map { [.tile2x1, .tile3x1].contains($0.size) } ?? false }
    private var veryWide: Bool { item.map { $0.size == .tile3x1 || $0.size == .tile3x2 } ?? false }
    private var expanded: Bool { item.map { [.tile2x2, .tile2x3, .tile3x2, .large].contains($0.size) } ?? false }
    private var accentColor: Color {
        if item?.kind == .calendar, let hex = item?.calendarAppearanceColor.hex { return Color(hex: hex) }
        return item?.accentStyle.hex.map(Color.init(hex:)) ?? Palette.accent(model.theme)
    }
    private var calendarFontDesign: Font.Design {
        switch item?.calendarAppearanceFont { case .system: return .default; case .mono: return .monospaced; case .serif: return .serif; default: return .rounded }
    }
    private var effectiveGlassStyle: GlassStyle {
        if let glassOverride { return glassOverride }
        guard let item else { return model.lookGlassStyle }
        return item.glassStyle == .off ? model.lookGlassStyle : item.glassStyle
    }
    private var effectiveCornerRadius: CGFloat { CGFloat(model.lookCornerRadius) }
    var body: some View {
        Group {
            if let item { content(item) }
            else { placeholder }
        }
        .padding(item?.kind == .calculator ? 10 : 16)
        .scaleEffect(item?.kind == .calendar ? CGFloat(item?.calendarScale ?? 1) : 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: effectiveCornerRadius, style: .continuous))
        .overlay(cardOverlay)
        // Desktop panels get their shadow from the window server (hasShadow on the
        // NSPanel). A SwiftUI shadow here would be clipped at the panel edge and
        // read as a dark rim around the rounded corners.
        .shadow(color: .black.opacity(desktop ? 0 : 0.18), radius: 16, y: 6)
        .task(id: weatherTaskKey) {
            guard let item, item.kind == .weather else { return }
            while !Task.isCancelled {
                await loadWeather(for: item)
                try? await Task.sleep(for: .seconds(weatherReading == nil ? 60 : 600))
            }
        }
        .task(id: stocksTaskKey) {
            guard let item, item.kind == .stocks else { return }
            while !Task.isCancelled {
                await loadStocks(item)
                try? await Task.sleep(for: .seconds(stocksQuotes?.isEmpty == false ? 300 : 60))
            }
        }
        .task(id: cryptoTaskKey) {
            guard let item, item.kind == .crypto else { return }
            while !Task.isCancelled {
                await loadCrypto(item)
                try? await Task.sleep(for: .seconds(cryptoPrices?.isEmpty == false ? 300 : 60))
            }
        }
        .task(id: ratesTaskKey) {
            guard let item, item.kind == .currencies else { return }
            while !Task.isCancelled {
                await loadRates(item)
                try? await Task.sleep(for: .seconds(rateRows?.isEmpty == false ? 1800 : 60))
            }
        }
        .task(id: repoTaskKey) {
            guard let item, item.kind == .github else { return }
            while !Task.isCancelled {
                await loadRepo(item)
                githubFeedData = await LiveFeed.githubFeed(repo: item.githubRepo)
                try? await Task.sleep(for: .seconds(600))
            }
        }
        .task(id: airTaskKey) {
            guard let item, item.kind == .airQuality else { return }
            while !Task.isCancelled {
                await loadAirQuality(item)
                try? await Task.sleep(for: .seconds(airReading != nil ? 1800 : 60))
            }
        }
        .task(id: networkTaskKey) {
            guard let item, item.kind == .network else { return }
            let filter = item.networkInterfaceFilter
            var lastCounters: [String: (Int64, Int64)] = [:]
            var lastSampleDate = Date.now
            var tick = 0
            while !Task.isCancelled {
                let samples = LiveFeed.interfaceTraffic()
                let now = Date.now
                let elapsed = now.timeIntervalSince(lastSampleDate)
                if elapsed >= 0.5 {
                    var deltaIn: Int64 = 0
                    var deltaOut: Int64 = 0
                    for sample in samples where filter == "all" || sample.name == filter {
                        let previous = lastCounters[sample.name]
                        deltaIn += max(0, sample.bytesIn - (previous?.0 ?? sample.bytesIn))
                        deltaOut += max(0, sample.bytesOut - (previous?.1 ?? sample.bytesOut))
                    }
                    downSpeed = Double(deltaIn) / elapsed
                    upSpeed = Double(deltaOut) / elapsed
                    lastCounters = Dictionary(uniqueKeysWithValues: samples.map { ($0.name, ($0.bytesIn, $0.bytesOut)) })
                    lastSampleDate = now
                    availableInterfaces = samples.map { $0.name }
                }
                tick += 1
                if tick % 300 == 1 { await loadNetworkFacts() }
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .task(id: musicTaskKey) {
            guard let item, [.music, .audio, .soundMixer, .ambientSound].contains(item.kind) else { return }
            while !Task.isCancelled {
                let state = await LiveFeed.playbackState()
                playbackUpdatedAt = .now
                let trackChanged = state.map { $0.title != playback?.title || $0.artist != playback?.artist || $0.app != playback?.app } ?? (playback != nil)
                playback = state
                if trackChanged {
                    artwork = nil
                    artworkTint = nil
                    if let state {
                        artwork = await LiveFeed.artwork(for: state)
                        artworkTint = artwork.flatMap(LiveFeed.averageColor(of:))
                    }
                }
                try? await Task.sleep(for: .seconds(3))
            }
        }
        .task(id: batteryTaskKey) {
            guard let item, item.kind == .battery else { return }
            while !Task.isCancelled {
                batteryLowPower = await LiveFeed.lowPowerModeEnabled()
                if item.batteryStyle == .devices {
                    bluetoothBatteries = await LiveFeed.bluetoothBatteryDevices()
                }
                try? await Task.sleep(for: .seconds(300))
            }
        }
        .task(id: calendarTaskKey) {
            guard let item, item.kind == .calendar else { return }
            while !Task.isCancelled {
                await loadCalendarEvents()
                try? await Task.sleep(for: .seconds(calendarEvents.isEmpty ? 60 : 300))
            }
        }
        .task(id: toolboxTaskKey) {
            guard let item, item.kind == .toolbox else { return }
            while !Task.isCancelled {
                toolboxMuted = await Toolbox.isMuted()
                toolboxDesktopHidden = Toolbox.isDesktopHidden()
                toolboxHiddenFiles = Toolbox.isShowingHiddenFiles()
                try? await Task.sleep(for: .seconds(30))
            }
        }
        .task(id: devicesTaskKey) {
            guard let item, item.kind == .devices else { return }
            var batteryLevels: [String: Int] = [:]
            var ticks = 0
            while !Task.isCancelled {
                if ticks % 12 == 0 {
                    batteryLevels = Dictionary(await LiveFeed.bluetoothBatteryDevices().map { ($0.name, $0.percent) }, uniquingKeysWith: { first, _ in first })
                }
                pairedDevices = LiveFeed.pairedBluetoothDevices(batteryLevels: batteryLevels)
                ticks += 1
                try? await Task.sleep(for: .seconds(10))
            }
        }
        .task(id: disksTaskKey) {
            guard let item, item.kind == .disks else { return }
            while !Task.isCancelled {
                mountedVolumes = LiveFeed.mountedVolumes()
                try? await Task.sleep(for: .seconds(15))
            }
        }
        .task(id: activityTaskKey) {
            guard let item, item.kind == .activity else { return }
            let monitor = SystemMonitor.shared
            monitor.retainSampler()
            defer { monitor.releaseSampler() }
            for await sample in monitor.$sample.values {
                if let sample { activitySample = sample }
            }
        }
        .simultaneousGesture(DragGesture(minimumDistance: 4).onChanged { value in
            guard desktop, item?.positionLocked == false else { return }
            // Cumulative translation; the controller keeps the delta bookkeeping so
            // no view state is written per event (that re-rendered the card mid-drag).
            onMove?(value.translation)
        }.onEnded { _ in onDragEnd?() })
        .contextMenu {
            if let item {
                Button("Widget Settings…", systemImage: "slider.horizontal.3") { model.showWidgetSettings(item.id) }
                Menu("Size") {
                    ForEach([WidgetSize.tile1x1, .tile1x2, .tile2x1, .tile2x2, .tile2x3, .tile3x1, .tile3x2]) { size in
                        Button { model.update(item.id) { $0.size = size } } label: {
                            if item.size == size { Label(size.rawValue, systemImage: "checkmark") }
                            else { Text(size.rawValue) }
                        }
                    }
                }
                Menu("Glass") {
                    ForEach(GlassStyle.allCases) { style in
                        Button { model.update(item.id) { $0.glassStyle = style } } label: {
                            if item.glassStyle == style { Label(style.rawValue, systemImage: "checkmark") }
                            else { Text(style.rawValue) }
                        }
                    }
                }
                Button(item.positionLocked ? "Unlock Position" : "Lock Position", systemImage: item.positionLocked ? "lock.open" : "lock") {
                    model.update(item.id) { $0.positionLocked.toggle() }
                }
                Divider()
                Button("Remove Widget", systemImage: "minus") { model.removeFromDesktop(item.id) }
            }
        }
    }
    private var cardOverlay: some View {
        let glass = effectiveGlassStyle
        return ZStack {
            RoundedRectangle(cornerRadius: effectiveCornerRadius, style: .continuous).stroke(.white.opacity(glass == .frosted || glass == .liquid ? 0.42 : 0.10), lineWidth: 1)
            if glass == .frosted || glass == .liquid {
                RoundedRectangle(cornerRadius: max(0, effectiveCornerRadius - 1), style: .continuous)
                    .stroke(LinearGradient(colors: [.white.opacity(0.42), .white.opacity(0.025), .white.opacity(glass == .liquid ? 0.32 : 0.16)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1).padding(1)
                VStack(spacing: 0) {
                    LinearGradient(colors: [.white.opacity(glass == .liquid ? 0.34 : 0.20), .white.opacity(0.035), .clear], startPoint: .top, endPoint: .bottom).frame(height: 34)
                    Spacer(minLength: 0)
                }.clipShape(RoundedRectangle(cornerRadius: effectiveCornerRadius, style: .continuous)).blendMode(.screen)
            }
        }.allowsHitTesting(false)
    }
    private static func mixColors(_ base: Color, _ tint: Color, _ amount: Double) -> Color {
        guard let a = NSColor(base).usingColorSpace(.sRGB), let b = NSColor(tint).usingColorSpace(.sRGB) else { return base }
        let red = a.redComponent + (b.redComponent - a.redComponent) * amount
        let green = a.greenComponent + (b.greenComponent - a.greenComponent) * amount
        let blue = a.blueComponent + (b.blueComponent - a.blueComponent) * amount
        return Color(red: Double(red), green: Double(green), blue: Double(blue))
    }
    private var background: some View {
        let kind = item?.kind
        let colors: [Color]
        if kind == .dayProgress, item?.dayProgressColors == "sky" {
            let calendar = Calendar.current
            let hour = Double(calendar.component(.hour, from: dayClockTick)) + Double(calendar.component(.minute, from: dayClockTick)) / 60
            colors = Self.daySkyColors(hour: hour)
        } else {
        switch kind {
        case .clock, .simpleClock, .flipClock, .wordClock: colors = [Color(hex: "27334A"), Color(hex: "151C2A")]
        case .weather, .airQuality: colors = [Color(hex: "284A68"), Color(hex: "142334")]
        case .calendar, .reminders, .stickyNote, .custom: colors = [Color(hex: "3E3827"), Color(hex: "211F19")]
        case .music, .audio, .soundMixer, .ambientSound:
            if let tint = artworkTint {
                colors = [Self.mixColors(Color(hex: "443052"), Color(nsColor: tint), 0.65), Self.mixColors(Color(hex: "211A2B"), Color(nsColor: tint), 0.4)]
            } else {
                colors = [Color(hex: "443052"), Color(hex: "211A2B")]
            }
        case .battery, .system, .temperature, .devices, .activity, .appTime: colors = [Color(hex: "285044"), Color(hex: "14251F")]
        case .worldMap, .worldClock, .moon, .starfield: colors = [Color(hex: "263C46"), Color(hex: "131F2B")]
        case .timer, .stopwatch, .pomodoro, .countdown: colors = [Color(hex: "4A332D"), Color(hex: "241B1B")]
        case .stocks, .crypto, .currencies, .speedTest, .network: colors = [Color(hex: "29453E"), Color(hex: "152420")]
        default: colors = [Color(hex: "343A32"), Color(hex: "191C18")]
        }
        }
        // Per-widget transparency level. The weather widget's transparent mode is
        // already see-through by design and keeps its own backdrop handling.
        let level: Double
        if kind == .weather, item?.weatherBackground == .transparent { level = 1 }
        else if effectiveGlassStyle == .solidDark || effectiveGlassStyle == .solidLight { level = 1 }
        else { level = item?.backgroundOpacity ?? 1 }
        // Light mode compensation: white-on-dark text is the design, so when the
        // system is in light mode a dark scrim keeps the card legible behind the
        // transparent layers. Zero in dark mode, and off for styles that are
        // transparent on purpose (clear glass, weather transparent mode).
        let scrim: Double
        if effectiveGlassStyle == .solidLight { scrim = 0.45 }
        else if effectiveGlassStyle == .solidDark { scrim = 0 }
        else if model.systemIsDark { scrim = 0 }
        else if effectiveGlassStyle == .clear { scrim = 0 }
        else if kind == .weather, item?.weatherBackground == .transparent { scrim = 0 }
        else if let item {
            let base = (1 - item.backgroundOpacity) * 0.65
            let material = effectiveGlassStyle == .frosted || effectiveGlassStyle == .liquid
            scrim = material ? max(0.38, base) : base
        } else { scrim = 0 }
        return ZStack {
            if effectiveGlassStyle == .solidDark {
                Color.black.opacity(0.88)
            } else if effectiveGlassStyle == .solidLight {
                Color.white.opacity(0.88)
            } else if effectiveGlassStyle == .frosted {
                Rectangle().fill(.ultraThinMaterial).overlay(LinearGradient(colors: [colors[0].opacity(0.45), colors[1].opacity(0.70)], startPoint: .topLeading, endPoint: .bottomTrailing))
            } else if effectiveGlassStyle == .clear {
                Color.clear
            } else if effectiveGlassStyle == .liquid {
                Rectangle().fill(.thinMaterial).overlay(LinearGradient(colors: [colors[0].opacity(0.38), colors[1].opacity(0.48)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(alignment: .topLeading) { Ellipse().fill(.white.opacity(0.12)).frame(width: 260, height: 90).blur(radius: 28).offset(x: -55, y: -55) }
            } else if kind == .weather, item?.weatherBackground == .transparent {
                Color.clear
                if item?.weatherBackdrop != WeatherBackdrop.none { WeatherGlow(opacity: item?.weatherBackdrop == .full ? 0.34 : 0.14) }
            } else {
                if kind == .weather, item?.weatherBackground == .sky {
                    let code = Self.weatherSceneCode(weatherReading?.currentCode ?? 1, scene: item?.weatherScene ?? .auto, isDay: weatherReading?.isDay ?? true)
                    LinearGradient(colors: Self.weatherSkyColors(code: code), startPoint: .topLeading, endPoint: .bottomTrailing)
                } else { LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing) }
                RadialGradient(colors: [colors[0].opacity(0.35), .clear], center: .topTrailing, startRadius: 0, endRadius: 250)
                if kind == .weather, item?.weatherBackdrop != WeatherBackdrop.none { WeatherGlow(opacity: item?.weatherBackdrop == .full ? 0.34 : 0.14) }
            }
        }
        .opacity(level)
        .overlay(colors[1].opacity(scrim).allowsHitTesting(false))
    }

    @ViewBuilder private func content(_ item: WidgetInstance) -> some View {
        switch item.kind {
        case .clock, .simpleClock, .flipClock, .wordClock:
            clock(item)
        case .countdown:
            countdownCard
        case .calendar:
            calendar
                .contentShape(Rectangle())
                .onTapGesture { performCalendarClick(item) }
        case .weather:
            weather(item)
        case .stickyNote, .custom:
            note(item)
        case .quote:
            quote
        case .dayProgress:
            dayProgressCard
        case .yearProgress:
            progress(item.kind)
        case .worldClock:
            worldClock
        case .battery:
            batteryCard
        case .temperature:
            temperatureCard
        case .devices:
            devicesCard
        case .activity:
            activityCard
        case .system:
            systemCard(item.kind)
        case .appTime:
            appTimeCard
        case .timer, .stopwatch, .pomodoro:
            timer(item.kind)
        case .calculator:
            calculator
        case .unitConverter:
            metric(item.kind, value: "1 km", detail: "0.62 miles · sample conversion")
        case .network:
            networkCard
        case .speedTest:
            speedTestCard
        case .stocks:
            stocksCard
        case .crypto:
            cryptoCard
        case .currencies:
            currenciesCard
        case .github:
            githubCard
        case .music, .audio, .soundMixer, .ambientSound:
            musicCard(item.kind)
        case .worldMap:
            map
        case .moon:
            moonCard
        case .starfield:
            stars
        case .companion:
            companion
        case .photos, .mirror:
            mediaCard(item.kind)
        case .reminders:
            reminders
        case .disks:
            disksCard
        case .trash, .folder, .dropZone:
            fileUtilityCard(item.kind)
        case .terminal:
            terminal
        case .airQuality:
            airQualityCard
        case .toolbox:
            toolboxCard
        case .apps:
            appsCard
        case .shortcut:
            quickActionsCard(item.kind)
        case .smartHome:
            metric(item.kind, value: "Home", detail: "Open the Home app to manage accessories")
        case .webPage:
            webPageCard(item)
        case .clipboard:
            clipboard
        case .passwordGenerator:
            passwordCard
        case .widgetStack:
            stack(item)
        }
    }

    private func header(_ name: String, _ symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(model.uniformColors ? Palette.accent(model.theme) : accentColor).frame(width: 25, height: 25).background(iconTileFill, in: RoundedRectangle(cornerRadius: 8))
            Text(name).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.9))
            Spacer(minLength: 2)
            Circle().fill(.white.opacity(0.22)).frame(width: 4, height: 4)
        }
    }
    private var iconTileFill: Color {
        switch effectiveGlassStyle {
        case .solidDark: return Color.black.opacity(0.32)
        case .solidLight: return Color.white.opacity(0.22)
        case .clear: return .clear
        default: return .white.opacity(0.07)
        }
    }
    @ViewBuilder private func clock(_ item: WidgetInstance) -> some View {
        TimelineView(.periodic(from: .now, by: item.showSeconds ? 1 : 30)) { context in
            clockContent(item, date: context.date)
        }
    }
    @ViewBuilder private func clockMinimalContent(_ item: WidgetInstance, date: Date, timeZone: TimeZone, accent: Color, timeSize: CGFloat, showTZ: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Self.digitalTime(date, use24Hour: item.use24Hour, seconds: item.showSeconds, timeZone: timeZone))
                .font(.system(size: timeSize, weight: .ultraLight, design: .rounded)).monospacedDigit().minimumScaleFactor(0.55).lineLimit(1)
            if item.showDate { Text(Self.clockDate(date, format: "EEEE, MMMM d", timeZone: timeZone)).font(.system(size: max(9, timeSize * 0.24), weight: .medium)).foregroundStyle(accent.opacity(0.8)) }
            if showTZ { Text(Self.timeZoneLabel(for: date, timeZone: timeZone)).font(.system(size: 8, weight: .bold)).foregroundStyle(accent) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    @ViewBuilder private func clockWorldList(date: Date, zone: TimeZone, accent: Color, timeSize: CGFloat, count: Int) -> some View {
        let cities = (item?.worldClockCities ?? []).filter { TimeZone(identifier: $0) != nil }
        let list = cities.isEmpty ? ["Europe/London", "Asia/Tokyo"] : Array(cities.prefix(count))
        ForEach(list, id: \.self) { city in
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(WorldClockCities.displayName(for: city)).font(.system(size: 9, weight: .semibold))
                    HStack(spacing: 3) {
                        Image(systemName: Self.isDaylight(in: city, at: date) ? "sun.max.fill" : "moon.stars.fill")
                            .font(.system(size: 6))
                            .foregroundStyle(Color(hex: Self.isDaylight(in: city, at: date) ? "FFD35F" : "AFC4FF"))
                        Text(Self.offsetLabel(in: city, at: date)).font(.system(size: 7)).foregroundStyle(Palette.muted)
                    }
                }
                Spacer(minLength: 4)
                Text(Self.time(in: city, at: date, use24Hour: item?.use24Hour ?? false))
                    .font(.system(size: timeSize, weight: .light, design: .rounded)).monospacedDigit().foregroundStyle(accent)
            }
        }
    }
    @ViewBuilder private func clockContent(_ item: WidgetInstance, date: Date) -> some View {
        let clockAccent = item.accentStyle.hex.map(Color.init(hex:)) ?? Color(hex: item.clockTheme.color)
        let clockZone = item.clockTimeZone == "system" ? TimeZone.current : (TimeZone(identifier: item.clockTimeZone) ?? .current)
        switch item.size {
        case .tile3x1:
            switch item.clockStyle {
            case .minimal:
                HStack {
                    clockMinimalContent(item, date: date, timeZone: clockZone, accent: clockAccent, timeSize: 52, showTZ: true)
                    Spacer(minLength: 0)
                }
            case .world:
                VStack(alignment: .leading, spacing: 8) {
                    header("World Clock", "globe")
                    clockWorldList(date: date, zone: clockZone, accent: clockAccent, timeSize: 16, count: 3)
                }
                Spacer(minLength: 0)
            default:
                HStack(spacing: 12) {
                    clockVisual(item, date: date, side: 118, timeZone: clockZone)
                    Text(Self.digitalTime(date, use24Hour: item.use24Hour, seconds: item.showSeconds, timeZone: clockZone))
                        .font(.system(size: 39, weight: .light, design: .rounded)).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
                    Rectangle().fill(.white.opacity(0.18)).frame(width: 1, height: 58)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(Self.clockDate(date, format: "EEEE", timeZone: clockZone)).font(.system(size: 13, weight: .semibold))
                        Text(Self.clockDate(date, format: "MMM d", timeZone: clockZone)).font(.system(size: 11)).foregroundStyle(.white.opacity(0.66))
                        Text(Self.timeZoneLabel(for: date, timeZone: clockZone)).font(.system(size: 8, weight: .bold)).foregroundStyle(clockAccent)
                    }
                    Spacer(minLength: 0)
                }
            }
        case .tile2x1:
            switch item.clockStyle {
            case .minimal:
                HStack {
                    clockMinimalContent(item, date: date, timeZone: clockZone, accent: clockAccent, timeSize: 44, showTZ: true)
                    Spacer(minLength: 0)
                }
            case .world:
                VStack(alignment: .leading, spacing: 7) {
                    header("World Clock", "globe")
                    clockWorldList(date: date, zone: clockZone, accent: clockAccent, timeSize: 14, count: 3)
                }
                Spacer(minLength: 0)
            default:
                HStack(spacing: 14) {
                    clockVisual(item, date: date, side: 92, timeZone: clockZone)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(Self.digitalTime(date, use24Hour: item.use24Hour, seconds: item.showSeconds, timeZone: clockZone)).font(.system(size: 31, weight: .light, design: .rounded)).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
                        if item.showDate { Text(Self.clockDate(date, format: "EEEE, MMM d", timeZone: clockZone)).font(.system(size: 9)).foregroundStyle(.white.opacity(0.66)) }
                        Text(Self.timeZoneLabel(for: date, timeZone: clockZone)).font(.system(size: 8, weight: .bold)).foregroundStyle(clockAccent)
                    }
                    Spacer(minLength: 0)
                }
            }
        case .tile1x2:
            VStack(spacing: 8) {
                header(item.kind.rawValue, item.kind.symbol)
                Spacer(minLength: 0)
                switch item.clockStyle {
                case .minimal:
                    clockMinimalContent(item, date: date, timeZone: clockZone, accent: clockAccent, timeSize: 48, showTZ: true)
                        .frame(maxWidth: .infinity, alignment: .center)
                case .world:
                    clockWorldList(date: date, zone: clockZone, accent: clockAccent, timeSize: 14, count: 4)
                default:
                    clockVisual(item, date: date, side: 150, timeZone: clockZone)
                    Text(Self.digitalTime(date, use24Hour: item.use24Hour, seconds: item.showSeconds, timeZone: clockZone)).font(.system(size: 27, weight: .light, design: .rounded)).monospacedDigit()
                    if item.showDate { Text(Self.clockDate(date, format: "EEEE, MMM d", timeZone: clockZone)).font(.system(size: 9)).foregroundStyle(.white.opacity(0.66)) }
                    Text(Self.timeZoneLabel(for: date, timeZone: clockZone)).font(.system(size: 8, weight: .bold)).foregroundStyle(clockAccent)
                }
                Spacer(minLength: 0)
            }
        case .tile2x3:
            VStack(alignment: .leading, spacing: 12) {
                switch item.clockStyle {
                case .minimal:
                    clockMinimalContent(item, date: date, timeZone: clockZone, accent: clockAccent, timeSize: 64, showTZ: false)
                        .frame(maxWidth: .infinity, alignment: .center)
                case .world:
                    VStack(alignment: .leading, spacing: 9) {
                        header("World Clock", "globe")
                        clockWorldList(date: date, zone: clockZone, accent: clockAccent, timeSize: 16, count: 5)
                    }
                default:
                    clockVisual(item, date: date, side: 200, timeZone: clockZone).frame(maxWidth: .infinity)
                    Text(Self.digitalTime(date, use24Hour: item.use24Hour, seconds: item.showSeconds, timeZone: clockZone)).font(.system(size: 50, weight: .light, design: .rounded)).monospacedDigit().minimumScaleFactor(0.55).lineLimit(1)
                }
                HStack { Text(Self.clockDate(date, format: "EEEE, MMMM d", timeZone: clockZone)).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.68)); Spacer(); Text(Self.timeZoneLabel(for: date, timeZone: clockZone)).font(.system(size: 8, weight: .bold)).foregroundStyle(clockAccent) }
                Rectangle().fill(.white.opacity(0.15)).frame(height: 1)
                clockWorldList(date: date, zone: clockZone, accent: clockAccent, timeSize: 11, count: 3)
                Spacer(minLength: 0)
            }
        case .tile3x2:
            switch item.clockStyle {
            case .minimal:
                HStack {
                    clockMinimalContent(item, date: date, timeZone: clockZone, accent: clockAccent, timeSize: 72, showTZ: true)
                    Spacer(minLength: 0)
                }
            case .world:
                VStack(alignment: .leading, spacing: 10) {
                    header("World Clock", "globe")
                    clockWorldList(date: date, zone: clockZone, accent: clockAccent, timeSize: 18, count: 5)
                    Spacer(minLength: 0)
                }
            default:
                HStack(spacing: 24) {
                    clockVisual(item, date: date, side: 220, timeZone: clockZone)
                    VStack(alignment: .leading, spacing: 12) {
                        Text(Self.digitalTime(date, use24Hour: item.use24Hour, seconds: item.showSeconds, timeZone: clockZone)).font(.system(size: 55, weight: .light, design: .rounded)).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
                        Text(Self.clockDate(date, format: "EEEE, MMMM d", timeZone: clockZone)).font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.68))
                        Text(Self.timeZoneLabel(for: date, timeZone: clockZone)).font(.system(size: 9, weight: .bold)).foregroundStyle(clockAccent)
                        Rectangle().fill(.white.opacity(0.15)).frame(height: 1)
                        clockWorldList(date: date, zone: clockZone, accent: clockAccent, timeSize: 11, count: 3)
                        Spacer(minLength: 0)
                    }
                    Spacer(minLength: 0)
                }
            }
        default:
            VStack(alignment: .leading, spacing: 8) {
                Spacer(minLength: 4)
                if item.clockStyle == .analog {
                    ClockFace(date: date, showSeconds: item.showSeconds, accent: clockAccent, theme: item.clockTheme, timeZone: clockZone).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if item.clockStyle == .minimal {
                    VStack(spacing: 3) {
                        Text(Self.digitalTime(date, use24Hour: item.use24Hour, seconds: item.showSeconds, timeZone: clockZone)).font(.system(size: expanded ? 72 : 36, weight: .ultraLight, design: .rounded)).monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                        if item.showDate { Text(Self.clockDate(date, format: "EEEE, MMMM d", timeZone: clockZone)).font(.system(size: 10, weight: .medium)).foregroundStyle(clockAccent.opacity(0.8)) }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if item.clockStyle == .world {
                    VStack(alignment: .leading, spacing: 9) {
                        header("World Clock", "globe")
                        ForEach([("LOCAL", clockZone.identifier), ("LONDON", "Europe/London"), ("TOKYO", "Asia/Tokyo")], id: \.0) { city, zone in
                            HStack { Text(city).font(.system(size: 8, weight: .bold)).foregroundStyle(Palette.muted); Spacer(); Text(Self.time(in: zone, at: date)).font(.system(size: expanded ? 20 : 15, weight: .light, design: .rounded)).monospacedDigit().foregroundStyle(clockAccent) }
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    GeometryReader { geometry in
                        Text(Self.digitalTime(date, use24Hour: item.use24Hour, seconds: item.showSeconds, timeZone: clockZone))
                            .font(.system(size: min(max(geometry.size.width * 0.22, 30), expanded ? 90 : 72), weight: .light, design: .rounded))
                            .monospacedDigit().minimumScaleFactor(0.55).lineLimit(1)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    }
                }
                if item.showDate { Text(Self.clockDate(date, format: "EEEE, MMMM d, yyyy", timeZone: clockZone)).font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.62)) }
            }
        }
    }
    @ViewBuilder private func clockVisual(_ item: WidgetInstance, date: Date, side: CGFloat, timeZone: TimeZone) -> some View {
        if item.clockStyle == .analog {
            ClockFace(date: date, showSeconds: item.showSeconds, accent: Color(hex: item.clockTheme.color), theme: item.clockTheme, timeZone: timeZone).frame(width: side, height: side)
        } else {
            Text(Self.digitalTime(date, use24Hour: item.use24Hour, seconds: item.showSeconds, timeZone: timeZone))
                .font(.system(size: side * 0.38, weight: .light, design: item.clockTheme == .mono ? .monospaced : .rounded)).foregroundStyle(Color(hex: item.clockTheme.color)).monospacedDigit().minimumScaleFactor(0.55).lineLimit(1)
                .frame(width: side, height: side)
        }
    }
    private static func timeZoneLabel(for date: Date, timeZone: TimeZone) -> String {
        let offset = timeZone.secondsFromGMT(for: date)
        let sign = offset >= 0 ? "+" : "−"
        let minutes = abs(offset) / 60
        return String(format: "GMT%@%d:%02d", sign, minutes / 60, minutes % 60)
    }
    private static func digitalTime(_ date: Date, use24Hour: Bool, seconds: Bool, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.locale = Locale(identifier: use24Hour ? "en_GB" : Locale.current.identifier)
        formatter.dateStyle = .none
        if seconds { formatter.dateFormat = use24Hour ? "HH:mm:ss" : "h:mm:ss a" }
        else { formatter.timeStyle = .short }
        return formatter.string(from: date)
    }
    private static func clockDate(_ date: Date, format: String, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
    private var configuredCalendar: Calendar {
        var calendar = Calendar.current
        let weekStart = item?.calendarWeekStart ?? .system
        calendar.firstWeekday = weekStart == .monday ? 2 : (weekStart == .sunday ? 1 : Calendar.current.firstWeekday)
        return calendar
    }
    @ViewBuilder private var calendar: some View {
        let month = Calendar.current.date(byAdding: .month, value: item?.calendarMonthOffset ?? 0, to: .now) ?? .now
        let calendarSystem = configuredCalendar
        let shift = calendarSystem.firstWeekday - 1
        let symbols = calendarSystem.shortWeekdaySymbols
        let days = Array(symbols[shift..<symbols.count] + symbols[0..<shift])
        let firstDay = calendarSystem.date(from: calendarSystem.dateComponents([.year, .month], from: month)) ?? month
        let leading = (calendarSystem.component(.weekday, from: firstDay) - calendarSystem.firstWeekday + 7) % 7
        let dayCount = calendarSystem.range(of: .day, in: .month, for: month)?.count ?? 30
        if tiny {
            VStack(alignment: .leading, spacing: 8) {
                header("Today", "calendar")
                Spacer(minLength: 0)
                Text(Date.now.formatted(.dateTime.day())).font(.system(size: 54, weight: .light, design: .rounded)).foregroundStyle(accentColor)
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide))).font(.system(size: 11, weight: .semibold))
                Spacer(minLength: 0)
                Text("Tap a larger size for the month view.").font(.system(size: 8)).foregroundStyle(Palette.muted)
            }
        } else if tall || item?.calendarViewMode == .agenda {
            VStack(alignment: .leading, spacing: 10) {
                header("Upcoming", "calendar")
                Text(month.formatted(.dateTime.month(.wide).year())).font(.system(size: 10, weight: .medium, design: calendarFontDesign)).foregroundStyle(Palette.muted)
                if calendarEvents.isEmpty {
                    calendarEmptyState(calendarEventsMessage.isEmpty ? "Connect Calendar to see your upcoming events." : calendarEventsMessage)
                } else {
                    ForEach(calendarEvents.prefix(tall ? 5 : 3)) { event in calendarEventRow(event) }
                }
                Spacer(minLength: 0)
                Button { Task { await loadCalendarEvents() } } label: { Label("Show my events", systemImage: "calendar.badge.checkmark").font(.system(size: 8, weight: .semibold)).foregroundStyle(accentColor) }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle())
            }
        } else if wide {
            VStack(alignment: .leading, spacing: 12) {
                HStack { header(month.formatted(.dateTime.month(.wide)), "calendar"); Text(month.formatted(.dateTime.year())).font(.system(size: 10, design: calendarFontDesign)).foregroundStyle(Palette.muted) }
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { offset in
                        let currentWeekday = Calendar.current.component(.weekday, from: .now)
                        let start = calendarSystem.firstWeekday
                        let dayOffset = offset - (currentWeekday - start + 7) % 7
                        let day = Calendar.current.date(byAdding: .day, value: dayOffset, to: .now) ?? .now
                        VStack(spacing: 8) {
                            Text(day.formatted(.dateTime.weekday(.narrow))).font(.system(size: 8, weight: .bold, design: calendarFontDesign)).foregroundStyle(Palette.muted)
                            Text(day.formatted(.dateTime.day())).font(.system(size: 13, weight: Calendar.current.isDateInToday(day) ? .bold : .medium, design: calendarFontDesign))
                                .foregroundStyle(Calendar.current.isDateInToday(day) ? Palette.background : .white)
                                .frame(width: 25, height: 25).background(Calendar.current.isDateInToday(day) ? accentColor : .clear, in: Circle())
                        }.frame(maxWidth: .infinity)
                    }
                }
                Spacer(minLength: 0)
                if item?.size == .tile3x1 {
                    Rectangle().fill(.white.opacity(0.12)).frame(height: 1)
                    if let event = calendarEvents.first { calendarEventRow(event) }
                    else { Button { Task { await loadCalendarEvents() } } label: { Label("Show my events", systemImage: "calendar.badge.checkmark").font(.system(size: 8, weight: .semibold)).foregroundStyle(accentColor) }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle()) }
                } else {
                    Text("TODAY · \(Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))").font(.system(size: 9, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                }
            }
        } else if veryWide {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack { header(month.formatted(.dateTime.month(.wide)), "calendar"); Text(month.formatted(.dateTime.year())).font(.system(size: 10, design: calendarFontDesign)).foregroundStyle(Palette.muted) }
                    calendarMonthGrid(days: days, leading: leading, dayCount: dayCount, month: month)
                }.frame(maxWidth: .infinity)
                Rectangle().fill(.white.opacity(0.12)).frame(width: 1)
                VStack(alignment: .leading, spacing: 8) {
                    Text("UPCOMING").font(.system(size: 8, weight: .bold)).tracking(1.1).foregroundStyle(Palette.muted)
                    if calendarEvents.isEmpty {
                        calendarEmptyState(calendarEventsMessage.isEmpty ? "Your events appear here." : calendarEventsMessage)
                    } else {
                        ForEach(calendarEvents.prefix(4)) { event in calendarEventRow(event) }
                    }
                    Spacer(minLength: 0)
                    Button { Task { await loadCalendarEvents() } } label: { Label("Show my events", systemImage: "calendar.badge.checkmark").font(.system(size: 8, weight: .semibold)).foregroundStyle(accentColor) }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle())
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        } else {
        VStack(alignment: .leading, spacing: expanded ? 10 : 6) {
            HStack {
                Image(systemName: "calendar").font(.system(size: 11, weight: .semibold)).foregroundStyle(accentColor)
                Text(month.formatted(.dateTime.month(.wide).year())).font(.system(size: 14, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 2)
                if let id {
                    Button { model.adjustCalendarMonth(id, by: -1) } label: { Image(systemName: "chevron.left") }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle()).help("Previous month")
                    Button { model.adjustCalendarMonth(id, by: 1) } label: { Image(systemName: "chevron.right") }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle()).help("Next month")
                }
            }
            calendarMonthGrid(days: days, leading: leading, dayCount: dayCount, month: month)
            if expanded {
                Rectangle().fill(.white.opacity(0.12)).frame(height: 1)
                if let event = calendarEvents.first { calendarEventRow(event) }
                else {
                    HStack { Text("Upcoming events").font(.system(size: 9, weight: .medium)).foregroundStyle(Palette.muted); Spacer(); Button("Show my events") { Task { await loadCalendarEvents() } }.font(.system(size: 8, weight: .semibold)).buttonStyle(FullAreaButtonStyle()).foregroundStyle(accentColor) }
                }
                Spacer(minLength: 0)
            }
        }
        }
    }
    private func calendarMonthGrid(days: [String], leading: Int, dayCount: Int, month: Date) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7), spacing: 5) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in Text(String(day.prefix(1))).font(.system(size: 8, weight: .bold, design: calendarFontDesign)).foregroundStyle(Palette.muted) }
            ForEach(0..<leading, id: \.self) { _ in Text(" ").frame(maxWidth: .infinity).padding(.vertical, 4) }
            ForEach(1...dayCount, id: \.self) { day in
                let isToday = day == Calendar.current.component(.day, from: .now) && Calendar.current.isDate(month, equalTo: .now, toGranularity: .month)
                let hasEvent = calendarEventDays.contains(day)
                VStack(spacing: 2) {
                    Text("\(day)").font(.system(size: 8, weight: isToday ? .bold : .regular, design: calendarFontDesign))
                        .foregroundStyle(isToday ? Palette.background : .white.opacity(0.75))
                        .frame(maxWidth: .infinity).frame(height: 16)
                        .background(isToday ? accentColor : .clear, in: Circle())
                    Circle().fill(hasEvent ? (isToday ? Palette.background.opacity(0.001) : accentColor) : .clear).frame(width: 3.5, height: 3.5)
                }.frame(maxWidth: .infinity)
            }
        }.padding(.top, 2)
    }
    private func calendarEmptyState(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text).font(.system(size: 9, weight: .medium, design: calendarFontDesign)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            if text.contains("System Settings") || text.contains("Privacy") {
                Button { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.privacy?Privacy_Calendars")!) } label: { Label("Open Settings", systemImage: "gearshape") }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle()).font(.system(size: 8, weight: .semibold)).foregroundStyle(accentColor)
            }
        }
    }
    private func calendarEventRow(_ event: CalendarEventEntry) -> some View {
        let stripe = event.colorHex.map { Color(hex: $0) } ?? accentColor
        return HStack(alignment: .top, spacing: 7) {
            RoundedRectangle(cornerRadius: 2).fill(stripe).frame(width: 3, height: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).font(.system(size: 9, weight: .semibold, design: calendarFontDesign)).lineLimit(1)
                Text(event.isAllDay ? "All-day · \(event.date.formatted(.dateTime.weekday(.abbreviated)))" : "\(event.date.formatted(.dateTime.hour().minute())) – \(event.endDate.formatted(.dateTime.hour().minute())) · \(event.date.formatted(.dateTime.weekday(.abbreviated)))")
                    .font(.system(size: 8, weight: .medium, design: calendarFontDesign)).foregroundStyle(Palette.muted).lineLimit(1)
            }
        }
    }
    private static let calendarStore = EKEventStore()
    private func loadCalendarEvents() async {
        do {
            let granted = try await Self.calendarStore.requestFullAccessToEvents()
            guard granted else { calendarEventsMessage = "Calendar access is off. Allow Littleboard in System Settings → Privacy & Security → Calendars."; return }
            // Cover both the agenda window (today + 7 days) and the displayed month,
            // so the grid can mark days that hold events.
            let displayedMonth = Calendar.current.date(byAdding: .month, value: item?.calendarMonthOffset ?? 0, to: .now) ?? .now
            let monthStart = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: displayedMonth)) ?? displayedMonth
            let monthEnd = Calendar.current.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart) ?? displayedMonth
            let agendaStart = Calendar.current.startOfDay(for: .now)
            let agendaEnd = Calendar.current.date(byAdding: .day, value: 7, to: agendaStart) ?? agendaStart.addingTimeInterval(604_800)
            let start = min(monthStart, agendaStart)
            let end = max(monthEnd, agendaEnd)
            let predicate = Self.calendarStore.predicateForEvents(withStart: start, end: end, calendars: nil)
            let found = Self.calendarStore.events(matching: predicate).sorted { $0.startDate < $1.startDate }
            calendarEvents = found.filter { $0.endDate > agendaStart }.map { event in
                CalendarEventEntry(
                    id: event.eventIdentifier ?? UUID().uuidString,
                    title: event.title ?? "Untitled event",
                    date: event.startDate,
                    endDate: event.endDate,
                    isAllDay: event.isAllDay,
                    colorHex: event.calendar.flatMap { Self.calendarColorHex($0) }
                )
            }
            // Day numbers in the displayed month that carry at least one event.
            let calendar = Calendar.current
            var days = Set<Int>()
            for event in found {
                guard calendar.isDate(event.startDate, equalTo: displayedMonth, toGranularity: .month) else { continue }
                days.insert(calendar.component(.day, from: event.startDate))
            }
            calendarEventDays = days
            calendarEventsMessage = calendarEvents.isEmpty ? "No upcoming events this week." : ""
        } catch {
            calendarEventsMessage = "Calendar access is unavailable. Check Privacy & Security settings."
        }
    }
    private static func calendarColorHex(_ calendar: EKCalendar) -> String? {
        guard let cgColor = calendar.cgColor else { return nil }
        guard let nsColor = NSColor(cgColor: cgColor)?.usingColorSpace(.sRGB) else { return nil }
        return String(format: "%02X%02X%02X", Int(nsColor.redComponent * 255), Int(nsColor.greenComponent * 255), Int(nsColor.blueComponent * 255))
    }
    private func performCalendarClick(_ item: WidgetInstance) {
        switch item.calendarClickAction {
        case .none: break
        case .openCalendar: NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
        case .showAgenda: model.update(item.id) { $0.calendarViewMode = $0.calendarViewMode == .agenda ? .month : .agenda }
        case .openURL: if let url = URL(string: item.calendarClickURL), ["http", "https"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url) }
        case .runShortcut:
            let name = item.calendarShortcutName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, var components = URLComponents(string: "shortcuts://run-shortcut") else { return }
            components.queryItems = [URLQueryItem(name: "name", value: name)]
            if let url = components.url { NSWorkspace.shared.open(url) }
        }
    }
    private func weather(_ item: WidgetInstance) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: "location.fill").font(.system(size: 9)).foregroundStyle(Color(hex: "9BD6FF"))
                Text(weatherReading?.location ?? item.city).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                Spacer()
                Text("LIVE · OPEN-METEO").font(.system(size: 6, weight: .bold)).tracking(0.7).foregroundStyle(.white.opacity(0.45))
            }
            if let weather = weatherReading {
                if tiny {
                    HStack(spacing: 8) {
                        Image(systemName: Self.weatherSymbol(Self.weatherSceneCode(weather.currentCode, scene: item.weatherScene, isDay: weather.isDay))).symbolRenderingMode(.hierarchical).contentTransition(.symbolEffect(.replace)).font(.system(size: 34)).foregroundStyle(Color(hex: "FFD781"))
                        VStack(alignment: .leading, spacing: 0) { Text(Self.weatherTemperature(weather.temperature, unit: item.weatherUnit)).font(.system(size: 38, weight: .ultraLight, design: .rounded)); Text(Self.weatherDescription(Self.weatherSceneCode(weather.currentCode, scene: item.weatherScene, isDay: weather.isDay))).font(.system(size: 8, weight: .medium)).lineLimit(1) }
                    }
                    Text("H \(Self.weatherTemperature(weather.high, unit: item.weatherUnit))   L \(Self.weatherTemperature(weather.low, unit: item.weatherUnit))").font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.72))
                } else if item.size == .tile1x2 {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 8) { Image(systemName: Self.weatherSymbol(Self.weatherSceneCode(weather.currentCode, scene: item.weatherScene, isDay: weather.isDay))).font(.system(size: 28)).foregroundStyle(Color(hex: "FFD781")); VStack(alignment: .leading, spacing: 0) { Text(Self.weatherTemperature(weather.temperature, unit: item.weatherUnit)).font(.system(size: 40, weight: .ultraLight, design: .rounded)); Text(Self.weatherDescription(Self.weatherSceneCode(weather.currentCode, scene: item.weatherScene, isDay: weather.isDay))).font(.system(size: 8, weight: .medium)).lineLimit(1) } }
                        Text("Feels \(Self.weatherTemperature(weather.apparent, unit: item.weatherUnit)) · H \(Self.weatherTemperature(weather.high, unit: item.weatherUnit)) / L \(Self.weatherTemperature(weather.low, unit: item.weatherUnit))").font(.system(size: 7, weight: .medium)).foregroundStyle(.white.opacity(0.7)).lineLimit(1).minimumScaleFactor(0.7)
                        Rectangle().fill(.white.opacity(0.12)).frame(height: 1)
                        ForEach(Array(weather.hours.prefix(4).enumerated()), id: \.offset) { index, hour in HStack { Text(index == 0 ? "Now" : hour.label).font(.system(size: 8)).foregroundStyle(Palette.muted); Spacer(); Image(systemName: Self.weatherSymbol(Self.weatherSceneCode(hour.code, scene: item.weatherScene, isDay: hour.isDay))).font(.system(size: 9)).foregroundStyle(Color(hex: "FFD781")); Text(Self.weatherTemperature(hour.temperature, unit: item.weatherUnit)).font(.system(size: 8, weight: .medium)) } }
                        Rectangle().fill(.white.opacity(0.12)).frame(height: 1)
                        ForEach(Array(weather.days.prefix(3).enumerated()), id: \.offset) { _, day in HStack { Text(day.label).font(.system(size: 8)).frame(width: 32, alignment: .leading); Image(systemName: Self.weatherSymbol(Self.weatherSceneCode(day.code, scene: item.weatherScene))).font(.system(size: 9)).foregroundStyle(Color(hex: "FFD781")); Spacer(); Text("\(Self.weatherTemperature(day.low, unit: item.weatherUnit)) / \(Self.weatherTemperature(day.high, unit: item.weatherUnit))").font(.system(size: 8, weight: .medium)) } }
                    }
                } else {
                    HStack(alignment: .top, spacing: 14) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .center, spacing: 8) { Image(systemName: Self.weatherSymbol(Self.weatherSceneCode(weather.currentCode, scene: item.weatherScene, isDay: weather.isDay))).contentTransition(.symbolEffect(.replace)).font(.system(size: expanded ? 44 : 32)).foregroundStyle(Color(hex: "FFD781")); Text(Self.weatherTemperature(weather.temperature, unit: item.weatherUnit)).font(.system(size: expanded ? 58 : 45, weight: .ultraLight, design: .rounded)).monospacedDigit().contentTransition(.numericText()) }
                            Text(Self.weatherDescription(Self.weatherSceneCode(weather.currentCode, scene: item.weatherScene, isDay: weather.isDay))).font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.82))
                            Text("Feels like \(Self.weatherTemperature(weather.apparent, unit: item.weatherUnit))").font(.system(size: 8)).foregroundStyle(.white.opacity(0.62))
                            HStack(spacing: 10) { Label("↑ \(Self.weatherTemperature(weather.high, unit: item.weatherUnit))", systemImage: "arrow.up"); Label("↓ \(Self.weatherTemperature(weather.low, unit: item.weatherUnit))", systemImage: "arrow.down") }.font(.system(size: 8, weight: .medium)).foregroundStyle(.white.opacity(0.72)).padding(.top, 3)
                        }
                        Spacer(minLength: 0)
                        if expanded || tall {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("7 DAY FORECAST").font(.system(size: 7, weight: .bold)).tracking(0.7).foregroundStyle(Palette.muted)
                                ForEach(Array(weather.days.prefix(5).enumerated()), id: \.offset) { index, day in
                                    HStack(spacing: 7) { Text(day.label).font(.system(size: 8, weight: .medium)).frame(width: 27, alignment: .leading); Image(systemName: Self.weatherSymbol(Self.weatherSceneCode(day.code, scene: item.weatherScene))).font(.system(size: 9)).foregroundStyle(Color(hex: "FFD781")); Text(Self.weatherTemperature(day.low, unit: item.weatherUnit)).font(.system(size: 8)).foregroundStyle(.white.opacity(0.6)); GeometryReader { geo in Capsule().fill(LinearGradient(colors: [Color(hex: "83C9FF"), Color(hex: "FFD35F")], startPoint: .leading, endPoint: .trailing)).frame(width: max(12, geo.size.width * CGFloat((day.high - weather.low) / max(1, weather.high - weather.low)))) }.frame(height: 4); Text(Self.weatherTemperature(day.high, unit: item.weatherUnit)).font(.system(size: 8, weight: .semibold)) }
                                }
                            }.frame(maxWidth: expanded ? 135 : 150)
                        }
                    }
                    Rectangle().fill(.white.opacity(0.12)).frame(height: 1)
                    if expanded {
                        WeatherTemperatureChart(hours: Array(weather.hours.prefix(12)), unit: item.weatherUnit)
                            .frame(height: 50)
                    }
                    HStack(spacing: 0) {
                        ForEach(Array(weather.hours.prefix(5).enumerated()), id: \.offset) { index, hour in
                            VStack(spacing: 5) { Text(index == 0 ? "NOW" : hour.label).font(.system(size: 7, weight: .semibold)).foregroundStyle(.white.opacity(0.58)); Image(systemName: Self.weatherSymbol(Self.weatherSceneCode(hour.code, scene: item.weatherScene, isDay: hour.isDay))).font(.system(size: 11)).foregroundStyle(Color(hex: "FFD781")); Text(Self.weatherTemperature(hour.temperature, unit: item.weatherUnit)).font(.system(size: 9, weight: .medium, design: .rounded)) }.frame(maxWidth: .infinity)
                        }
                    }
                    if expanded { HStack { Label("Humidity \(weather.humidity)%", systemImage: "humidity"); Spacer(); Label("Wind \(Int(weather.wind.rounded())) km/h", systemImage: "wind"); Spacer(); Label("AQI \(weather.aqi.map(String.init) ?? "—")", systemImage: "aqi.medium"); Spacer(); Label("Sunset \(weather.sunset)", systemImage: "sunset") }.font(.system(size: 8, weight: .medium)).foregroundStyle(.white.opacity(0.7)) }
                }
            } else {
                Spacer(minLength: 0)
                ProgressView().controlSize(.small).tint(Color(hex: "FFD781")).frame(maxWidth: .infinity)
                Text(weatherError ?? "Getting current conditions for \(item.city)…").font(.system(size: 9)).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
        }
        .animation(item.weatherLiveAnimation ? .easeInOut(duration: 0.65) : nil, value: item.weatherScene)
        .animation(item.weatherLiveAnimation ? .easeInOut(duration: 0.65) : nil, value: weatherReading?.currentCode)
    }
    @MainActor private func loadWeather(for item: WidgetInstance) async {
        weatherError = nil
        do {
            let latitude = item.weatherUsesCurrentLocation ? item.weatherLatitude : nil
            let longitude = item.weatherUsesCurrentLocation ? item.weatherLongitude : nil
            weatherReading = try await Self.fetchWeather(city: item.city, latitude: latitude, longitude: longitude, locationName: item.weatherLocationName)
        } catch {
            weatherReading = nil
            weatherError = "Weather unavailable. Check the city and internet connection."
        }
    }
    static func fetchWeather(city: String, latitude: Double?, longitude: Double?, locationName: String?) async throws -> WeatherSnapshot {
        let coordinates: (latitude: Double, longitude: Double, name: String)
        if let latitude, let longitude {
            coordinates = (latitude, longitude, locationName?.isEmpty == false ? locationName! : "Current Location")
        } else {
            var geocode = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
            geocode.queryItems = [URLQueryItem(name: "name", value: city), URLQueryItem(name: "count", value: "1"), URLQueryItem(name: "language", value: "en"), URLQueryItem(name: "format", value: "json")]
            let (geoData, _) = try await URLSession.shared.data(from: geocode.url!)
            let geo = try JSONDecoder().decode(GeoResponse.self, from: geoData)
            guard let place = geo.results?.first else { throw URLError(.cannotFindHost) }
            coordinates = (place.latitude, place.longitude, place.name + (place.admin1.map { ", \($0)" } ?? ""))
        }
        var endpoint = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        endpoint.queryItems = [URLQueryItem(name: "latitude", value: String(coordinates.latitude)), URLQueryItem(name: "longitude", value: String(coordinates.longitude)), URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,is_day"), URLQueryItem(name: "hourly", value: "temperature_2m,weather_code,is_day"), URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset"), URLQueryItem(name: "timezone", value: "auto"), URLQueryItem(name: "forecast_days", value: "7")]
        let (data, _) = try await URLSession.shared.data(from: endpoint.url!)
        let response = try JSONDecoder().decode(ForecastResponse.self, from: data)
        var airQuality: AirQualityResponse?
        var airEndpoint = URLComponents(string: "https://air-quality-api.open-meteo.com/v1/air-quality")!
        airEndpoint.queryItems = [URLQueryItem(name: "latitude", value: String(coordinates.latitude)), URLQueryItem(name: "longitude", value: String(coordinates.longitude)), URLQueryItem(name: "current", value: "us_aqi,pm2_5"), URLQueryItem(name: "timezone", value: "auto")]
        if let (airData, _) = try? await URLSession.shared.data(from: airEndpoint.url!) { airQuality = try? JSONDecoder().decode(AirQualityResponse.self, from: airData) }
        let hourFormatter = DateFormatter(); hourFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm"; hourFormatter.timeZone = TimeZone(identifier: response.timezone)
        let dayFormatter = DateFormatter(); dayFormatter.dateFormat = "yyyy-MM-dd"; dayFormatter.timeZone = TimeZone(identifier: response.timezone)
        let labelFormatter = DateFormatter(); labelFormatter.dateFormat = "EEE"; labelFormatter.timeZone = TimeZone(identifier: response.timezone)
        let now = Date.now
        let hours = zip(response.hourly.time.indices, response.hourly.time).compactMap { index, value -> WeatherHour? in
            guard let date = hourFormatter.date(from: value), date >= now, index < response.hourly.temperature.count, index < response.hourly.code.count else { return nil }
            let isDay = response.hourly.isDay.flatMap { index < $0.count ? $0[index] : nil } ?? 1
            return WeatherHour(label: hourFormatter.string(from: date).suffix(5).description, temperature: response.hourly.temperature[index], code: response.hourly.code[index], isDay: isDay != 0)
        }
        let days = response.daily.time.indices.compactMap { index -> WeatherDay? in
            guard index < response.daily.high.count, index < response.daily.low.count, index < response.daily.code.count, let date = dayFormatter.date(from: response.daily.time[index]) else { return nil }
            return WeatherDay(label: Calendar.current.isDateInToday(date) ? "Today" : labelFormatter.string(from: date), low: response.daily.low[index], high: response.daily.high[index], code: response.daily.code[index])
        }
        return WeatherSnapshot(location: coordinates.name, temperature: response.current.temperature, apparent: response.current.apparent, humidity: response.current.humidity, wind: response.current.wind, currentCode: response.current.code, high: response.daily.high.first ?? response.current.temperature, low: response.daily.low.first ?? response.current.temperature, hours: Array(hours.prefix(24)), days: days, sunset: response.daily.sunset.first.flatMap { String($0.suffix(5)) } ?? "—", aqi: airQuality?.current.aqi, isDay: response.current.isDay != 0)
    }
    // Out-of-band code for the Night scene: real conditions still drive the
    // numbers, but every visual switch (symbol, description, sky colors) treats
    // it as a clear night.
    static let nightWeatherCode = 1000
    static func weatherDescription(_ code: Int) -> String {
        switch code { case Self.nightWeatherCode: return "Clear night"; case 0: return "Clear sky"; case 1: return "Mainly clear"; case 2: return "Partly cloudy"; case 3: return "Overcast"; case 45, 48: return "Fog"; case 51...57: return "Drizzle"; case 61...67: return "Rain"; case 71...77: return "Snow"; case 80...82: return "Rain showers"; case 85, 86: return "Snow showers"; case 95...99: return "Thunderstorm"; default: return "Current conditions" }
    }
    static func weatherTemperature(_ celsius: Double, unit: WeatherUnit) -> String {
        let useFahrenheit = unit == .fahrenheit || (unit == .auto && Locale.current.measurementSystem == .us)
        let value = useFahrenheit ? celsius * 9 / 5 + 32 : celsius
        return "\(Int(value.rounded()))°"
    }
    private static func weatherSkyColors(code: Int) -> [Color] {
        switch code {
        case Self.nightWeatherCode: return [Color(hex: "0B1026"), Color(hex: "232B52")]
        case 0, 1: return [Color(hex: "2478C8"), Color(hex: "F4A64A")]
        case 2, 3, 45, 48: return [Color(hex: "65798F"), Color(hex: "344256")]
        case 51...67, 80...82, 95...99: return [Color(hex: "243B59"), Color(hex: "152234")]
        case 71...77, 85, 86: return [Color(hex: "8DB3D1"), Color(hex: "506C89")]
        default: return [Color(hex: "2478C8"), Color(hex: "F4A64A")]
        }
    }
    private static func weatherSceneCode(_ actualCode: Int, scene: WeatherScene, isDay: Bool = true) -> Int {
        switch scene {
        case .auto:
            // After sunset Auto renders clear skies as a night scene.
            if isDay { return actualCode }
            return actualCode <= 1 ? Self.nightWeatherCode : actualCode
        case .clear: return 0; case .partlyCloudy: return 2; case .rain: return 61; case .snow: return 71; case .night: return Self.nightWeatherCode
        }
    }
    static func weatherSymbol(_ code: Int) -> String {
        switch code { case Self.nightWeatherCode: return "moon.stars.fill"; case 0, 1: return "sun.max.fill"; case 2: return "cloud.sun.fill"; case 3: return "cloud.fill"; case 45, 48: return "cloud.fog.fill"; case 51...67, 80...82: return "cloud.rain.fill"; case 71...77, 85, 86: return "cloud.snow.fill"; case 95...99: return "cloud.bolt.rain.fill"; default: return "cloud.sun.fill" }
    }
    private func note(_ item: WidgetInstance) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header(item.title, "note.text")
            if wide {
                HStack(alignment: .center, spacing: 20) {
                    Text(item.note).font(.system(size: veryWide ? 24 : 18, weight: .medium, design: .rounded)).lineLimit(3).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 5) { Text("\(item.note.count)").font(.system(size: 24, weight: .light, design: .rounded)); Text("CHARACTERS").font(.system(size: 7, weight: .bold)).tracking(0.7).foregroundStyle(Palette.muted) }
                }
            } else {
                Spacer(minLength: 0)
                Text(item.note).font(.system(size: tiny ? 14 : expanded ? 23 : 18, weight: .medium, design: .rounded)).lineLimit(expanded ? 9 : 5).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if expanded { Text("\(item.note.split(whereSeparator: \.isWhitespace).count) WORDS · \(item.note.count) CHARACTERS").font(.system(size: 7, weight: .bold)).tracking(0.8).foregroundStyle(Palette.muted) }
                else { Text("EDIT IN WIDGET SETTINGS").font(.system(size: 7, weight: .bold)).tracking(0.8).foregroundStyle(Palette.muted) }
            }
        }
    }
    private var quote: some View {
        let quotes = [("The secret of getting ahead is getting started.", "MARK TWAIN"), ("It always seems impossible until it’s done.", "NELSON MANDELA"), ("Great things are done by a series of small things.", "VINCENT VAN GOGH"), ("Well done is better than well said.", "BENJAMIN FRANKLIN"), ("Act as if what you do makes a difference. It does.", "WILLIAM JAMES")]
        let selected = quotes[(item?.quoteIndex ?? 0) % quotes.count]
        return VStack(alignment: .leading, spacing: 12) {
            header("A thought", "quote.opening")
            if wide {
                HStack(alignment: .center, spacing: 20) {
                    Text("“\(selected.0)”").font(.system(size: veryWide ? 24 : 18, weight: .regular, design: .serif)).lineSpacing(3).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 7) { Capsule().fill(accentColor).frame(width: 22, height: 2); Text(selected.1).font(.system(size: 8, weight: .bold)).tracking(1).foregroundStyle(.white.opacity(0.58)); if veryWide { Button("Next quote", systemImage: "arrow.right") { if let id { model.nextQuote(id) } }.font(.system(size: 9, weight: .semibold)).buttonStyle(FullAreaButtonStyle()).foregroundStyle(accentColor) } }
                }
            } else {
                Spacer(minLength: 0)
                Text("“\(selected.0)”").font(.system(size: expanded ? 24 : 18, weight: .regular, design: .serif)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 7) { Capsule().fill(accentColor).frame(width: 16, height: 2); Text(selected.1).font(.system(size: 8, weight: .bold)).tracking(1.1).foregroundStyle(.white.opacity(0.55)); Spacer(); if let id { Button { model.nextQuote(id) } label: { Image(systemName: "arrow.right") }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle()).foregroundStyle(accentColor).help("Next quote") } }
                if expanded { Spacer(minLength: 0); Text("A small reminder for today.").font(.system(size: 10)).foregroundStyle(Palette.muted) }
                Spacer(minLength: 0)
            }
        }
    }
    private func progress(_ kind: WidgetKind) -> some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let calendar = Calendar.current
            let now = context.date
            let year = calendar.component(.year, from: now)
            let dayStart = calendar.startOfDay(for: now)
            let start = kind == .dayProgress ? dayStart : (calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? now)
            let end = kind == .dayProgress ? (calendar.date(byAdding: .day, value: 1, to: dayStart) ?? now.addingTimeInterval(86400)) : (calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) ?? now.addingTimeInterval(31_536_000))
            let value = min(max(now.timeIntervalSince(start) / end.timeIntervalSince(start), 0), 1)
            let remaining = max(0, Int(end.timeIntervalSince(now)))
            VStack(alignment: .leading, spacing: 12) {
                header(kind.rawValue, "chart.pie.fill")
                if tiny {
                    Spacer(minLength: 0)
                    Text("\(Int(value * 100))%").font(.system(size: 41, weight: .light, design: .rounded))
                    ProgressView(value: value).tint(accentColor)
                    Text(kind == .dayProgress ? "\(remaining / 3600) HOURS LEFT TODAY" : "\(remaining / 86400) DAYS LEFT THIS YEAR").font(.system(size: 8, weight: .bold)).tracking(0.6).foregroundStyle(Palette.muted)
                    Spacer(minLength: 0)
                } else if wide {
                    HStack(spacing: 20) {
                        Text("\(Int(value * 100))%").font(.system(size: veryWide ? 58 : 43, weight: .light, design: .rounded)).monospacedDigit()
                        VStack(alignment: .leading, spacing: 8) {
                            ProgressView(value: value).tint(accentColor)
                            Text(kind == .dayProgress ? "\(remaining / 3600)h \((remaining % 3600) / 60)m left today" : "\(remaining / 86400) days left in \(calendar.component(.year, from: now))").font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                        }
                        Spacer(minLength: 0)
                    }
                } else {
                    Spacer(minLength: 0)
                    Text("\(Int(value * 100))%").font(.system(size: expanded ? 62 : 48, weight: .light, design: .rounded)).monospacedDigit()
                    ProgressView(value: value).tint(accentColor)
                    Text(kind == .dayProgress ? "\(remaining / 3600) HOURS \((remaining % 3600) / 60) MINUTES LEFT" : "\(remaining / 86400) DAYS UNTIL YEAR END").font(.system(size: 8, weight: .bold)).tracking(0.8).foregroundStyle(Palette.muted)
                    if expanded { Text("Updated live · local time").font(.system(size: 9)).foregroundStyle(.white.opacity(0.65)) }
                    Spacer(minLength: 0)
                }
            }
        }
    }
    private var countdownCard: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let year = Calendar.current.component(.year, from: context.date) + 1
            let target = Calendar.current.date(from: DateComponents(year: year, month: 1, day: 1)) ?? context.date
            let seconds = max(0, Int(target.timeIntervalSince(context.date)))
            VStack(alignment: .leading, spacing: 12) {
                header("Countdown", "hourglass")
                Text("New Year · \(year)").font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                Spacer(minLength: 0)
                if tiny {
                    Text("\(seconds / 86400)").font(.system(size: 48, weight: .light, design: .rounded)).monospacedDigit()
                    Text("DAYS TO GO").font(.system(size: 8, weight: .bold)).tracking(0.9).foregroundStyle(Palette.muted)
                } else if wide {
                    HStack(spacing: 18) {
                        countdownUnit("DAYS", seconds / 86400)
                        countdownUnit("HOURS", (seconds / 3600) % 24)
                        countdownUnit("MIN", (seconds / 60) % 60)
                        if veryWide { countdownUnit("SEC", seconds % 60) }
                    }
                } else {
                    HStack(spacing: 10) { countdownUnit("DAYS", seconds / 86400); countdownUnit("HOURS", (seconds / 3600) % 24); countdownUnit("MIN", (seconds / 60) % 60) }
                    if expanded { Text("\(seconds % 60) seconds · counting down live").font(.system(size: 9)).foregroundStyle(.white.opacity(0.6)) }
                }
                Spacer(minLength: 0)
            }
        }
    }
    private func countdownUnit(_ label: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(format: "%02d", value)).font(.system(size: expanded || veryWide ? 30 : 23, weight: .light, design: .rounded)).monospacedDigit()
            Text(label).font(.system(size: 7, weight: .bold)).tracking(0.8).foregroundStyle(Palette.muted)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    @ViewBuilder private var worldClock: some View {
        TimelineView(.periodic(from: .now, by: item?.showSeconds == true ? 1 : 30)) { context in worldClockLayout(at: context.date) }
    }
    @ViewBuilder private func worldClockLayout(at date: Date) -> some View {
        let zones = item?.worldClockCities.filter { TimeZone(identifier: $0) != nil } ?? []
        let cities = zones.isEmpty ? ["America/New_York", "Europe/London", "Asia/Tokyo"] : zones
        let zone = { (identifier: String) in TimeZone(identifier: identifier) ?? .current }
        if tiny {
            let first = cities.first ?? "America/New_York"
            VStack(alignment: .leading, spacing: 5) {
                header(WorldClockCities.displayName(for: first), "globe")
                Spacer(minLength: 0)
                Text(Self.time(in: first, at: date, use24Hour: item?.use24Hour ?? false))
                    .font(.system(size: 30, weight: .light, design: .rounded)).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: Self.isDaylight(in: first, at: date) ? "sun.max.fill" : "moon.stars.fill").font(.system(size: 7)).foregroundStyle(Color(hex: Self.isDaylight(in: first, at: date) ? "FFD35F" : "AFC4FF"))
                    Text(Self.offsetLabel(in: first, at: date)).font(.system(size: 8, weight: .semibold)).foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 0)
            }
        } else if wide && !veryWide {
            VStack(alignment: .leading, spacing: 10) {
                header("World Clock · Live", "globe")
                HStack(spacing: 8) {
                    ForEach(cities.prefix(3), id: \.self) { city in
                        worldClockTile(city, at: date, zone: zone(city), face: 20, timeSize: veryWide ? 20 : 15)
                    }
                }
                Spacer(minLength: 0)
            }
        } else if veryWide {
            // 3×2 / 3×1: two-column grid of city tiles with analog faces.
            VStack(alignment: .leading, spacing: 10) {
                header("World Clock", "globe")
                let columns = item?.size == .tile3x1 ? 1 : 2
                let visible = item?.size == .tile3x1 ? Array(cities.prefix(4)) : Array(cities.prefix(6))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns == 1 ? 1 : 2), spacing: 7) {
                    ForEach(visible, id: \.self) { city in
                        worldClockTile(city, at: date, zone: zone(city), face: 22, timeSize: 15, boxed: true)
                    }
                }
                Spacer(minLength: 0)
            }
        } else if tall {
            // 1×2: vertical list of up to five cities.
            VStack(alignment: .leading, spacing: 9) {
                header("World Clock", "globe")
                ForEach(cities.prefix(5), id: \.self) { city in
                    worldClockRow(city, at: date, zone: zone(city), face: 20, timeSize: 14)
                }
                Spacer(minLength: 0)
            }
        } else {
            // 2×2 and larger: reference-style list with analog faces and offsets.
            VStack(alignment: .leading, spacing: expanded ? 10 : 8) {
                header("World Clock", "globe")
                ForEach(cities.prefix(expanded ? 5 : 3), id: \.self) { city in
                    worldClockRow(city, at: date, zone: zone(city), face: expanded ? 26 : 20, timeSize: expanded ? 16 : 13)
                }
                if expanded {
                    Spacer(minLength: 0)
                    Text("TIMES UPDATE LIVE · EDIT CITIES IN THE LIBRARY").font(.system(size: 6, weight: .bold)).tracking(0.7).foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 0)
            }
        }
    }
    private func worldClockRow(_ city: String, at date: Date, zone: TimeZone, face: CGFloat, timeSize: CGFloat) -> some View {
        HStack(spacing: 9) {
            MiniClockFace(date: date, timeZone: zone, accent: accentColor, size: face)
            VStack(alignment: .leading, spacing: 2) {
                Text(WorldClockCities.displayName(for: city)).font(.system(size: 10, weight: .semibold, design: .rounded)).lineLimit(1)
                HStack(spacing: 3) {
                    Image(systemName: Self.isDaylight(in: city, at: date) ? "sun.max.fill" : "moon.stars.fill")
                        .font(.system(size: 6.5))
                        .foregroundStyle(Color(hex: Self.isDaylight(in: city, at: date) ? "FFD35F" : "AFC4FF"))
                    Text(Self.offsetLabel(in: city, at: date)).font(.system(size: 7.5, weight: .medium)).foregroundStyle(Palette.muted)
                }
            }
            Spacer(minLength: 4)
            Text(Self.time(in: city, at: date, use24Hour: item?.use24Hour ?? false))
                .font(.system(size: timeSize, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }
    }
    private func worldClockTile(_ city: String, at date: Date, zone: TimeZone, face: CGFloat, timeSize: CGFloat, boxed: Bool = false) -> some View {
        let content = HStack(spacing: 8) {
            MiniClockFace(date: date, timeZone: zone, accent: accentColor, size: face)
            VStack(alignment: .leading, spacing: 2) {
                Text(WorldClockCities.displayName(for: city)).font(.system(size: 8.5, weight: .semibold, design: .rounded)).lineLimit(1)
                Text(Self.time(in: city, at: date, use24Hour: item?.use24Hour ?? false))
                    .font(.system(size: timeSize, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1)
                HStack(spacing: 3) {
                    Image(systemName: Self.isDaylight(in: city, at: date) ? "sun.max.fill" : "moon.stars.fill")
                        .font(.system(size: 6.5))
                        .foregroundStyle(Color(hex: Self.isDaylight(in: city, at: date) ? "FFD35F" : "AFC4FF"))
                    Text(Self.offsetLabel(in: city, at: date)).font(.system(size: 7, weight: .medium)).foregroundStyle(Palette.muted)
                }
            }
            Spacer(minLength: 0)
        }
        return Group {
            if boxed { content.padding(8).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10)) }
            else { content }
        }
    }
    private static func time(in identifier: String, at date: Date = .now, use24Hour: Bool = false) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: identifier)
        if use24Hour {
            formatter.dateFormat = "HH:mm"
        } else {
            formatter.timeStyle = .short
        }
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
    private static func isDaylight(in identifier: String, at date: Date) -> Bool {
        guard let zone = TimeZone(identifier: identifier) else { return true }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let hour = calendar.component(.hour, from: date)
        return hour >= 6 && hour < 19
    }
    private static func offsetLabel(in identifier: String, at date: Date) -> String {
        guard let zone = TimeZone(identifier: identifier) else { return "" }
        let difference = Double(zone.secondsFromGMT(for: date) - TimeZone.current.secondsFromGMT(for: date)) / 3600
        if abs(difference) < 0.01 { return "This Mac" }
        let rounded = (difference * 2).rounded() / 2
        let sign = rounded >= 0 ? "+" : "−"
        let value = abs(rounded)
        let text = value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.1f", value)
        return "\(sign)\(text)h"
    }
    private static func dayLabel(in identifier: String, at date: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: identifier)
        formatter.dateFormat = "EEE · MMM d"
        return formatter.string(from: date)
    }
    private func metric(_ kind: WidgetKind, value: String, detail: String) -> some View {
        let facts = Self.metricFacts(kind)
        return VStack(alignment: .leading, spacing: 10) {
            header(kind.rawValue, kind.symbol)
            if tiny {
                Spacer(minLength: 0)
                Text(value).font(.system(size: 22, weight: .medium, design: .rounded)).lineLimit(2).minimumScaleFactor(0.65)
                Text(detail).font(.system(size: 8)).foregroundStyle(.white.opacity(0.6)).lineLimit(2)
                Spacer(minLength: 0)
                metricAction(kind)
            } else if wide || veryWide {
                HStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 7) { Text(value).font(.system(size: veryWide ? 34 : 26, weight: .medium, design: .rounded)).lineLimit(1).minimumScaleFactor(0.65); Text(detail).font(.system(size: 9)).foregroundStyle(.white.opacity(0.62)).lineLimit(2) }
                    ForEach(Array(facts.prefix(veryWide ? 3 : 2).enumerated()), id: \.offset) { _, fact in VStack(alignment: .leading, spacing: 5) { Text(fact.0.uppercased()).font(.system(size: 7, weight: .bold)).tracking(0.7).foregroundStyle(Palette.muted); Text(fact.1).font(.system(size: 10, weight: .medium)).lineLimit(2) }.frame(maxWidth: .infinity, alignment: .leading) }
                    metricAction(kind)
                }
                Spacer(minLength: 0)
            } else {
                Text(value).font(.system(size: expanded ? 32 : 23, weight: .medium, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
                Text(detail).font(.system(size: 9)).foregroundStyle(.white.opacity(0.62)).lineLimit(2)
                ForEach(Array(facts.prefix(expanded ? 4 : (tall ? 2 : 0)).enumerated()), id: \.offset) { _, fact in
                    HStack(alignment: .firstTextBaseline) { Text(fact.0).font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.62)); Spacer(); Text(fact.1).font(.system(size: 9, weight: .semibold)).multilineTextAlignment(.trailing).lineLimit(2) }
                }
                Spacer(minLength: 0)
                metricAction(kind)
            }
        }
    }
    private var networkCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                header("Network", "wifi")
                Spacer(minLength: 4)
                if !tiny, item?.showLocalAddress ?? true, let local = localIPs.first(where: { filterMatches($0.0) }) ?? localIPs.first {
                    Text(local.1).font(.system(size: 8, weight: .semibold, design: .monospaced)).foregroundStyle(.white.opacity(0.55)).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                }
            }
            // Live throughput hero, sampled from kernel counters every second.
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                speedBlock(direction: "arrow.down", color: Color(hex: "5AC8FA"), bytesPerSecond: downSpeed)
                speedBlock(direction: "arrow.up", color: Color(hex: "30D158"), bytesPerSecond: upSpeed)
                Spacer(minLength: 0)
            }
            if !tiny {
                VStack(alignment: .leading, spacing: 6) {
                    if let wifiName { networkRow("Wi-Fi network", wifiName) }
                    if let local = localIPs.first { networkRow("Interface", [model.networkType, filterMatches(local.0) ? local.0 : model.networkInterface].filter { !$0.isEmpty }.joined(separator: " · ")) }
                    if let externalIP { networkRow("External IP", externalIP) }
                    if let externalRegion { networkRow("Region", externalRegion) }
                    if localIPs.isEmpty && externalIP == nil {
                        Text("Waiting for network details…").font(.system(size: 9)).foregroundStyle(Palette.muted)
                    }
                }
            }
            Spacer(minLength: 0)
            Button { openApp("com.apple.systempreferences") } label: { Label("Network Settings", systemImage: "gearshape") }
                .font(.system(size: 9, weight: .semibold)).buttonStyle(FullAreaButtonStyle()).foregroundStyle(accentColor)
        }
    }
    private func speedBlock(direction: String, color: Color, bytesPerSecond: Double) -> some View {
        let formatted = Self.speedText(bytesPerSecond, unit: item?.networkUnit ?? "mbs")
        return HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: direction).font(.system(size: expanded ? 15 : 12, weight: .bold)).foregroundStyle(color)
            Text(formatted.value).font(.system(size: expanded ? 34 : 24, weight: .medium, design: .rounded)).monospacedDigit().contentTransition(.numericText())
            Text(formatted.suffix).font(.system(size: 8, weight: .bold)).foregroundStyle(Palette.muted)
        }
    }
    static func speedText(_ bytesPerSecond: Double, unit: String) -> (value: String, suffix: String) {
        if unit == "mbit" {
            let mbit = bytesPerSecond * 8 / 1_000_000
            let value = mbit >= 100 ? String(format: "%.0f", mbit) : (mbit >= 10 ? String(format: "%.1f", mbit) : String(format: "%.2f", mbit))
            return (value, "Mbit/s")
        }
        if bytesPerSecond >= 1024 * 1024 {
            return (String(format: "%.1f", bytesPerSecond / (1024 * 1024)), "MB/s")
        }
        return ("\(Int(bytesPerSecond / 1024))", "KB/s")
    }
    private func filterMatches(_ interface: String) -> Bool {
        let filter = item?.networkInterfaceFilter ?? "all"
        return filter == "all" || filter == interface
    }
    private func networkRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.62))
            Spacer()
            Text(value).font(.system(size: 9, weight: .semibold, design: .monospaced)).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
        }
    }
    private func loadNetworkFacts() async {
        localIPs = LiveFeed.localAddresses()
        wifiName = LiveFeed.wifiNetworkName()
        if let trace = await LiveFeed.networkTrace() {
            externalIP = trace.ip
            externalRegion = trace.region
        }
    }
    private func loadStocks(_ item: WidgetInstance) async {
        let quotes = await LiveFeed.stocks(item.stocksSymbols)
        stocksQuotes = quotes
        stocksError = quotes.isEmpty ? "Couldn't reach Yahoo Finance. Check the symbols and connection." : nil
    }
    private func loadCrypto(_ item: WidgetInstance) async {
        let prices = await LiveFeed.crypto(item.cryptoCoins)
        cryptoPrices = prices
        cryptoError = prices.isEmpty ? "Couldn't reach CoinGecko. The free feed may be busy — retrying soon." : nil
    }
    private func loadRates(_ item: WidgetInstance) async {
        if let result = await LiveFeed.rates(base: item.currencyBase, quotes: item.currencyQuotes) {
            rateRows = result.rows
            ratesDate = result.date
            ratesError = nil
        } else {
            ratesError = "Couldn't reach the exchange-rate feed."
        }
    }
    private func loadRepo(_ item: WidgetInstance) async {
        if let info = await LiveFeed.repository(item.githubRepo) {
            repo = info
            repoError = nil
        } else {
            repoError = "Couldn't load \(item.githubRepo). Use owner/repository in settings."
        }
    }
    private func loadAirQuality(_ item: WidgetInstance) async {
        if let reading = await LiveFeed.airQuality(city: item.city) {
            airReading = reading
            airError = nil
        } else {
            airError = "Air quality unavailable for \(item.city). Check the city name."
        }
    }
    private func feedFooter(_ label: String) -> some View {
        Text(label).font(.system(size: 6, weight: .bold)).tracking(0.7).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
    }
    private func feedLoadingView(_ message: String) -> some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            ProgressView().controlSize(.small).tint(accentColor).frame(maxWidth: .infinity)
            Text(message).font(.system(size: 9)).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center).frame(maxWidth: .infinity)
            Spacer(minLength: 0)
        }
    }
    private func feedErrorView(_ message: String, retry: @escaping () -> Void) -> some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            Image(systemName: "wifi.exclamationmark").font(.system(size: 22, weight: .light)).foregroundStyle(.white.opacity(0.5))
            Text(message).font(.system(size: 9)).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            Button("Retry") { retry() }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle()).font(.system(size: 9, weight: .semibold)).foregroundStyle(accentColor)
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity)
    }
    private var stocksCard: some View {
        let quotes = stocksQuotes ?? []
        return VStack(alignment: .leading, spacing: 9) {
            header("Stocks", "chart.line.uptrend.xyaxis")
            if !quotes.isEmpty {
                if let first = quotes.first, expanded || veryWide {
                    MiniSparkline(values: first.closes, up: first.change >= 0).frame(height: expanded ? 44 : 28)
                }
                if tiny {
                    if let first = quotes.first { stockRow(first, big: true) }
                } else if wide {
                    HStack(spacing: 16) {
                        ForEach(quotes.prefix(veryWide ? 4 : 3)) { quote in stockRow(quote).frame(maxWidth: .infinity) }
                    }
                } else {
                    ForEach(quotes.prefix(expanded ? 5 : 3)) { quote in stockRow(quote) }
                }
                Spacer(minLength: 0)
                feedFooter("LIVE · YAHOO FINANCE · REFRESHES EVERY 5 MIN")
            } else if let stocksError {
                feedErrorView(stocksError) { if let item { Task { await loadStocks(item) } } }
            } else {
                feedLoadingView("Fetching quotes…")
            }
        }
    }
    private func stockRow(_ quote: LiveFeed.StockQuote, big: Bool = false) -> some View {
        let up = quote.change >= 0
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(quote.symbol).font(.system(size: big ? 16 : 11, weight: .semibold, design: .rounded))
                if big, let currency = quote.currency { Text(currency).font(.system(size: 8, weight: .medium)).foregroundStyle(Palette.muted) }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 1) {
                Text(String(format: "%.2f", quote.price)).font(.system(size: big ? 30 : 13, weight: .medium, design: .rounded)).monospacedDigit().contentTransition(.numericText())
                HStack(spacing: 3) {
                    Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
                    Text(String(format: "%+.2f%%", quote.changePercent))
                }.font(.system(size: 9, weight: .semibold)).foregroundStyle(up ? Color(hex: "30D158") : Color(hex: "FF453A"))
            }
        }
    }
    private var cryptoCard: some View {
        let prices = cryptoPrices ?? []
        return VStack(alignment: .leading, spacing: 9) {
            header("Crypto", "bitcoinsign.bank.building")
            if !prices.isEmpty {
                if tiny {
                    if let first = prices.first { cryptoRow(first, big: true) }
                } else if wide {
                    HStack(spacing: 16) {
                        ForEach(prices.prefix(veryWide ? 4 : 3)) { price in cryptoRow(price).frame(maxWidth: .infinity) }
                    }
                } else {
                    ForEach(prices.prefix(expanded ? 5 : 3)) { price in cryptoRow(price) }
                }
                Spacer(minLength: 0)
                feedFooter("LIVE · COINGECKO · USD")
            } else if let cryptoError {
                feedErrorView(cryptoError) { if let item { Task { await loadCrypto(item) } } }
            } else {
                feedLoadingView("Fetching prices…")
            }
        }
    }
    private func cryptoRow(_ entry: LiveFeed.CryptoPrice, big: Bool = false) -> some View {
        let up = entry.change24h >= 0
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name).font(.system(size: big ? 16 : 11, weight: .semibold, design: .rounded)).lineLimit(1)
                if big { Text(entry.id.capitalized).font(.system(size: 8, weight: .medium)).foregroundStyle(Palette.muted) }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 1) {
                Text(Self.usdPrice(entry.price)).font(.system(size: big ? 30 : 13, weight: .medium, design: .rounded)).monospacedDigit().contentTransition(.numericText())
                HStack(spacing: 3) {
                    Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
                    Text(String(format: "%+.1f%%", entry.change24h))
                }.font(.system(size: 9, weight: .semibold)).foregroundStyle(up ? Color(hex: "30D158") : Color(hex: "FF453A"))
            }
        }
    }
    private static func usdPrice(_ value: Double) -> String {
        value >= 1000 ? "$" + String(format: "%.0f", value) : (value >= 1 ? String(format: "$%.2f", value) : String(format: "$%.4f", value))
    }
    private var currenciesCard: some View {
        let rows = rateRows ?? []
        return VStack(alignment: .leading, spacing: 9) {
            header("Currencies", "dollarsign.circle")
            if !rows.isEmpty {
                if let item {
                    Text("1 \(item.currencyBase) =").font(.system(size: tiny ? 14 : 11, weight: .medium)).foregroundStyle(.white.opacity(0.72))
                }
                if wide {
                    HStack(spacing: 14) {
                        ForEach(Array(rows.prefix(veryWide ? 4 : 3).enumerated()), id: \.offset) { _, row in
                            VStack(alignment: .leading, spacing: 3) { Text(row.0).font(.system(size: 10, weight: .semibold)).foregroundStyle(accentColor); Text(String(format: "%.2f", row.1)).font(.system(size: veryWide ? 24 : 18, weight: .light, design: .rounded)).monospacedDigit() }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } else {
                    ForEach(Array(rows.prefix(expanded ? 4 : 2).enumerated()), id: \.offset) { _, row in
                        HStack { Text(row.0).font(.system(size: 11, weight: .semibold)).foregroundStyle(accentColor); Spacer(); Text(String(format: "%.4f", row.1)).font(.system(size: 13, weight: .medium, design: .rounded)).monospacedDigit() }
                    }
                }
                Spacer(minLength: 0)
                feedFooter("LIVE · FRANKFURTER · ECB RATES\(ratesDate.map { " · \($0)" } ?? "")")
            } else if let ratesError {
                feedErrorView(ratesError) { if let item { Task { await loadRates(item) } } }
            } else {
                feedLoadingView("Fetching exchange rates…")
            }
        }
    }
    private var githubCard: some View {
        let feed = githubFeedData
        let hasToken = LiveFeed.GitHubKeychain.load() != nil
        let repoSlug = item?.githubRepo ?? ""
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                header("GitHub", "chevron.left.forwardslash.chevron.right")
                Spacer(minLength: 4)
                if let total = feed.totalContributions {
                    Text("\(total) contributions").font(.system(size: 7, weight: .bold)).tracking(0.5).foregroundStyle(Palette.muted)
                }
            }
            if !hasToken {
                HStack(spacing: 6) {
                    Image(systemName: "key.fill").font(.system(size: 9)).foregroundStyle(accentColor)
                    Text("Add an access token in the library for reviews, PRs, inbox, and your contribution graph.").font(.system(size: 8)).foregroundStyle(.white.opacity(0.6)).fixedSize(horizontal: false, vertical: true)
                }
            }
            if hasToken {
                HStack(spacing: 6) {
                    githubTile("Review", feed.reviews, "BF5AF2", "eyeglasses")
                    githubTile("Issues", feed.issues, "0A84FF", "exclamationmark.circle")
                    githubTile("PRs", feed.prs, "FF9F0A", "arrow.triangle.pull")
                    githubTile("Inbox", feed.inbox, "32ADE6", "tray.fill")
                }
            }
            if !feed.heatmap.isEmpty, !tiny {
                contributionHeatmap(feed.heatmap)
            }
            if let stars = feed.stars, !repoSlug.isEmpty {
                HStack(spacing: 8) {
                    if let conclusion = feed.runConclusion ?? feed.runStatus {
                        let success = conclusion == "success"
                        let running = conclusion == "in_progress" || conclusion == "queued"
                        Image(systemName: running ? "circle.dotted" : (success ? "checkmark.circle.fill" : "xmark.circle.fill"))
                            .font(.system(size: 10))
                            .foregroundStyle(running ? Color(hex: "FFD60A") : (success ? Color(hex: "30D158") : Color(hex: "FF453A")))
                    }
                    Text(repoSlug).font(.system(size: 9.5, weight: .semibold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 4)
                    githubFact("STAR", stars, "star.fill")
                    if let issues = feed.openIssues { githubFact("ISSUE", issues, "exclamationmark.circle") }
                }
                .padding(8)
                .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))
            }
            Spacer(minLength: 0)
            HStack {
                feedFooter(hasToken ? "GITHUB API · TOKEN IN KEYCHAIN" : "GITHUB API · PUBLIC")
                Spacer()
                if !repoSlug.isEmpty {
                    Button { openWebAddress("https://github.com/\(repoSlug)") } label: { Image(systemName: "arrow.up.right.square") }.font(.system(size: 9, weight: .semibold)).buttonStyle(FullAreaButtonStyle()).foregroundStyle(accentColor).help("Open repository")
                }
            }
        }
    }
    private func githubTile(_ label: String, _ count: Int, _ colorHex: String, _ symbol: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(Color(hex: colorHex))
            Text("\(count)").font(.system(size: tiny ? 14 : 18, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(label).font(.system(size: 7, weight: .semibold)).foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, tiny ? 7 : 10)
        .background(Color(hex: colorHex).opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: colorHex).opacity(0.3), lineWidth: 1))
    }
    private func contributionHeatmap(_ weeks: [[Int]]) -> some View {
        let shown = weeks.suffix(tiny ? 12 : (expanded ? 22 : 18))
        return HStack(alignment: .top, spacing: 2) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, week in
                VStack(spacing: 2) {
                    ForEach(0..<7, id: \.self) { day in
                        let count = day < week.count ? week[day] : 0
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(count == 0 ? Color.white.opacity(0.06) : (count < 3 ? Color(hex: "0E4429") : (count < 6 ? Color(hex: "006D32") : (count < 10 ? Color(hex: "26A641") : Color(hex: "39D353")))))
                            .frame(height: expanded ? 8 : 6)
                    }
                }
            }
        }
    }
    private func githubFact(_ label: String, _ value: Int, _ symbol: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 9)).foregroundStyle(accentColor)
            Text("\(value)").font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(label).font(.system(size: 7, weight: .bold)).tracking(0.6).foregroundStyle(Palette.muted)
        }
    }
    private static func repoDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) {
            return date.formatted(.relative(presentation: .named))
        }
        return iso
    }
    private var speedTestCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            header("Speed Test", "wifi")
            switch speedState {
            case .idle:
                if let last = lastSpeedResult {
                    speedResultView(last)
                } else {
                    Spacer(minLength: 0)
                    Text("Measure your real download, upload, and latency against Cloudflare.").font(.system(size: 9)).foregroundStyle(.white.opacity(0.62)).fixedSize(horizontal: false, vertical: true)
                }
            case .running(let phase):
                Spacer(minLength: 0)
                ProgressView().controlSize(.small).tint(accentColor).frame(maxWidth: .infinity)
                Text(phase).font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.75)).frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            case .done(let result):
                speedResultView(result)
            case .failed(let message):
                feedErrorView(message) { Task { await startSpeedTest() } }
            }
            Button { Task { await startSpeedTest() } } label: {
                Label(speedState.isRunning ? "Testing…" : (lastSpeedResult == nil && speedState.isIdle ? "Run Test" : "Run Again"), systemImage: "bolt.horizontal")
                    .font(.system(size: 9, weight: .semibold)).buttonStyle(FullAreaButtonStyle()).foregroundStyle(accentColor)
            }.disabled(speedState.isRunning)
            if expanded { feedFooter("CLOUDFLARE SPEED · DOWNLOADS 25 MB ONCE") }
            Spacer(minLength: 0)
        }
    }
    @State private var lastSpeedResult: LiveFeed.SpeedTestResult?
    private func speedResultView(_ result: LiveFeed.SpeedTestResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                speedMetric("DOWN", String(format: "%.1f", result.downloadMbps), "Mbps")
                speedMetric("UP", String(format: "%.1f", result.uploadMbps), "Mbps")
                speedMetric("PING", String(format: "%.0f", result.latencyMs), "ms")
            }
            if expanded { Text("MEASURED FROM THIS MAC · CLOUDFLARE").font(.system(size: 6, weight: .bold)).tracking(0.7).foregroundStyle(.white.opacity(0.4)) }
        }
    }
    private func speedMetric(_ label: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 7, weight: .bold)).tracking(0.8).foregroundStyle(Palette.muted)
            HStack(alignment: .firstTextBaseline, spacing: 3) { Text(value).font(.system(size: expanded ? 26 : 21, weight: .light, design: .rounded)).monospacedDigit(); Text(unit).font(.system(size: 8, weight: .medium)).foregroundStyle(.white.opacity(0.6)) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func startSpeedTest() async {
        do {
            let result = try await LiveFeed.runSpeedTest { phase in speedState = .running(phase) }
            lastSpeedResult = result
            speedState = .done(result)
        } catch {
            speedState = .failed("Test failed. Check your connection and try again.")
        }
    }
    // App Time: hourly stacked chart colored by category, category totals, and
    // the day's apps with real icons — like the reference widget. Reads the
    // shared AppUsageMonitor on a 15-second cadence.
    private var appTimeCard: some View {
        TimelineView(.periodic(from: .now, by: 15)) { _ in
            appTimeContent
        }
    }
    private var appTimeContent: some View {
        let monitor = AppUsageMonitor.shared
        let entries = monitor.usage.sorted { $0.value > $1.value }.filter { $0.value > 0 }
        let total = monitor.usage.values.reduce(0, +)
        let buckets = monitor.categoryHourly
        let peak = buckets.values.flatMap { $0 }.max() ?? 0
        let scale = max(1800, Int((Double(peak) / 1800).rounded() * 1800))
        let categoryTotals = buckets.map { category, hours -> (String, Int) in (category, hours.reduce(0, +)) }
            .filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }
        let appIcon = { (app: String) -> NSImage in
            if let bundleID = monitor.bundleIDs[app], let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                return NSWorkspace.shared.icon(forFile: url.path)
            }
            return NSWorkspace.shared.icon(forFile: "/Applications")
        }
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                userAvatar
                Text(Self.durationText(total)).font(.system(size: tiny ? 22 : 26, weight: .light, design: .rounded)).monospacedDigit()
                Spacer(minLength: 0)
            }
            if tiny {
                Spacer(minLength: 0)
                Text("TODAY").font(.system(size: 8, weight: .bold)).tracking(0.8).foregroundStyle(Palette.muted)
                Spacer(minLength: 0)
            } else {
                appTimeChart(buckets: buckets, scale: scale)
                if !categoryTotals.isEmpty {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(Array(categoryTotals.prefix(expanded ? 3 : 2)), id: \.0) { category, seconds in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(category).font(.system(size: 8.5, weight: .semibold)).foregroundStyle(Color(hex: Self.categoryColor(category)))
                                Text(Self.durationText(seconds)).font(.system(size: 8.5)).foregroundStyle(Palette.muted)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
                if !entries.isEmpty {
                    Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(entries.prefix(expanded ? 5 : 3), id: \.key) { app, seconds in
                            HStack(spacing: 8) {
                                Image(nsImage: appIcon(app)).resizable().frame(width: 19, height: 19).clipShape(RoundedRectangle(cornerRadius: 5))
                                Text(app).font(.system(size: 10, weight: .medium)).lineLimit(1)
                                Spacer(minLength: 4)
                                Text(Self.durationText(seconds)).font(.system(size: 9.5, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(.white.opacity(0.7))
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
                feedFooter("TRACKED LOCALLY · RESETS AT MIDNIGHT")
            }
        }
    }
    private var userAvatar: some View {
        let name = NSUserName()
        let initials = name.prefix(2).uppercased()
        return ZStack {
            Circle().fill(LinearGradient(colors: [accentColor.opacity(0.8), accentColor.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(String(initials)).font(.system(size: tiny ? 11 : 13, weight: .bold, design: .rounded)).foregroundStyle(Palette.background)
        }
        .frame(width: tiny ? 26 : 34, height: tiny ? 26 : 34)
    }
    private static func categoryColor(_ category: String) -> String {
        AppUsageMonitor.appCategories.first { $0.name == category }?.color ?? "FF9F0A"
    }
    private func appTimeChart(buckets: [String: [Int]], scale: Int) -> some View {
        // One canvas-like layout: gridlines and stacked bars share the same plot
        // rect, so the axis labels and bars always line up.
        let hourLabels = [(0, "12 AM"), (6, "6 AM"), (12, "12 PM"), (18, "6 PM")]
        return VStack(spacing: 3) {
            GeometryReader { geo in
                let plotHeight = geo.size.height
                let barSlot = geo.size.width / 24
                ZStack(alignment: .bottomLeading) {
                    ForEach([0.5, 1.0], id: \.self) { fraction in
                        VStack(spacing: 1) {
                            Text(Self.durationText(Int(Double(scale) * fraction)))
                                .font(.system(size: 6.5, weight: .medium))
                                .foregroundStyle(Palette.muted.opacity(0.7))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .offset(y: fraction == 1 ? -1 : 0)
                            Rectangle().fill(.white.opacity(0.08)).frame(height: 0.5)
                        }
                        .frame(height: plotHeight * CGFloat(fraction), alignment: .top)
                        .frame(maxHeight: plotHeight, alignment: .bottom)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    HStack(alignment: .bottom, spacing: barSlot * 0.22) {
                        ForEach(0..<24, id: \.self) { hour in
                            let segments: [(Double, Color)] = AppUsageMonitor.appCategories.compactMap { category in
                                let seconds = buckets[category.name]?[hour] ?? 0
                                guard seconds > 0 else { return nil }
                                return (Double(seconds), Color(hex: category.color))
                            }
                            VStack(spacing: 1) {
                                if segments.isEmpty {
                                    RoundedRectangle(cornerRadius: 1.5).fill(.white.opacity(0.05)).frame(height: 3)
                                } else {
                                    ForEach(Array(segments.reversed().enumerated()), id: \.offset) { _, segment in
                                        RoundedRectangle(cornerRadius: 1.5).fill(segment.1)
                                            .frame(height: max(3, plotHeight * CGFloat(segment.0 / Double(scale))))
                                    }
                                }
                            }
                            .frame(width: max(2.5, barSlot * 0.6), alignment: .bottom)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, barSlot * 0.5 - max(2.5, barSlot * 0.6) / 2)
                }
            }
            HStack(spacing: 0) {
                ForEach(hourLabels, id: \.1) { hour, label in
                    Text(label).font(.system(size: 6.5, weight: .medium)).foregroundStyle(Palette.muted)
                    if hour != 18 { Spacer(minLength: 0) }
                }
            }
        }
        .frame(height: wide ? 84 : (expanded ? 104 : 80))
    }
    private static func durationText(_ seconds: Int) -> String {
        guard seconds > 0 else { return "0m" }
        if seconds < 60 { return "\(seconds)s" }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
    private static func metricFacts(_ kind: WidgetKind) -> [(String, String)] {
        switch kind {
        case .unitConverter: return [("Miles", "0.62 mi"), ("Feet", "3,281 ft"), ("Inches", "39,370 in"), ("Based on", "1 kilometer")]
        case .smartHome: return [("Accessories", "Use Apple Home"), ("Control", "Home app")]
        default: return [("Details", "Local preview"), ("Status", "No external source")]
        }
    }
    @ViewBuilder private func metricAction(_ kind: WidgetKind) -> some View {
        switch kind {
        case .smartHome: Button { openApp("com.apple.Home") } label: { Label("Open Home", systemImage: "arrow.up.right.square") }.font(.system(size: 8, weight: .semibold)).buttonStyle(FullAreaButtonStyle()).foregroundStyle(accentColor)
        default: EmptyView()
        }
    }
    private func openApp(_ bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
    // Toolbox: real system toggles with live states. Stay awake runs caffeinate
    // with a duration; Finder toggles apply defaults and restart Finder briefly.
    private var toolboxCard: some View {
        let tools = (item?.toolboxTools ?? []).compactMap { ToolboxTool(rawValue: $0) }
        let toolsPerRow = tiny ? 3 : (wide ? (veryWide ? 5 : 4) : (expanded ? 5 : 4))
        let rows = stride(from: 0, to: tools.count, by: toolsPerRow).map { Array(tools[$0..<min($0 + toolsPerRow, tools.count)]) }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                header("Toolbox", "wrench.and.screwdriver.fill")
                Spacer(minLength: 4)
                if Toolbox.stayAwakeRemaining != nil, expanded || wide {
                    HStack(spacing: 5) {
                        Image(systemName: "cup.and.saucer.fill").font(.system(size: 8)).foregroundStyle(accentColor)
                        Text("Awake \(Self.durationShort(Toolbox.stayAwakeRemaining!))").font(.system(size: 8, weight: .semibold)).monospacedDigit().foregroundStyle(accentColor)
                    }.padding(.horizontal, 7).padding(.vertical, 3).background(accentColor.opacity(0.14), in: Capsule())
                }
            }
            if tools.isEmpty {
                Text("Enable tools in the widget settings.").font(.system(size: 9)).foregroundStyle(Palette.muted)
            }
            VStack(spacing: 8) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 8) {
                        ForEach(row) { tool in
                            toolboxTile(tool)
                        }
                    }
                }
            }
            if !tiny, let active = Toolbox.stayAwakeRemaining {
                HStack(spacing: 5) {
                    Text("STAY AWAKE").font(.system(size: 6, weight: .bold)).tracking(0.8).foregroundStyle(Palette.muted)
                    Text("ON · \(Self.durationShort(active)) LEFT").font(.system(size: 6, weight: .bold)).tracking(0.6).foregroundStyle(accentColor)
                    Spacer(minLength: 0)
                }
            }
            Spacer(minLength: 0)
        }
    }
    @State private var stayAwakeDuration = 60
    private func toolboxTile(_ tool: ToolboxTool) -> some View {
        let isActive: Bool
        switch tool {
        case .darkMode: isActive = !model.systemIsDark ? false : true
        case .hideIcons: isActive = toolboxDesktopHidden
        case .hiddenFiles: isActive = toolboxHiddenFiles
        case .mute: isActive = toolboxMuted
        case .stayAwake: isActive = Toolbox.stayAwakeRemaining != nil
        default: isActive = false
        }
        return Button {
            switch tool {
            case .stayAwake: Toolbox.toggleStayAwake(minutes: stayAwakeDuration)
            case .darkMode: Toolbox.toggleDarkMode()
            case .hideIcons: Toolbox.setDesktopHidden(!toolboxDesktopHidden)
            case .hiddenFiles: Toolbox.setShowHiddenFiles(!toolboxHiddenFiles)
            case .mute: Toolbox.toggleMute(); toolboxMuted.toggle()
            case .ejectAll: Toolbox.ejectAll()
            case .displayOff: Toolbox.displayOff()
            case .screenSaver: Toolbox.startScreenSaver()
            case .screenshot: Toolbox.takeScreenshot()
            }
            if tool == .hideIcons { toolboxDesktopHidden.toggle() }
            if tool == .hiddenFiles { toolboxHiddenFiles.toggle() }
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isActive ? accentColor.opacity(0.22) : .white.opacity(0.07))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(isActive ? accentColor.opacity(0.7) : .white.opacity(0.06), lineWidth: 1))
                    Image(systemName: tool.symbol)
                        .font(.system(size: tiny ? 13 : 15, weight: .medium))
                        .foregroundStyle(isActive ? accentColor : .white.opacity(0.85))
                }
                .frame(height: tiny ? 30 : 34)
                Text(tool.name).font(.system(size: 7.5, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.75).foregroundStyle(.white.opacity(0.72))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(FullAreaButtonStyle())
        .help(tool.name)
    }
    // Apps widget: user-picked launcher with Grid / Dock / List / Tiles looks,
    // running-app dots, and per-size capacity — like the reference widget.
    private var appsCard: some View {
        let catalog = LiveFeed.applicationCatalog()
        let paths = Dictionary(catalog.map { ($0.name, $0.path) }, uniquingKeysWith: { first, _ in first })
        let chosen = (item?.appsList ?? []).compactMap { name -> (name: String, path: String)? in
            guard let path = paths[name] else { return nil }
            return (name, path)
        }
        let look = item?.appsLook ?? "grid"
        let runningNames = Set(NSWorkspace.shared.runningApplications.compactMap { $0.localizedName })
        let cols: Int = {
            switch item?.size {
            case .tile1x1, .small: return 2
            case .tile1x2: return 2
            case .tile2x1: return 4
            case .tile2x2, .large: return 3
            case .tile2x3: return 3
            case .tile3x1: return 5
            case .tile3x2: return 5
            default: return 4
            }
        }()
        let rows: Int = {
            switch item?.size {
            case .tile1x1, .small: return 2
            case .tile1x2: return 3
            case .tile2x1: return 1
            case .tile2x2, .large: return 3
            case .tile2x3: return 5
            case .tile3x1: return 2
            case .tile3x2: return 3
            default: return 3
            }
        }()
        let capacity = cols * rows
        let iconSide: CGFloat = {
            let size = item?.appsIconSize ?? "auto"
            if size == "small" { return 26 }
            if size == "medium" { return 36 }
            if size == "large" { return 50 }
            return min(46, max(26, 150 / CGFloat(max(1, cols)) + 10))
        }()
        return VStack(alignment: .leading, spacing: 8) {
            header("Apps", "square.grid.2x2.fill")
            if chosen.isEmpty {
                Spacer(minLength: 0)
                Text("Add your favorite apps in the library — they launch right from here.").font(.system(size: 9)).foregroundStyle(.white.opacity(0.62)).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            } else if look == "list" {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(chosen.prefix(expanded ? 7 : (tall ? 6 : 3))), id: \.path) { app in
                        appsListRow(app: app, running: runningNames.contains(app.0), markRunning: item?.appsMarkRunning ?? true, iconSide: 22)
                    }
                }
                Spacer(minLength: 0)
            } else if look == "dock" {
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    ForEach(Array(chosen.prefix(capacity)), id: \.path) { app in
                        appsIcon(app: app, running: runningNames.contains(app.0), markRunning: item?.appsMarkRunning ?? true, side: iconSide, showName: false, boxed: false)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                Spacer(minLength: 0)
            } else {
                let visible = Array(chosen.prefix(capacity))
                let rowsOfApps = stride(from: 0, to: visible.count, by: cols).map { Array(visible[$0..<min($0 + cols, visible.count)]) }
                VStack(spacing: 7) {
                    ForEach(Array(rowsOfApps.enumerated()), id: \.offset) { _, rowApps in
                        HStack(spacing: 8) {
                            ForEach(rowApps, id: \.path) { app in
                                appsIcon(app: app, running: runningNames.contains(app.0), markRunning: item?.appsMarkRunning ?? true, side: iconSide, showName: item?.appsShowNames ?? false, boxed: look == "tiles")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
    }
    private func appsIcon(app: (name: String, path: String), running: Bool, markRunning: Bool, side: CGFloat, showName: Bool, boxed: Bool) -> some View {
        Button {
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: app.path), configuration: NSWorkspace.OpenConfiguration())
        } label: {
            VStack(spacing: 3) {
                ZStack(alignment: .bottom) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                        .resizable()
                        .frame(width: side, height: side)
                        .clipShape(RoundedRectangle(cornerRadius: side * 0.22, style: .continuous))
                        .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
                    if markRunning && running {
                        Circle().fill(Color(hex: "30D158")).frame(width: 5, height: 5).offset(y: 3)
                    }
                }
                .frame(height: side + 5)
                if showName {
                    Text(app.name).font(.system(size: 7.5, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8).foregroundStyle(.white.opacity(0.7))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, boxed ? 6 : 2)
            .background(boxed ? Color.white.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(FullAreaButtonStyle())
        .help("Open \(app.name)")
    }
    private func appsListRow(app: (name: String, path: String), running: Bool, markRunning: Bool, iconSide: CGFloat) -> some View {
        Button {
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: app.path), configuration: NSWorkspace.OpenConfiguration())
        } label: {
            HStack(spacing: 8) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.path)).resizable().frame(width: iconSide, height: iconSide).clipShape(RoundedRectangle(cornerRadius: 5))
                Text(app.name).font(.system(size: 10, weight: .medium)).lineLimit(1)
                Spacer(minLength: 4)
                if markRunning && running {
                    Circle().fill(Color(hex: "30D158")).frame(width: 5, height: 5)
                }
                Image(systemName: "arrow.up.right").font(.system(size: 7)).foregroundStyle(Palette.muted)
            }
            .padding(6)
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(FullAreaButtonStyle())
        .help("Open \(app.name)")
    }
    // Day Progress: sky-coloured card with a sun/moon arc tracking the time of
    // day. Counts the whole day or a custom "My hours" window (wraps midnight),
    // with Sky or Theme colours.
    @State private var dayClockTick = Date.now
    private var dayProgressCard: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let geometry = dayProgressGeometry(at: context.date)
            return VStack(alignment: .leading, spacing: 8) {
                if !tiny {
                    HStack(spacing: 8) {
                        header(context.date.formatted(.dateTime.weekday(.wide)), "sun.and.horizon.fill")
                        Spacer(minLength: 4)
                        HStack(spacing: 4) {
                            Image(systemName: "moon.fill").font(.system(size: 8)).foregroundStyle(Color(hex: "AFC4FF"))
                            Text(Self.lunarState(at: context.date).name).font(.system(size: 8, weight: .medium)).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 0)
                if !tiny {
                    dayProgressArc(progress: geometry.fraction, isDay: geometry.isDay, size: wide ? (veryWide ? 150 : 110) : (expanded ? 120 : 90))
                        .frame(maxWidth: .infinity)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(Int((geometry.fraction * 100).rounded()))%")
                        .font(.system(size: tiny ? 34 : (wide ? 44 : 38), weight: .light, design: .rounded)).monospacedDigit()
                    Text(tiny ? "of the day" : (item?.dayProgressCounts == "hours" ? "of your hours" : "of the day"))
                        .font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.66))
                    Spacer(minLength: 0)
                    if !tiny {
                        Text("\(Self.durationText(Int(geometry.remaining))) left").font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.6))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                if tiny {
                    HStack(spacing: 4) {
                        Image(systemName: "moon.fill").font(.system(size: 7)).foregroundStyle(Color(hex: "AFC4FF"))
                        Text(Self.lunarState(at: context.date).name).font(.system(size: 7.5, weight: .medium)).foregroundStyle(Palette.muted).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
                Spacer(minLength: 0)
            }
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { tick in dayClockTick = tick }
        }
    }
    private func dayProgressGeometry(at date: Date) -> (fraction: Double, remaining: Double, isDay: Bool) {
        let calendar = Calendar.current
        let secondsOfDay = Double(calendar.component(.hour, from: date) * 3600 + calendar.component(.minute, from: date) * 60 + calendar.component(.second, from: date))
        var windowStart = 0.0
        var windowLength = 86400.0
        if item?.dayProgressCounts == "hours" {
            let from = min(max(item?.dayProgressFrom ?? 9, 0), 24) * 3600
            let until = min(max(item?.dayProgressUntil ?? 17, 0), 24) * 3600
            if until > from {
                windowStart = from
                windowLength = until - from
            } else if until < from {
                // Wraps past midnight, like the reference describes.
                windowStart = from
                windowLength = 86400 - from + until
            } else {
                windowStart = from
                windowLength = 3600
            }
        }
        var elapsed = secondsOfDay - windowStart
        if elapsed < 0 { elapsed += 86400 }
        let fraction = windowLength > 0 ? min(1, max(0, elapsed / windowLength)) : 0
        let remaining = max(0, windowLength - min(elapsed, windowLength))
        let hour = Double(calendar.component(.hour, from: date)) + Double(calendar.component(.minute, from: date)) / 60
        return (fraction, remaining, hour >= 6.5 && hour < 18.5)
    }
    private func dayProgressArc(progress: Double, isDay: Bool, size: CGFloat) -> some View {
        let clamped = min(1, max(0, progress))
        let angle = Double.pi * (1 - clamped)
        let radius = size * 0.42
        let center = CGPoint(x: size / 2, y: size * 0.78)
        let discX = center.x - radius * cos(angle) * 1.0
        let discY = center.y - radius * sin(angle)
        return ZStack {
            Path { path in
                path.addArc(center: center, radius: radius, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true)
            }
            .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [2, 4]))
            .foregroundStyle(.white.opacity(0.4))
            Circle()
                .fill(isDay ? Color(hex: "FFD35F") : Color(hex: "D6DFFF"))
                .frame(width: size * 0.14, height: size * 0.14)
                .shadow(color: (isDay ? Color(hex: "FFD35F") : Color(hex: "AFC4FF")).opacity(0.8), radius: 8)
                .position(x: discX, y: discY)
            // Sibling in the arc's coordinate space — positioning the icon inside
            // an overlay of the small disc used to throw it off the card.
            Image(systemName: isDay ? "sun.max.fill" : "moon.fill")
                .font(.system(size: size * 0.055))
                .foregroundStyle(isDay ? Color(hex: "B8860B") : Color(hex: "5A6B9E"))
                .position(x: discX, y: discY)
        }
        .frame(width: size, height: size * 0.82)
    }
    static func daySkyColors(hour: Double) -> [Color] {
        switch hour {
        case 5..<7.5: return [Color(hex: "FF9A56"), Color(hex: "C86DD7")]
        case 7.5..<10: return [Color(hex: "4A90D9"), Color(hex: "87CEEB")]
        case 10..<16: return [Color(hex: "3D87D6"), Color(hex: "7EC8F0")]
        case 16..<18.5: return [Color(hex: "F2994A"), Color(hex: "F2C94C")]
        case 18.5..<20.5: return [Color(hex: "7B4397"), Color(hex: "DC2430")]
        default: return [Color(hex: "2C3E70"), Color(hex: "4B3A78")]
        }
    }
    private func quickActionsCard(_ kind: WidgetKind) -> some View {
        let actions: [(String, String, String)]
        switch kind {
        case .apps: actions = [("Safari", "Safari", "com.apple.Safari"), ("Notes", "Notes", "com.apple.Notes"), ("Music", "Music", "com.apple.Music"), ("Calendar", "Calendar", "com.apple.iCal")]
        default: actions = [("Shortcuts", "Shortcuts", "com.apple.shortcuts"), ("Music", "Music", "com.apple.Music"), ("Notes", "Notes", "com.apple.Notes")]
        }
        return VStack(alignment: .leading, spacing: 9) {
            header(kind.rawValue, kind.symbol)
            if tiny {
                Button { openApp(actions[0].2) } label: { Label("Open \(actions[0].0)", systemImage: "arrow.up.right.square") }
                    .font(.system(size: 10, weight: .semibold)).buttonStyle(FullAreaButtonStyle()).foregroundStyle(accentColor)
                if kind == .shortcut {
                    Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(Date.now.formatted(date: .complete, time: .shortened), forType: .string) } label: { Label("Copy date", systemImage: "doc.on.doc") }
                        .font(.system(size: 9)).buttonStyle(FullAreaButtonStyle()).foregroundStyle(.white.opacity(0.75))
                }
                Spacer(minLength: 0)
            } else if wide {
                HStack(spacing: 9) {
                    ForEach(actions.prefix(veryWide ? 4 : 3), id: \.0) { title, symbol, bundleID in
                        Button { openApp(bundleID) } label: { VStack(spacing: 7) { Image(systemName: symbol == "System Settings" ? "gearshape" : "app.fill").font(.system(size: 16)); Text(title).font(.system(size: 8, weight: .medium)).lineLimit(1) }.frame(maxWidth: .infinity).padding(8).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 9)) }
                            .buttonStyle(FullAreaButtonStyle()).foregroundStyle(.white.opacity(0.9))
                    }
                }
                Spacer(minLength: 0)
            } else {
                ForEach(actions.prefix(expanded ? actions.count : 2), id: \.0) { title, _, bundleID in
                    Button { openApp(bundleID) } label: { HStack { Image(systemName: "arrow.up.right.square").foregroundStyle(accentColor); Text("Open \(title)").font(.system(size: 10, weight: .medium)); Spacer(); Image(systemName: "arrow.up.right").font(.system(size: 8)).foregroundStyle(Palette.muted) }.padding(8).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8)) }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle()).foregroundStyle(.white)
                }
                Spacer(minLength: 0)
                if expanded { Text("OPEN AN APP · NO COMMANDS RUN").font(.system(size: 7, weight: .bold)).tracking(0.7).foregroundStyle(Palette.muted) }
            }
        }
    }
    private func mediaCard(_ kind: WidgetKind) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header(kind.rawValue, kind.symbol)
            Spacer(minLength: 0)
            Image(systemName: kind == .photos ? "photo.on.rectangle.angled" : "person.crop.rectangle").font(.system(size: tiny ? 28 : 40, weight: .light)).foregroundStyle(accentColor)
            Text(kind == .photos ? "Your photo library" : "Photo Booth mirror").font(.system(size: 13, weight: .semibold, design: .rounded))
            Text(kind == .photos ? "Open Photos to browse your albums." : "Open Photo Booth to use the camera.").font(.system(size: 9)).foregroundStyle(.white.opacity(0.62)).lineLimit(expanded ? 3 : 2)
            Button { openApp(kind == .photos ? "com.apple.Photos" : "com.apple.PhotoBooth") } label: { Label(kind == .photos ? "Open Photos" : "Open Photo Booth", systemImage: "arrow.up.right.square") }.font(.system(size: 9, weight: .semibold)).buttonStyle(FullAreaButtonStyle()).foregroundStyle(accentColor)
            if expanded { Text("CAMERA AND PHOTO LIBRARY STAY IN APPLE’S APP").font(.system(size: 7, weight: .bold)).tracking(0.55).foregroundStyle(Palette.muted) }
            Spacer(minLength: 0)
        }
    }
    private func fileUtilityCard(_ kind: WidgetKind) -> some View {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let folder: URL
        switch kind {
        case .trash: folder = home.appendingPathComponent(".Trash", isDirectory: true)
        case .dropZone: folder = home.appendingPathComponent("Downloads", isDirectory: true)
        case .disks: folder = URL(fileURLWithPath: "/", isDirectory: true)
        default: folder = home
        }
        let fileCount = (try? FileManager.default.contentsOfDirectory(atPath: folder.path).count)
        let capacity = try? FileManager.default.attributesOfFileSystem(forPath: home.path)
        let free = (capacity?[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        let total = (capacity?[.systemSize] as? NSNumber)?.int64Value ?? 0
        let value: String = kind == .disks ? "\(Self.gigabytes(free)) GB free" : (fileCount.map(String.init) ?? "—")
        let detail: String = kind == .disks ? "of \(Self.gigabytes(total)) GB on this Mac" : (kind == .trash ? "items in Trash" : kind == .dropZone ? "items in Downloads" : "items in your Home folder")
        return VStack(alignment: .leading, spacing: 10) {
            header(kind.rawValue, kind.symbol)
            Spacer(minLength: 0)
            Text(value).font(.system(size: tiny ? 25 : 34, weight: .light, design: .rounded)).lineLimit(1).minimumScaleFactor(0.65)
            Text(detail).font(.system(size: 9)).foregroundStyle(.white.opacity(0.64))
            if kind == .disks { ProgressView(value: total > 0 ? Double(total - free) / Double(total) : 0).tint(accentColor) }
            if expanded { Text(folder.path).font(.system(size: 8, design: .monospaced)).foregroundStyle(Palette.muted).lineLimit(2).textSelection(.enabled) }
            Button { NSWorkspace.shared.open(folder) } label: { Label("Open in Finder", systemImage: "folder") }.font(.system(size: 9, weight: .semibold)).buttonStyle(FullAreaButtonStyle()).foregroundStyle(accentColor)
            Spacer(minLength: 0)
        }
    }
    private static func gigabytes(_ bytes: Int64) -> Int { Int((Double(bytes) / 1_073_741_824).rounded()) }
    private func webPageCard(_ item: WidgetInstance) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            header("Web Page", "safari.fill")
            if let url = Self.webURL(item.webAddress) {
                InlineWebView(url: url)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "safari").font(.system(size: tiny ? 25 : 38)).foregroundStyle(accentColor)
                    Text("Add a full web address like https://rea.tools in widget settings.").font(.system(size: 9)).foregroundStyle(.white.opacity(0.62)).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack(spacing: 8) {
                Text(item.webAddress).font(.system(size: 8, design: .monospaced)).foregroundStyle(Palette.muted).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                Spacer(minLength: 4)
                Button { openWebAddress(item.webAddress) } label: { Image(systemName: "arrow.up.right") }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle()).foregroundStyle(accentColor).help("Open in browser")
            }
        }
    }
    private static func webURL(_ address: String) -> URL? {
        var value = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty, !value.contains("://") { value = "https://" + value }
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host != nil else { return nil }
        return url
    }
    private func openWebAddress(_ address: String) {
        let value = address.contains("://") ? address : "https://\(address)"
        if let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url) }
    }
    @State private var generatedPassword = "Tap Generate"
    private var passwordCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            header("Password Generator", "key.fill")
            Text(generatedPassword).font(.system(size: tiny ? 12 : 16, weight: .medium, design: .monospaced)).lineLimit(expanded ? 3 : 2).minimumScaleFactor(0.65).textSelection(.enabled)
            Spacer(minLength: 0)
            HStack {
                Button("Generate") { generatedPassword = Self.makePassword(length: expanded ? 24 : 16) }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle()).foregroundStyle(accentColor)
                Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(generatedPassword, forType: .string) } label: { Image(systemName: "doc.on.doc") }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle()).foregroundStyle(.white.opacity(0.75)).help("Copy password")
            }.font(.system(size: 10, weight: .semibold))
            if expanded { Text("Generated locally · not saved").font(.system(size: 8)).foregroundStyle(Palette.muted) }
        }
    }
    private static func makePassword(length: Int) -> String {
        let alphabet = Array("abcdefghjkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ23456789!@#$%")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).compactMap { _ in alphabet.randomElement(using: &generator) })
    }
    // Premium battery card: real IOKit stats (watts, health, cycles, temperature),
    // dynamic color states, and a charging pulse. Three styles: stat sheet gauge,
    // BetterMacWidgets-style rings, and rings for Bluetooth accessories.
    @ViewBuilder private var batteryCard: some View {
        switch item?.batteryStyle ?? .gauge {
        case .ring: batteryRingCard
        case .devices: batteryDevicesCard
        default: batteryGaugeCard
        }
    }
    private var batteryRingCard: some View {
        let stats = LiveFeed.batteryStats()
        let color = batteryColor(level: stats?.percent ?? 0, charging: stats?.charging == true)
        let ringSize: CGFloat = expanded ? 96 : (wide ? 84 : 72)
        return VStack(alignment: .leading, spacing: 10) {
            header("Battery", "battery.100percent")
            Spacer(minLength: 0)
            HStack(spacing: expanded ? 26 : 18) {
                BatteryRing(percent: stats?.percent ?? 0, charging: stats?.charging == true, color: color, icon: "laptopcomputer", size: ringSize, label: "This Mac")
                if let minutes = stats?.minutesRemaining, expanded {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(stats?.charging == true ? "TIME TO FULL" : "REMAINING").font(.system(size: 7, weight: .bold)).tracking(0.8).foregroundStyle(Palette.muted)
                        Text(Self.durationShort(minutes)).font(.system(size: 17, weight: .medium, design: .rounded)).monospacedDigit()
                        if let watts = stats?.watts { Text(String(format: "%.1f W", watts)).font(.system(size: 9, weight: .semibold)).foregroundStyle(accentColor) }
                        if batteryLowPower { Text("LOW POWER").font(.system(size: 7, weight: .bold)).foregroundStyle(Color(hex: "FFD60A")) }
                    }
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            feedFooter(stats?.charging == true ? "CHARGING · IOKIT LIVE" : (stats?.onAC == true ? "AC POWER · IOKIT LIVE" : "ON BATTERY · IOKIT LIVE"))
        }
    }
    private var batteryDevicesCard: some View {
        let stats = LiveFeed.batteryStats()
        let color = batteryColor(level: stats?.percent ?? 0, charging: stats?.charging == true)
        let ringSize: CGFloat = expanded ? 84 : (wide ? 76 : (tiny ? 64 : 68))
        let devices = Array(bluetoothBatteries.prefix(expanded ? 3 : 2))
        return VStack(alignment: .leading, spacing: 10) {
            header("Battery", "battery.100percent")
            Spacer(minLength: 0)
            if devices.isEmpty && !tiny {
                HStack(spacing: 14) {
                    BatteryRing(percent: stats?.percent ?? 0, charging: stats?.charging == true, color: color, icon: "laptopcomputer", size: ringSize, label: "This Mac")
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No accessories found").font(.system(size: 11, weight: .semibold, design: .rounded))
                        Text("Connect AirPods, a Magic Keyboard, or a mouse to see their batteries here.").font(.system(size: 9)).foregroundStyle(.white.opacity(0.6)).fixedSize(horizontal: false, vertical: true)
                        Button { openApp("com.apple.systempreferences") } label: { Label("Bluetooth Settings", systemImage: "dot.radiowaves.left.and.right") }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle()).font(.system(size: 9, weight: .semibold)).foregroundStyle(accentColor)
                    }
                    Spacer(minLength: 0)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: expanded ? 22 : 16) {
                        BatteryRing(percent: stats?.percent ?? 0, charging: stats?.charging == true, color: color, icon: "laptopcomputer", size: ringSize, label: "This Mac")
                        ForEach(devices) { device in
                            BatteryRing(percent: device.percent, charging: false, color: batteryColor(level: device.percent, charging: false), icon: device.icon, size: ringSize * 0.88, label: device.name)
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
            Spacer(minLength: 0)
            feedFooter(devices.isEmpty ? "CONNECT BLUETOOTH ACCESSORIES" : "THIS MAC + BLUETOOTH · LIVE")
        }
    }
    private var batteryGaugeCard: some View {
        let stats = LiveFeed.batteryStats()
        let level = stats?.percent ?? 0
        let color = batteryColor(level: level, charging: stats?.charging == true)
        return Group {
            if let stats {
                if tiny {
                    VStack(alignment: .leading, spacing: 8) {
                        header("Battery", "battery.100percent")
                        Spacer(minLength: 0)
                        BatteryGlyph(percent: stats.percent, charging: stats.charging, color: color, width: 52)
                            .frame(maxWidth: .infinity)
                        Text("\(stats.percent)%").font(.system(size: 34, weight: .light, design: .rounded)).monospacedDigit().frame(maxWidth: .infinity)
                        Text(stats.charging ? "Charging" : (stats.onAC ? "AC Power" : "On battery")).font(.system(size: 8, weight: .semibold)).foregroundStyle(.white.opacity(0.6)).frame(maxWidth: .infinity)
                        Spacer(minLength: 0)
                    }
                } else if wide {
                    HStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 7) {
                            header("Battery", "battery.100percent")
                            HStack(alignment: .center, spacing: 10) {
                                BatteryGlyph(percent: stats.percent, charging: stats.charging, color: color, width: 54)
                                Text("\(stats.percent)%").font(.system(size: veryWide ? 40 : 32, weight: .light, design: .rounded)).monospacedDigit()
                            }
                        }
                        Spacer(minLength: 0)
                        VStack(alignment: .leading, spacing: 7) {
                            batteryStateLabel(stats)
                            if let watts = stats.watts { batteryStatRow("POWER", String(format: "%.1f W", watts)) }
                            if let minutes = stats.minutesRemaining { batteryStatRow(stats.onAC && !stats.charging ? "FULL IN" : "REMAINING", Self.durationShort(minutes)) }
                            if let health = stats.healthPercent { batteryStatRow("HEALTH", "\(health)%") }
                        }
                        if veryWide {
                            VStack(alignment: .leading, spacing: 7) {
                                if let cycles = stats.cycleCount { batteryStatRow("CYCLES", "\(cycles)") }
                                if let temperature = stats.temperatureC { batteryStatRow("TEMP", String(format: "%.0f°C", temperature)) }
                                if batteryLowPower { batteryStatRow("LOW POWER", "On") }
                            }
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 11) {
                        HStack {
                            header("Battery", "battery.100percent")
                            if batteryLowPower {
                                Text("LOW POWER")
                                    .font(.system(size: 6, weight: .bold)).tracking(1)
                                    .foregroundStyle(Color(hex: "FFD60A"))
                                    .padding(.horizontal, 6).padding(.vertical, 3)
                                    .background(Color(hex: "FFD60A").opacity(0.14), in: Capsule())
                            }
                        }
                        HStack(alignment: .center, spacing: 14) {
                            BatteryGlyph(percent: stats.percent, charging: stats.charging, color: color, width: expanded ? 74 : 58)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(stats.percent)%").font(.system(size: expanded ? 46 : 34, weight: .light, design: .rounded)).monospacedDigit()
                                batteryStateLabel(stats)
                            }
                            Spacer(minLength: 0)
                        }
                        Rectangle().fill(.white.opacity(0.1)).frame(height: 1)
                        VStack(alignment: .leading, spacing: 7) {
                            if let minutes = stats.minutesRemaining {
                                HStack { Text(stats.charging ? "Time to full" : "Time remaining").font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.62)); Spacer(); Text(Self.durationShort(minutes)).font(.system(size: 10, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(color) }
                            }
                            if expanded, let watts = stats.watts {
                                HStack { Text("Power draw").font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.62)); Spacer(); Text(String(format: "%.1f W", watts)).font(.system(size: 10, weight: .semibold, design: .rounded)).monospacedDigit() }
                            }
                            if expanded, let health = stats.healthPercent {
                                HStack { Text("Battery health").font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.62)); Spacer(); Text("\(health)%").font(.system(size: 10, weight: .semibold, design: .rounded)).monospacedDigit() }
                            }
                            if expanded, let cycles = stats.cycleCount {
                                HStack { Text("Charge cycles").font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.62)); Spacer(); Text("\(cycles)").font(.system(size: 10, weight: .semibold, design: .rounded)).monospacedDigit() }
                            }
                            if expanded, let temperature = stats.temperatureC {
                                HStack { Text("Temperature").font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.62)); Spacer(); Text(String(format: "%.0f°C", temperature)).font(.system(size: 10, weight: .semibold, design: .rounded)).monospacedDigit() }
                            }
                        }
                        Spacer(minLength: 0)
                        feedFooter(stats.onAC ? "AC POWER · IOKIT LIVE" : "ON BATTERY · IOKIT LIVE")
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    header("Battery", "battery.100percent")
                    Spacer(minLength: 0)
                    Image(systemName: "powerplug.fill").font(.system(size: tiny ? 26 : 38, weight: .light)).foregroundStyle(accentColor).frame(maxWidth: .infinity)
                    Text("AC Power · No battery").font(.system(size: 11, weight: .semibold, design: .rounded)).frame(maxWidth: .infinity)
                    Text("This Mac runs on external power.").font(.system(size: 9)).foregroundStyle(.white.opacity(0.55)).frame(maxWidth: .infinity)
                    Spacer(minLength: 0)
                }
            }
        }
    }
    private func batteryColor(level: Int, charging: Bool) -> Color {
        // Dynamic color, matching the reference widget: red under 20, orange under
        // 40, green above, accent while charging.
        if model.uniformColors { return accentColor }
        if charging { return accentColor }
        if level < 20 { return Color(hex: "FF453A") }
        if level < 40 { return Color(hex: "FF9F0A") }
        return Color(hex: "30D158")
    }
    private func batteryStateLabel(_ stats: LiveFeed.BatteryStats) -> some View {
        HStack(spacing: 5) {
            if stats.charging {
                Image(systemName: "bolt.fill").font(.system(size: 8, weight: .bold))
                    .phaseAnimator([1, 0.45, 0.8], trigger: stats.charging) { view, phase in
                        view.opacity(phase)
                    } animation: { _ in
                        .easeInOut(duration: 0.7)
                    }
            }
            Text(stats.charging ? "Charging" : (stats.onAC ? "AC Power" : "On battery"))
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(accentColor)
    }
    private func batteryStatRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 7, weight: .bold)).tracking(0.8).foregroundStyle(Palette.muted)
            Text(value).font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
        }
    }
    private static func durationShort(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
    // Devices widget: paired Bluetooth devices with live battery bars and working
    // connect / disconnect buttons.
    private var devicesCard: some View {
        let sorted = sortDevices(pairedDevices)
        let visible = sorted.prefix(tiny ? 2 : (expanded ? 5 : (wide ? 4 : 3)))
        return VStack(alignment: .leading, spacing: 9) {
            header("Devices", "dot.radiowaves.left.and.right")
            if sorted.isEmpty {
                Spacer(minLength: 0)
                Text("No paired Bluetooth devices.").font(.system(size: 9)).foregroundStyle(Palette.muted).frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(visible), id: \.id) { device in
                        deviceRow(device)
                    }
                }
                Spacer(minLength: 0)
                feedFooter("\(sorted.filter { $0.connected }.count) CONNECTED · \(sorted.count) PAIRED")
            }
        }
    }
    private func sortDevices(_ devices: [LiveFeed.PairedDeviceInfo]) -> [LiveFeed.PairedDeviceInfo] {
        let allowed = (item?.showDisconnectedDevices ?? true) ? devices : devices.filter { $0.connected }
        let batteriesFirst: (LiveFeed.PairedDeviceInfo, LiveFeed.PairedDeviceInfo) -> Bool = { a, b in
            let levelA = a.batteryPercent ?? -1
            let levelB = b.batteryPercent ?? -1
            if levelA != levelB { return levelA > levelB }
            if a.connected != b.connected { return a.connected }
            return a.name < b.name
        }
        switch item?.deviceSort ?? "recent" {
        case "battery": return allowed.sorted(by: batteriesFirst)
        default:
            return allowed.sorted { a, b in
                if a.connected != b.connected { return a.connected }
                return a.name < b.name
            }
        }
    }
    // Disks widget: free-space ring, one row per mounted volume. Volumes appear
    // and disappear live; ejectable drives get an eject action; a disk with less
    // than a tenth free turns red and pulses.
    // Activity widget: CPU load with history chart, memory breakdown, and the
    // busiest programs. All activity widgets share one SystemMonitor sampler,
    // so every card updates together in real time.
    @State private var activitySample: SystemMonitor.Sample?
    private var activityCard: some View {
        let sample = activitySample
        let history = activityHistory
        let cpu = sample?.cpuPercent ?? 0
        let cpuColor = model.uniformColors ? accentColor : (cpu < 60 ? Color(hex: "30D158") : (cpu < 85 ? Color(hex: "FFD60A") : Color(hex: "FF453A")))
        return VStack(alignment: .leading, spacing: 10) {
            header("Activity", "waveform")
            if tiny {
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("CPU").font(.system(size: 9, weight: .bold)).tracking(0.8).foregroundStyle(Palette.muted)
                    Text("\(Int(cpu.rounded()))%").font(.system(size: 30, weight: .medium, design: .rounded)).monospacedDigit().foregroundStyle(cpuColor)
                }.frame(maxWidth: .infinity, alignment: .center)
                cpuChart(history, bars: 10, height: 26)
                Spacer(minLength: 0)
            } else if wide {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text("CPU").font(.system(size: 8, weight: .bold)).tracking(0.8).foregroundStyle(Palette.muted)
                            Text("\(Int(cpu.rounded()))%").font(.system(size: veryWide ? 34 : 27, weight: .medium, design: .rounded)).monospacedDigit().foregroundStyle(cpuColor)
                        }
                        cpuChart(history, bars: veryWide ? 20 : 14, height: 30)
                    }
                    if veryWide, let sample { memoryBlock(sample) }
                    Spacer(minLength: 0)
                }
                if !veryWide, let sample { memoryBlock(sample) }
                Spacer(minLength: 0)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text("CPU").font(.system(size: 9, weight: .bold)).tracking(0.8).foregroundStyle(Palette.muted)
                    Text("\(Int(cpu.rounded()))%").font(.system(size: 34, weight: .medium, design: .rounded)).monospacedDigit().foregroundStyle(cpuColor)
                    Spacer(minLength: 0)
                    if let pressure = sample?.pressure {
                        HStack(spacing: 4) {
                            Circle().fill(pressure == "Normal" ? Color(hex: "30D158") : (pressure == "Warning" ? Color(hex: "FFD60A") : Color(hex: "FF453A"))).frame(width: 5, height: 5)
                            Text(pressure).font(.system(size: 8, weight: .semibold)).foregroundStyle(.white.opacity(0.65))
                        }
                    }
                }
                cpuChart(history, bars: expanded ? 22 : 16, height: expanded ? 40 : 30)
                if let sample { memoryBlock(sample) }
                if item?.showProgramList ?? true, let programs = sample?.topPrograms, !programs.isEmpty, !narrow {
                    Rectangle().fill(.white.opacity(0.1)).frame(height: 1)
                    Text("BUSIEST").font(.system(size: 6.5, weight: .bold)).tracking(1).foregroundStyle(Palette.muted)
                    ForEach(programs.prefix(expanded ? 4 : 3)) { program in
                        HStack(spacing: 6) {
                            Text(program.name).font(.system(size: 9, weight: .medium)).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(String(format: "%.0f%%", program.percent)).font(.system(size: 9, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(.white.opacity(0.75))
                        }
                    }
                }
                Spacer(minLength: 0)
                feedFooter("SHARED SAMPLER · 2S · ALL WIDGETS SYNCED")
            }
        }
    }
    private var activityHistory: [Double] { SystemMonitor.shared.history }
    private func cpuChart(_ values: [Double], bars: Int, height: CGFloat) -> some View {
        GeometryReader { geometry in
            let shown = values.suffix(bars)
            HStack(alignment: .bottom, spacing: 2.5) {
                ForEach(Array(shown.enumerated()), id: \.offset) { _, value in
                    let color = value < 60 ? Color(hex: "30D158") : (value < 85 ? Color(hex: "FFD60A") : Color(hex: "FF453A"))
                    Capsule().fill(color).frame(maxWidth: .infinity).frame(height: max(3, geometry.size.height * CGFloat(value / 100)))
                }
                let missing = max(0, bars - shown.count)
                ForEach(0..<missing, id: \.self) { _ in
                    Capsule().fill(.white.opacity(0.08)).frame(maxWidth: .infinity).frame(height: 3)
                }
            }
            .frame(height: height, alignment: .bottom)
            .animation(.easeInOut(duration: 0.5), value: shown.count)
        }
        .frame(height: height)
    }
    private func memoryBlock(_ sample: SystemMonitor.Sample) -> some View {
        let usedFraction = sample.totalBytes > 0 ? Double(sample.usedBytes) / Double(sample.totalBytes) : 0
        let appFraction = sample.usedBytes > 0 ? Double(sample.appBytes) / Double(sample.usedBytes) : 0
        let wiredFraction = sample.usedBytes > 0 ? Double(sample.wiredBytes) / Double(sample.usedBytes) : 0
        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Memory").font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.72))
                Text(Self.capacityText(sample.usedBytes)).font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
                Spacer(minLength: 4)
                Text("of \(Self.capacityText(sample.totalBytes))").font(.system(size: 8)).foregroundStyle(Palette.muted)
            }
            GeometryReader { geo in
                HStack(spacing: 1) {
                    Capsule().fill(Color(hex: "5AC8FA")).frame(width: max(2, geo.size.width * appFraction))
                    Capsule().fill(Color(hex: "FFD35F")).frame(width: max(0, geo.size.width * wiredFraction))
                    Capsule().fill(Color(hex: "BF5AF2")).frame(width: max(0, geo.size.width * (max(0, 1 - appFraction - wiredFraction))))
                    Capsule().fill(.white.opacity(0.08)).frame(maxWidth: .infinity)
                }
            }.frame(height: 5)
            HStack(spacing: 8) {
                legendDot("App", Color(hex: "5AC8FA"))
                legendDot("Wired", Color(hex: "FFD35F"))
                legendDot("Compressed", Color(hex: "BF5AF2"))
                Spacer(minLength: 0)
            }
        }
    }
    private func legendDot(_ label: String, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 4, height: 4)
            Text(label).font(.system(size: 7, weight: .medium)).foregroundStyle(Palette.muted)
        }
    }
    private var disksCard: some View {
        let startup = mountedVolumes.first { $0.path == "/" } ?? mountedVolumes.first
        let shown = (item?.disksShowAll ?? true) ? mountedVolumes : startup.map { [$0] } ?? []
        let totalFree = shown.reduce(Int64(0)) { $0 + $1.free }
        let totalCapacity = shown.reduce(Int64(0)) { $0 + $1.total }
        let freeFraction = totalCapacity > 0 ? Double(totalFree) / Double(totalCapacity) : 0
        let ringColor = freeFraction < 0.1 ? Color(hex: "FF453A") : (freeFraction < 0.2 ? Color(hex: "FF9F0A") : Color(hex: "30D158"))
        let rowLimit = tiny ? 1 : (wide ? 2 : (expanded ? 4 : 3))
        return VStack(alignment: .leading, spacing: 10) {
            header("Disks", "internaldrive.fill")
            if tiny {
                Spacer(minLength: 0)
                diskRing(freeBytes: totalFree, fraction: freeFraction, color: ringColor, size: 74)
                    .frame(maxWidth: .infinity)
                if let startup {
                    diskRow(startup, showEject: false).padding(.horizontal, -4)
                }
                Spacer(minLength: 0)
            } else if wide {
                HStack(spacing: 16) {
                    diskRing(freeBytes: totalFree, fraction: freeFraction, color: ringColor, size: veryWide ? 96 : 82)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(shown.prefix(rowLimit)), id: \.id) { volume in
                            diskRow(volume, showEject: volume.isEjectable)
                        }
                    }
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
            } else {
                HStack(alignment: .center, spacing: 16) {
                    diskRing(freeBytes: totalFree, fraction: freeFraction, color: ringColor, size: expanded ? 104 : 88)
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(shown.prefix(rowLimit)), id: \.id) { volume in
                        diskRow(volume, showEject: volume.isEjectable)
                    }
                }
                Spacer(minLength: 0)
                feedFooter(shown.count == 1 ? "STARTUP DISK · LIVE" : "\(shown.count) DISKS MOUNTED · LIVE")
            }
        }
    }
    private func diskRing(freeBytes: Int64, fraction: Double, color: Color, size: CGFloat) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().stroke(.white.opacity(0.12), lineWidth: size * 0.07)
                Circle()
                    .trim(from: 0, to: max(0.03, fraction))
                    .stroke(color, style: StrokeStyle(lineWidth: size * 0.07, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.7), value: fraction)
                VStack(spacing: 1) {
                    Text(Self.capacityText(freeBytes)).font(.system(size: size * 0.2, weight: .semibold, design: .rounded)).monospacedDigit().minimumScaleFactor(0.7).lineLimit(1)
                    Text("free").font(.system(size: size * 0.11, weight: .medium)).foregroundStyle(Palette.muted)
                }.padding(size * 0.14)
            }
            .frame(width: size, height: size)
        }
    }
    private func diskRow(_ volume: LiveFeed.VolumeInfo, showEject: Bool) -> some View {
        let fractionUsed = 1 - volume.freeFraction
        let low = volume.freeFraction < 0.1
        let color = low ? Color(hex: "FF453A") : (volume.freeFraction < 0.2 ? Color(hex: "FF9F0A") : Color(hex: "30D158"))
        let hovering = hoveredVolume == volume.path
        // Row opens Finder via a plain tap gesture; the eject control must NOT be
        // a button nested inside another button (inner taps are unreliable).
        return HStack(spacing: 8) {
            Image(systemName: volume.isInternal ? "internaldrive.fill" : "externaldrive.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(volume.name).font(.system(size: 9.5, weight: .semibold, design: .rounded)).lineLimit(1)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.1))
                        Capsule().fill(color).frame(width: geo.size.width * CGFloat(fractionUsed))
                    }
                }.frame(height: 3.5)
            }
            Spacer(minLength: 4)
            Text(Self.capacityText(volume.free)).font(.system(size: 9, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(low ? color : .white.opacity(0.75))
            if showEject && hovering {
                Button {
                    hoveredVolume = nil
                    Task {
                        await LiveFeed.ejectVolume(path: volume.path)
                        mountedVolumes = LiveFeed.mountedVolumes()
                    }
                } label: {
                    Image(systemName: "eject.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Palette.background)
                        .padding(5)
                        .background(accentColor, in: Circle())
                }
                .buttonStyle(FullAreaButtonStyle())
                .help("Eject \(volume.name)")
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { NSWorkspace.shared.open(URL(fileURLWithPath: volume.path)) }
        .onHover { hovering in hoveredVolume = hovering ? volume.path : nil }
    }
    static func capacityText(_ bytes: Int64) -> String {
        let gigabytes = Double(bytes) / 1_000_000_000
        if gigabytes >= 1000 { return String(format: "%.2f TB", gigabytes / 1000) }
        if gigabytes >= 100 { return String(format: "%.0f GB", gigabytes) }
        return String(format: "%.0f GB", gigabytes)
    }
    private func deviceRow(_ device: LiveFeed.PairedDeviceInfo) -> some View {
        HStack(spacing: 8) {
            Image(systemName: device.icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(device.connected ? accentColor : .white.opacity(0.5))
                .frame(width: 24, height: 24)
                .background(.white.opacity(device.connected ? 0.09 : 0.05), in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(device.name).font(.system(size: 9.5, weight: .semibold, design: .rounded)).lineLimit(1)
                    Circle().fill(device.connected ? Color(hex: "30D158") : .white.opacity(0.25)).frame(width: 4.5, height: 4.5)
                }
                if let percent = device.batteryPercent {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.1))
                            Capsule().fill(batteryColor(level: percent, charging: false)).frame(width: geo.size.width * CGFloat(percent) / 100)
                        }
                    }.frame(height: 3.5)
                } else {
                    Text(device.connected ? "Connected" : "Disconnected")
                        .font(.system(size: 7.5, weight: .medium)).foregroundStyle(Palette.muted)
                }
            }
            Spacer(minLength: 4)
            HStack(spacing: 6) {
                if let percent = device.batteryPercent {
                    Text("\\(percent)%").font(.system(size: 9, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(.white.opacity(0.75))
                }
                Button {
                    let target = !device.connected
                    if LiveFeed.setBluetoothConnection(address: device.address, connect: target) {
                        pairedDevices = pairedDevices.map { entry in
                            var updated = entry
                            if entry.address == device.address {
                                updated.connected = target
                                updated.batteryPercent = target ? entry.batteryPercent : nil
                            }
                            return updated
                        }
                    }
                } label: {
                    Text(device.connected ? "Disconnect" : "Connect")
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(device.connected ? Color.white.opacity(0.12) : accentColor, in: Capsule())
                        .foregroundStyle(device.connected ? .white.opacity(0.85) : Palette.background)
                }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle()).help(device.connected ? "Disconnect \\(device.name)" : "Connect \\(device.name)")
            }
        }
    }
    // Temperature: real sensor values from the SMC (chip), the battery registry,
    // and fan status — refreshed every three seconds, like the reference widget.
    private var temperatureCard: some View {
        TimelineView(.periodic(from: .now, by: 3)) { _ in
            temperatureContent
        }
    }
    private func temperatureValue(_ value: Double?) -> String {
        guard let value else { return "—" }
        let unit = item?.temperatureUnit ?? .auto
        if unit == .fahrenheit || (unit == .auto && Locale.current.measurementSystem == .us) {
            return "\(Int((value * 9 / 5 + 32).rounded()))°"
        }
        return "\(Int(value.rounded()))°"
    }
    private var temperatureContent: some View {
        let chip = SMCReader.shared.firstTemperature(keys: SMCReader.chipKeys)
        let battery = LiveFeed.batteryStats()?.temperatureC
        let storage = SMCReader.shared.firstTemperature(keys: SMCReader.storageKeys)
        let smcBlocked = !SMCReader.shared.readable
        let fans = smcBlocked ? 0 : SMCReader.shared.fanCount()
        let rpm = fans > 0 ? SMCReader.shared.fanRPM(index: 0) : nil
        // When macOS blocks the chip sensor, the battery sensor headlines the
        // card instead — still a real, live reading.
        let headlineValue = chip ?? battery
        let headlineLabel = chip != nil ? "CHIP" : (battery != nil ? "BATTERY" : "CHIP")
        let hottest = [chip, battery, storage].compactMap { $0 }.max()
        return VStack(alignment: .leading, spacing: 10) {
            header("Temperature", "thermometer.medium")
            if tiny {
                Spacer(minLength: 0)
                Text(temperatureValue(hottest)).font(.system(size: 38, weight: .light, design: .rounded)).monospacedDigit().frame(maxWidth: .infinity)
                Text(hottest != nil ? "HOTTEST SENSOR" : "SENSORS UNAVAILABLE").font(.system(size: 8, weight: .bold)).tracking(0.8).foregroundStyle(Palette.muted).frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            } else if wide {
                HStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("CHIP").font(.system(size: 7, weight: .bold)).tracking(0.8).foregroundStyle(Palette.muted)
                        Text(temperatureValue(chip)).font(.system(size: veryWide ? 42 : 32, weight: .light, design: .rounded)).monospacedDigit()
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .leading, spacing: 5) {
                        if let battery { tempRow("Battery", temperatureValue(battery)) }
                        if let storage { tempRow("Storage", temperatureValue(storage)) }
                        if item?.showFanSpeed ?? true { tempRow(fans > 0 ? "Fan" : "Fans", fans > 0 ? (rpm.map { "\(Int($0)) rpm" } ?? "—") : "Fanless") }
                    }
                }
                Spacer(minLength: 0)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(temperatureValue(headlineValue)).font(.system(size: 46, weight: .light, design: .rounded)).monospacedDigit()
                        Text(headlineLabel).font(.system(size: 8, weight: .bold)).tracking(1).foregroundStyle(accentColor)
                        Spacer(minLength: 0)
                    }
                    VStack(alignment: .leading, spacing: 7) {
                        if let battery { row(label: "Battery", icon: "battery.100percent", value: temperatureValue(battery), bar: min(1, battery / 120)) }
                        if let storage { row(label: "Storage", icon: "internaldrive", value: temperatureValue(storage), bar: min(1, storage / 120)) }
                        if item?.showFanSpeed ?? true {
                            if smcBlocked {
                                row(label: "Fans", icon: "fan.blades", value: "Sensor access limited", bar: nil)
                            } else if fans > 0 {
                                row(label: rpm.map { "Fan · \(Int($0)) rpm" } ?? "Fan", icon: "fan.blades", value: fans == 1 ? "1 fan" : "\(fans) fans", bar: nil)
                            } else {
                                row(label: "Fanless", icon: "fan.blades", value: "Passive cooling", bar: nil)
                            }
                        }
                        row(label: "System load", icon: "cpu", value: thermalLabel, bar: nil)
                    }
                    Spacer(minLength: 0)
                    feedFooter(smcBlocked ? "SENSOR ACCESS LIMITED BY MACOS · LOCAL ONLY" : "SMC · READS EVERY 3 SECONDS · LOCAL ONLY")
                }
            }
        }
    }
    private var thermalLabel: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "Normal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }
    private func tempRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(.system(size: 7, weight: .bold)).tracking(0.7).foregroundStyle(Palette.muted)
            Text(value).font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
        }
    }
    private func row(label: String, icon: String, value: String, bar: Double?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 8)).foregroundStyle(accentColor).frame(width: 12)
                Text(label).font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.72))
                Spacer(minLength: 4)
                Text(value).font(.system(size: 10, weight: .semibold, design: .rounded)).monospacedDigit()
            }
            if let bar {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.09))
                        Capsule().fill(LinearGradient(colors: [Color(hex: "63D9FF"), Color(hex: "FFB45E"), Color(hex: "FF6B5E")], startPoint: .leading, endPoint: .trailing)).frame(width: geo.size.width * bar)
                    }
                }.frame(height: 3)
            }
        }
    }
    private func systemCard(_ kind: WidgetKind) -> some View {
        let rows = Self.systemFacts(kind)
        return VStack(alignment: .leading, spacing: 12) {
            header(kind.rawValue, kind.symbol)
            if tiny {
                Spacer(minLength: 0)
                Text(rows.first?.1 ?? "Unavailable").font(.system(size: 22, weight: .light, design: .rounded)).lineLimit(2).minimumScaleFactor(0.7)
                Text(rows.first?.0 ?? "STATUS").font(.system(size: 8, weight: .bold)).tracking(0.8).foregroundStyle(accentColor)
                Spacer(minLength: 0)
            } else if wide {
                HStack(spacing: 18) {
                    ForEach(Array(rows.prefix(veryWide ? 4 : 3).enumerated()), id: \.offset) { _, row in
                        VStack(alignment: .leading, spacing: 6) { Text(row.0.uppercased()).font(.system(size: 7, weight: .bold)).tracking(0.8).foregroundStyle(Palette.muted); Text(row.1).font(.system(size: 14, weight: .medium, design: .rounded)).lineLimit(2).minimumScaleFactor(0.7) }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Spacer(minLength: 0)
            } else {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .firstTextBaseline) { Text(row.0).font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.62)); Spacer(); Text(row.1).font(.system(size: 11, weight: .semibold, design: .rounded)).multilineTextAlignment(.trailing).lineLimit(2) }
                }
                if expanded { Spacer(minLength: 0); Text("READ-ONLY · SYSTEM DATA FROM THIS MAC").font(.system(size: 7, weight: .bold)).tracking(0.65).foregroundStyle(Palette.muted) }
            }
        }
    }
    private static func systemFacts(_ kind: WidgetKind) -> [(String, String)] {
        let process = ProcessInfo.processInfo
        let memory = Int((Double(process.physicalMemory) / 1_073_741_824).rounded())
        let host = Host.current().localizedName ?? "This Mac"
        let uptime = Int(process.systemUptime)
        let uptimeText = uptime >= 86_400 ? "\(uptime / 86_400)d \((uptime % 86_400) / 3600)h" : "\(uptime / 3600)h \((uptime % 3600) / 60)m"
        switch kind {
        case .system: return [("Mac", host), ("Logical CPU cores", "\(process.processorCount)"), ("Installed memory", "\(memory) GB")]
        case .temperature:
            let state = ProcessInfo.processInfo.thermalState
            let label: String
            switch state { case .nominal: label = "Normal"; case .fair: label = "Fair"; case .serious: label = "Serious"; case .critical: label = "Critical"; @unknown default: label = "Unknown" }
            return [("Thermal pressure", label), ("Sensor reading", "macOS does not expose CPU temperature")]
        case .devices: return [("Computer", host), ("CPU cores", "\(process.processorCount)"), ("Memory", "\(memory) GB")]
        case .activity: return [("System uptime", uptimeText), ("Processors", "\(process.processorCount) logical cores"), ("Memory", "\(memory) GB total")]
        default:
            let session = max(0, Int(Date.now.timeIntervalSince(sessionStartedAt)))
            return [("Littleboard session", "\(session / 60)m \(session % 60)s"), ("Started", sessionStartedAt.formatted(date: .omitted, time: .shortened)), ("Computer", host)]
        }
    }
    @ViewBuilder private func musicCard(_ kind: WidgetKind) -> some View {
        if let state = playback {
            musicLive(state)
        } else {
            musicIdle
        }
    }
    // Live player: album artwork, animated equalizer, scrubbable progress, and
    // transport controls. Interpolates the playhead between 3-second polls so the
    // progress bar moves smoothly instead of jumping.
    private func musicLive(_ state: LiveFeed.PlaybackState) -> some View {
        VStack(alignment: .leading, spacing: expanded ? 12 : 10) {
            HStack(spacing: 8) {
                header(state.isPlaying ? "Music" : "\(state.app) · Paused", "waveform")
                Spacer(minLength: 4)
                Text(state.app == "Spotify" ? "SPOTIFY" : (state.app == "Music" ? "APPLE MUSIC" : state.app.uppercased()))
                    .font(.system(size: 6, weight: .bold)).tracking(1.1)
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(accentColor.opacity(0.14), in: Capsule())
                if state.isPlaying {
                    HStack(spacing: 2.5) {
                        ForEach(0..<3, id: \.self) { i in
                            Capsule().fill(accentColor).frame(width: 2.5, height: 9)
                                .phaseAnimator([0.4, 1.0, 0.55, 0.9], trigger: state.isPlaying) { view, phase in
                                    view.scaleEffect(y: phase, anchor: .center)
                                } animation: { _ in
                                    .easeInOut(duration: 0.32 + Double(i) * 0.11)
                                }
                        }
                    }
                }
            }
            HStack(spacing: 14) {
                albumArtwork(side: tiny ? 46 : (wide ? (veryWide ? 82 : 64) : (expanded ? 108 : 76)))
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.title).font(.system(size: tiny ? 12 : (expanded ? 19 : 14), weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
                    if !state.artist.isEmpty { Text(state.artist).font(.system(size: tiny ? 9 : 10, weight: .medium)).foregroundStyle(.white.opacity(0.68)).lineLimit(1) }
                    if !tiny, !state.album.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "opticaldisc").font(.system(size: 7))
                            Text(state.album).lineLimit(1)
                        }.font(.system(size: 8)).foregroundStyle(.white.opacity(0.45))
                    }
                }
                Spacer(minLength: 0)
                if tiny, state.controllable { transportControls(state, compact: true) }
            }
            if !tiny {
                if state.duration > 0 { musicProgress(state) }
                else { Text("LIVE STREAM · NO TIMELINE").font(.system(size: 7, weight: .bold)).tracking(0.8).foregroundStyle(Palette.muted) }
            }
            if !tiny {
                HStack(spacing: 14) {
                    LiveEqualizer(count: expanded ? 40 : (veryWide ? 48 : 26), accent: accentColor, active: state.isPlaying)
                        .frame(maxWidth: .infinity)
                    if state.controllable { transportControls(state, compact: false) }
                }
            } else {
                LiveEqualizer(count: 12, accent: accentColor, active: state.isPlaying)
            }
        }
    }
    private func albumArtwork(side: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: side * 0.16, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: "D69C72"), Color(hex: "634A71")], startPoint: .topLeading, endPoint: .bottomTrailing))
            if let artwork {
                Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "music.note").font(.system(size: side * 0.34, weight: .light)).foregroundStyle(.white.opacity(0.9)).frame(width: side, height: side)
            }
            // Glass sheen across the cover, like a physical album sleeve.
            LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.02), .clear], startPoint: .topLeading, endPoint: .center)
                .frame(height: side * 0.5)
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: side * 0.16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: side * 0.16, style: .continuous).stroke(.white.opacity(0.16), lineWidth: 1))
        .shadow(color: .black.opacity(0.38), radius: 9, y: 4)
    }
    private func musicProgress(_ state: LiveFeed.PlaybackState) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let position = displayPosition(state, at: context.date)
            VStack(spacing: 4) {
                GeometryReader { geometry in
                    let fraction = state.duration > 0 ? min(1, max(0, position / state.duration)) : 0
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.14)).frame(height: 4)
                        Capsule().fill(LinearGradient(colors: [accentColor.opacity(0.85), accentColor], startPoint: .leading, endPoint: .trailing)).frame(width: max(4, geometry.size.width * fraction), height: 4)
                        Circle().fill(.white).frame(width: 8, height: 8).shadow(color: .black.opacity(0.4), radius: 2).offset(x: geometry.size.width * fraction - 4)
                    }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onEnded { value in
                        guard state.seekable, state.duration > 0 else { return }
                        let target = Double(value.location.x / max(1, geometry.size.width)) * state.duration
                        LiveFeed.playbackSeek(to: target, app: state.app)
                    })
                }.frame(height: 12)
                HStack {
                    Text(Self.timecode(position))
                    Spacer()
                    Text("-" + Self.timecode(max(0, state.duration - position)))
                }.font(.system(size: 7, weight: .semibold, design: .monospaced)).monospacedDigit().foregroundStyle(.white.opacity(0.52))
            }
        }
    }
    private func displayPosition(_ state: LiveFeed.PlaybackState, at date: Date) -> Double {
        guard state.duration > 0 else { return state.position }
        guard state.isPlaying else { return min(state.position, state.duration) }
        return min(state.duration, state.position + date.timeIntervalSince(playbackUpdatedAt))
    }
    private static func timecode(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total >= 3600 { return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60) }
        return String(format: "%d:%02d", total / 60, total % 60)
    }
    private func transportControls(_ state: LiveFeed.PlaybackState, compact: Bool) -> some View {
        HStack(spacing: compact ? 10 : 12) {
            controlButton("backward.end.fill", diameter: compact ? 24 : 30) { LiveFeed.playbackControl("previous track", app: state.app) }
            Button { LiveFeed.playbackControl("playpause", app: state.app) } label: {
                ZStack {
                    Circle().fill(accentColor)
                    Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: compact ? 10 : 13, weight: .bold))
                        .foregroundStyle(Palette.background)
                }
                .frame(width: compact ? 30 : 38, height: compact ? 30 : 38)
                .shadow(color: accentColor.opacity(0.45), radius: 7, y: 2)
            }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle()).help(state.isPlaying ? "Pause" : "Play")
            controlButton("forward.end.fill", diameter: compact ? 24 : 30) { LiveFeed.playbackControl("next track", app: state.app) }
        }
    }
    private func controlButton(_ symbol: String, diameter: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle().fill(.white.opacity(0.09))
                Image(systemName: symbol).font(.system(size: diameter * 0.36, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
            }
            .frame(width: diameter, height: diameter)
        }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle()).help(symbol == "backward.end.fill" ? "Previous" : "Next")
    }
    private var musicIdle: some View {
        VStack(alignment: .leading, spacing: 10) {
            header("Music", "waveform")
            Spacer(minLength: 0)
            HStack(spacing: 12) {
                albumArtwork(side: tiny ? 44 : (expanded ? 78 : 58))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nothing playing").font(.system(size: tiny ? 11 : (expanded ? 16 : 13), weight: .bold, design: .rounded))
                    Text("Open Music or Spotify and press play.").font(.system(size: 9)).foregroundStyle(.white.opacity(0.55)).lineLimit(2)
                    Button { openApp("com.apple.Music") } label: { Label("Open Music", systemImage: "arrow.up.right.square") }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle()).font(.system(size: 9, weight: .semibold)).foregroundStyle(accentColor).padding(.top, 2)
                }
                Spacer(minLength: 0)
            }
            LiveEqualizer(count: tiny ? 12 : (expanded ? 30 : 20), accent: accentColor, active: false)
        }
    }
    @ViewBuilder private var airQualityCard: some View {
        if let reading = airReading, let aqi = reading.aqi {
            let category = LiveFeed.aqiCategory(aqi)
            if tiny {
                VStack(alignment: .leading, spacing: 8) {
                    header("Air Quality", "wind")
                    Spacer(minLength: 0)
                    HStack(alignment: .firstTextBaseline, spacing: 7) { Text("\(aqi)").font(.system(size: 43, weight: .light, design: .rounded)); Text(category.label.uppercased()).font(.system(size: 8, weight: .bold)).tracking(0.8).foregroundStyle(Color(hex: category.color)) }
                    Text("AQI · \(reading.location)").font(.system(size: 8, weight: .bold)).tracking(0.4).foregroundStyle(Palette.muted).lineLimit(1)
                    Spacer(minLength: 0)
                }
            } else if wide {
                HStack(spacing: 22) {
                    VStack(alignment: .leading, spacing: 6) { header("Air Quality", "wind"); HStack(alignment: .firstTextBaseline, spacing: 7) { Text("\(aqi)").font(.system(size: 42, weight: .light, design: .rounded)); Text(category.label.uppercased()).font(.system(size: 8, weight: .bold)).foregroundStyle(Color(hex: category.color)) } }
                    VStack(alignment: .leading, spacing: 9) {
                        ProgressView(value: min(Double(aqi), 300), total: 300).tint(Color(hex: category.color))
                        if let pm25 = reading.pm25 { Label(String(format: "PM2.5 · %.1f μg/m³", pm25), systemImage: "circle.fill").font(.system(size: 9, weight: .medium)) }
                        if veryWide, let pm10 = reading.pm10 { Label(String(format: "PM10 · %.1f μg/m³", pm10), systemImage: "circle.fill").font(.system(size: 9, weight: .medium)) }
                        feedFooter("LIVE · OPEN-METEO · \(reading.location)")
                    }.foregroundStyle(.white.opacity(0.72))
                    Spacer(minLength: 0)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    header("Air Quality", "wind")
                    HStack(alignment: .firstTextBaseline, spacing: 8) { Text("\(aqi)").font(.system(size: 46, weight: .light, design: .rounded)); Text(category.label.uppercased()).font(.system(size: 9, weight: .bold)).tracking(1).foregroundStyle(Color(hex: category.color)) }
                    Text(reading.location).font(.system(size: 9)).foregroundStyle(.white.opacity(0.58)).lineLimit(1)
                    HStack(spacing: 4) { ForEach(0..<6, id: \.self) { i in Capsule().fill(i < min(6, (aqi / 50) + 1) ? Color(hex: category.color) : .white.opacity(0.12)).frame(height: 5) } }
                    if let pm25 = reading.pm25 { HStack { Label("PM2.5", systemImage: "circle.fill"); Spacer(); Text(String(format: "%.1f μg/m³", pm25)) }.font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.68)) }
                    if let pm10 = reading.pm10 { HStack { Text("PM10"); Spacer(); Text(String(format: "%.1f μg/m³", pm10)) }.font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.68)) }
                    if expanded, let ozone = reading.ozone { HStack { Text("O₃"); Spacer(); Text(String(format: "%.0f μg/m³", ozone)) }.font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.68)) }
                    Spacer(minLength: 0)
                    feedFooter("LIVE · OPEN-METEO AIR QUALITY")
                }
            }
        } else if let airError {
            feedErrorView(airError) { if let item { Task { await loadAirQuality(item) } } }
        } else {
            feedLoadingView("Getting air quality for \(item?.city ?? "your city")…")
        }
    }
    private var moonCard: some View {
        TimelineView(.periodic(from: .now, by: 3600)) { context in
            let phase = Self.lunarState(at: context.date)
            Group {
                if tiny {
                    VStack(alignment: .leading, spacing: 8) {
                        header("Moon", "moon.fill")
                        Spacer(minLength: 0)
                        moonImage(side: 60, illumination: phase.illumination)
                        Text(phase.name).font(.system(size: 10, weight: .semibold, design: .rounded))
                        Text("\(Int(phase.illumination * 100))% lit").font(.system(size: 8)).foregroundStyle(Palette.muted)
                        Spacer(minLength: 0)
                    }
                } else {
                    HStack(spacing: 18) {
                        moonImage(side: expanded ? 120 : 82, illumination: phase.illumination)
                        VStack(alignment: .leading, spacing: 8) {
                            if !expanded { header("Moon", "moon.fill") }
                            Text(phase.name).font(.system(size: expanded ? 21 : 16, weight: .medium, design: .rounded))
                            Text("Illumination · \(Int(phase.illumination * 100))%").font(.system(size: 9)).foregroundStyle(.white.opacity(0.65))
                            Text("Full moon in about \(Int(phase.daysToFull)) days").font(.system(size: 9, weight: .medium)).foregroundStyle(accentColor)
                            if expanded { Text("LUNAR PHASE · APPROXIMATE").font(.system(size: 7, weight: .bold)).tracking(0.7).foregroundStyle(Palette.muted) }
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }
    private func moonImage(side: CGFloat, illumination: Double) -> some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Color(hex: "F3E7C9"), Color(hex: "A9A894")], startPoint: .topLeading, endPoint: .bottomTrailing)).shadow(color: .white.opacity(0.2), radius: 20)
            Circle().fill(Color(hex: "24333A")).frame(width: side * (1 - abs(2 * illumination - 1)), height: side).offset(x: side * 0.3 * (illumination < 0.5 ? 1 : -1))
        }.frame(width: side, height: side).clipShape(Circle())
    }
    private static func lunarState(at date: Date) -> (name: String, illumination: Double, daysToFull: Double) {
        let period = 29.530588853
        let reference = Date(timeIntervalSince1970: 947_182_440)
        let age = date.timeIntervalSince(reference).truncatingRemainder(dividingBy: period * 86_400) / 86_400
        let normalized = age < 0 ? age + period : age
        let illumination = (1 - cos(2 * .pi * normalized / period)) / 2
        let phase = Int((normalized / period * 8).rounded()) % 8
        let names = ["New Moon", "Waxing Crescent", "First Quarter", "Waxing Gibbous", "Full Moon", "Waning Gibbous", "Last Quarter", "Waning Crescent"]
        let toFull = (period / 2 - normalized + period).truncatingRemainder(dividingBy: period)
        return (names[phase], illumination, toFull)
    }
    private func timer(_ kind: WidgetKind) -> some View {
        guard let id else { return AnyView(EmptyView()) }
        return AnyView(TimelineView(.periodic(from: .now, by: 1)) { context in
            let seconds = model.timerSeconds(id, at: context.date)
            VStack(alignment: .leading, spacing: 10) {
                header(kind.rawValue, "timer")
                Spacer(minLength: 0)
                Text(kind == .stopwatch ? String(format: "%02d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60) : String(format: "%02d:%02d", seconds / 60, seconds % 60)).font(.system(size: narrow ? 34 : 43, weight: .light, design: .rounded)).monospacedDigit().minimumScaleFactor(0.55)
                HStack(spacing: 8) {
                    Button { model.toggleTimer(id) } label: { Label(item?.timerRunning == true ? "Pause" : "Start", systemImage: item?.timerRunning == true ? "pause.fill" : "play.fill") }
                    Button { model.resetTimer(id) } label: { Image(systemName: "arrow.counterclockwise") }.help("Reset timer")
                }.font(.system(size: 9, weight: .bold)).buttonStyle(FullAreaButtonStyle()).foregroundStyle(accentColor)
                if expanded { Text(kind == .pomodoro ? "FOCUS SESSION · 25 MIN" : "TIMER · LOCAL TO THIS MAC").font(.system(size: 8, weight: .bold)).tracking(0.8).foregroundStyle(Palette.muted) }
                Spacer(minLength: 0)
            }
        })
    }
    private var calculator: some View {
        guard let id else { return AnyView(EmptyView()) }
        return AnyView(VStack(alignment: .leading, spacing: narrow ? 4 : 7) {
            header("Calculator", "function")
            Text(item?.calculatorDisplay ?? "0").font(.system(size: narrow ? 22 : 32, weight: .light, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5).frame(maxWidth: .infinity, alignment: .trailing)
            let rows = [["7", "8", "9", "÷"], ["4", "5", "6", "×"], ["1", "2", "3", "−"], ["AC", "0", ".", "+"], ["="]]
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 5) {
                    ForEach(row, id: \.self) { key in
                        Button { model.calculatorPress(id, key: key) } label: { Text(key).font(.system(size: 11, weight: .semibold)).frame(maxWidth: .infinity).frame(height: narrow ? 17 : 24).background(key == "=" ? accentColor.opacity(0.85) : .white.opacity(0.07), in: RoundedRectangle(cornerRadius: 7)).foregroundStyle(key == "=" ? Palette.background : .white) }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle())
                    }
                }
            }
        })
    }
    @ViewBuilder private var map: some View {
        let cities = [("San Francisco", "SF", "America/Los_Angeles"), ("London", "LDN", "Europe/London"), ("Tokyo", "TYO", "Asia/Tokyo")]
        if tiny {
            VStack(alignment: .leading, spacing: 8) {
                header("World Map", "globe.americas.fill")
                Spacer(minLength: 0)
                Image(systemName: "globe.americas.fill").font(.system(size: 40, weight: .light)).foregroundStyle(accentColor)
                Text("3 CITY TIME ZONES").font(.system(size: 8, weight: .bold)).tracking(0.7).foregroundStyle(Palette.muted)
                Button { openMap("San Francisco") } label: { Label("Open Maps", systemImage: "arrow.up.right.square") }.font(.system(size: 9, weight: .semibold)).buttonStyle(FullAreaButtonStyle()).foregroundStyle(accentColor)
                Spacer(minLength: 0)
            }
        } else if wide {
            VStack(alignment: .leading, spacing: 12) {
                header("World Map · City Times", "globe.americas.fill")
                HStack(spacing: 12) {
                    ForEach(cities, id: \.0) { city, _, zone in
                        Button { openMap(city) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(city).font(.system(size: 9, weight: .medium)).lineLimit(1)
                                Text(Self.time(in: zone)).font(.system(size: veryWide ? 21 : 16, weight: .medium, design: .rounded)).monospacedDigit()
                                Text(Self.dayLabel(in: zone)).font(.system(size: 8)).foregroundStyle(accentColor)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle()).foregroundStyle(.white)
                    }
                }
                Spacer(minLength: 0)
            }
        } else {
            HStack(spacing: 14) {
                ZStack {
                    Color(hex: "1D2928")
                    Path { p in p.move(to: CGPoint(x: 10, y: 50)); p.addCurve(to: CGPoint(x: 230, y: 20), control1: CGPoint(x: 70, y: 5), control2: CGPoint(x: 130, y: 85)); p.move(to: CGPoint(x: 35, y: 145)); p.addCurve(to: CGPoint(x: 245, y: 170), control1: CGPoint(x: 95, y: 95), control2: CGPoint(x: 165, y: 160)) }.stroke(.white.opacity(0.09), lineWidth: 14)
                    HStack { mapDot("SF"); Spacer(); mapDot("LDN"); Spacer(); mapDot("TYO") }.padding(.horizontal, 12)
                }.clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 6) {
                    header("World Map", "globe.americas.fill")
                    ForEach(cities, id: \.0) { city, _, zone in
                        Button { openMap(city) } label: { HStack { Text(city).font(.system(size: 8)); Spacer(); Text(Self.time(in: zone)).font(.system(size: 9, weight: .medium, design: .rounded)).monospacedDigit() } }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle()).foregroundStyle(.white)
                    }
                }.frame(maxWidth: expanded ? 180 : 155)
            }
        }
    }
    private func openMap(_ city: String) {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "maps.apple.com"
        components.queryItems = [URLQueryItem(name: "q", value: city)]
        if let url = components.url { NSWorkspace.shared.open(url) }
    }
    private func mapDot(_ label: String) -> some View { VStack(spacing: 5) { Circle().fill(accentColor).frame(width: 7, height: 7).shadow(color: accentColor, radius: 7); Text(label).font(.system(size: 7, weight: .bold)).foregroundStyle(.white.opacity(0.65)) } }
    private var stars: some View {
        GeometryReader { geometry in
            let count = tiny ? 14 : (expanded ? 72 : (veryWide ? 48 : 30))
            ZStack {
                Color(hex: "101827")
                ForEach(0..<count, id: \.self) { index in
                    let x = CGFloat((index * 73 + 17) % 101) / 100 * geometry.size.width - geometry.size.width / 2
                    let y = CGFloat((index * 47 + 29) % 101) / 100 * geometry.size.height - geometry.size.height / 2
                    Circle().fill(.white.opacity(Double((index % 4) + 2) / 10)).frame(width: CGFloat((index % 3) + 1), height: CGFloat((index % 3) + 1)).offset(x: x, y: y)
                }
                VStack(alignment: .leading, spacing: 7) {
                    header("Starfield", "sparkles")
                    Spacer()
                    if expanded { Text("\(count) STARS · DEEP FIELD").font(.system(size: 8, weight: .bold)).tracking(0.7).foregroundStyle(accentColor) }
                    Text(tiny ? "A little universe" : "A quiet corner of the universe").font(.system(size: expanded ? 14 : 11, weight: .medium)).foregroundStyle(.white.opacity(0.8))
                }.padding(16)
            }.clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
    private var companion: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = breathingStartedAt.map { max(0, Int(context.date.timeIntervalSince($0))) } ?? 0
            let phase = elapsed % 12
            let cue = phase < 4 ? "Breathe in" : (phase < 8 ? "Breathe out" : "Rest")
            VStack(spacing: 10) {
                if !tiny { header("Companion", "sparkles") }
                Spacer(minLength: 0)
                Image(systemName: breathingStartedAt == nil ? "sparkles" : "wind").font(.system(size: expanded ? 54 : 36, weight: .light)).foregroundStyle(accentColor).scaleEffect(breathingStartedAt == nil ? 1 : (phase < 4 ? 1.25 : (phase < 8 ? 0.9 : 1))).animation(.easeInOut(duration: 0.8), value: phase)
                Text(breathingStartedAt == nil ? (tiny ? "Take a breath." : "A little company") : cue).font(.system(size: expanded ? 18 : 13, weight: .semibold, design: .rounded))
                Button(breathingStartedAt == nil ? "Start breathing" : "Stop") { breathingStartedAt = breathingStartedAt == nil ? context.date : nil }.font(.system(size: 9, weight: .semibold)).buttonStyle(FullAreaButtonStyle()).foregroundStyle(accentColor)
                if expanded { Text("4 seconds in · 4 seconds out · 4 seconds rest").font(.system(size: 9)).foregroundStyle(Palette.muted) }
                Spacer(minLength: 0)
            }.frame(maxWidth: .infinity)
        }
    }
    private var reminders: some View {
        let entries = item?.reminderItems ?? []
        let visible = tiny ? min(entries.count, 1) : (wide ? min(entries.count, 3) : entries.count)
        let completed = item?.reminderCompleted ?? []
        let left = entries.indices.filter { !completed.indices.contains($0) || !completed[$0] }.count
        return VStack(alignment: .leading, spacing: 10) {
            header("Reminders", "checklist")
            Text("\(left) LEFT · LOCAL LIST").font(.system(size: 8, weight: .bold)).tracking(0.7).foregroundStyle(Palette.muted)
            ForEach(0..<visible, id: \.self) { index in
                let text = entries[index]
                let isDone = completed.indices.contains(index) && completed[index]
                Button { if let id { model.toggleReminder(id, index: index) } } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isDone ? "checkmark.circle.fill" : "circle").foregroundStyle(accentColor)
                        Text(text).font(.system(size: 9)).strikethrough(isDone).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle())
            }
            Spacer(minLength: 0)
            if expanded { Text("EDIT OR ADD ITEMS IN WIDGET SETTINGS").font(.system(size: 7, weight: .bold)).tracking(0.7).foregroundStyle(Palette.muted) }
        }
    }
    private var terminal: some View { VStack(alignment: .leading, spacing: 8) { header("Terminal", "terminal.fill"); Spacer(); Text("$ littleboard --hello\nReady when you are.").font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(accentColor); Spacer() } }
    private var clipboard: some View { VStack(alignment: .leading, spacing: 10) { header("Clipboard", "doc.on.clipboard"); Button("Read Clipboard", systemImage: "doc.on.clipboard") { clipboardText = NSPasteboard.general.string(forType: .string) ?? "No text on clipboard" }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle()).font(.system(size: 10, weight: .semibold)).foregroundStyle(accentColor); Text(clipboardText ?? "Your clipboard is only read when you press the button.").font(.system(size: 11, weight: .medium, design: .rounded)).lineLimit(expanded ? 8 : 3).textSelection(.enabled); Spacer(); Text("LOCAL · READ ON REQUEST").font(.system(size: 7, weight: .bold)).tracking(0.8).foregroundStyle(Palette.muted) } }
    private func stack(_ item: WidgetInstance) -> some View {
        let limit = tiny ? 1 : (wide ? 2 : 3)
        return VStack(alignment: .leading, spacing: 10) {
            header("Widget Stack", "square.3.layers.3d")
            Text("\(item.stack.count) CARDS · TAP CHOOSE CARDS TO EDIT").font(.system(size: 7, weight: .bold)).tracking(0.7).foregroundStyle(Palette.muted)
            if wide {
                HStack(spacing: 8) {
                    ForEach(Array(item.stack.prefix(limit).enumerated()), id: \.offset) { _, kind in stackRow(kind) }
                }
            } else {
                ForEach(Array(item.stack.prefix(limit).enumerated()), id: \.offset) { _, kind in stackRow(kind) }
            }
            Spacer(minLength: 0)
        }
    }
    private func stackRow(_ kind: WidgetKind) -> some View {
        HStack(spacing: 8) { Image(systemName: kind.symbol).foregroundStyle(accentColor).frame(width: 20); Text(kind.rawValue).font(.system(size: 10, weight: .medium)).lineLimit(1); Spacer(minLength: 0) }
            .padding(9).frame(maxWidth: .infinity, alignment: .leading).background(Palette.panel.opacity(item?.glassStyle == .off ? 1 : 0.42), in: RoundedRectangle(cornerRadius: 9))
    }
    private var placeholder: some View { VStack(alignment: .leading) { header("Widget preview", "sparkles"); Spacer(); Text("Choose a card from the library.").font(.system(size: 14)).foregroundStyle(Palette.muted); Spacer() } }
}

private struct ClockFace: View {
    let date: Date
    let showSeconds: Bool
    let accent: Color
    let theme: ClockTheme
    let timeZone: TimeZone
    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height, 320)
            let components = Self.clockComponents(date, timeZone: timeZone)
            let hour = Double(components.hour ?? 0).truncatingRemainder(dividingBy: 12)
            let minute = Double(components.minute ?? 0)
            let second = Double(components.second ?? 0)
            let hourFont: Font = .system(size: side * 0.085, weight: .bold, design: .rounded)
            ZStack {
                Circle().fill(theme == .glass ? .white.opacity(0.11) : theme == .neon ? accent.opacity(0.08) : .white.opacity(0.045))
                Circle().stroke(theme == .neon ? accent.opacity(0.5) : .white.opacity(0.14), lineWidth: theme == .neon ? 1.5 : 1)
                if theme == .solar { Circle().stroke(accent.opacity(0.24), lineWidth: side * 0.035).padding(side * 0.07) }
                ForEach(0..<60, id: \.self) { tick in
                    Capsule().fill(tick.isMultiple(of: 5) ? (theme == .mono ? Color.white : accent) : .white.opacity(theme == .glass ? 0.42 : 0.2))
                        .frame(width: tick.isMultiple(of: 5) ? (theme == .mono ? 1.5 : 2.2) : 1, height: tick.isMultiple(of: 5) ? side * 0.045 : side * 0.018)
                        .offset(y: -side * 0.43).rotationEffect(.degrees(Double(tick) * 6))
                }
                if theme == .classic || theme == .solar {
                    ForEach([0, 3, 6, 9], id: \.self) { numeral in
                        let angle = Double(numeral) * .pi / 6
                        Text("\(numeral == 0 ? 12 : numeral)")
                            .font(hourFont)
                            .foregroundStyle(.white.opacity(0.96))
                            .shadow(color: .black.opacity(0.85), radius: 2, x: 0, y: 1)
                            .position(x: side / 2 + sin(angle) * side * 0.32, y: side / 2 - cos(angle) * side * 0.32)
                    }
                }
                Capsule().fill(theme == .mono ? Color.white.opacity(0.9) : accent).frame(width: theme == .mono ? 2 : 4, height: side * 0.25).offset(y: -side * 0.125).rotationEffect(.degrees(hour * 30 + minute / 2))
                Capsule().fill(.white.opacity(0.86)).frame(width: 2, height: side * 0.29).offset(y: -side * 0.145).rotationEffect(.degrees(minute * 6 + second / 10))
                if showSeconds { Capsule().fill(accent).frame(width: 1, height: side * 0.38).offset(y: -side * 0.19).rotationEffect(.degrees(second * 6)) }
                Circle().fill(accent).frame(width: 7, height: 7)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    private static func clockComponents(_ date: Date, timeZone: TimeZone) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.dateComponents([.hour, .minute, .second], from: date)
    }
}

private struct WeatherGlow: View {
    var opacity: Double = 0.3
    var body: some View {
        GeometryReader { geometry in
            Circle().fill(RadialGradient(colors: [Color(hex: "FFD27A").opacity(opacity), Color(hex: "FFB44E").opacity(opacity * 0.28), .clear], center: .center, startRadius: 4, endRadius: geometry.size.width * 0.7))
                .frame(width: geometry.size.width * 1.3, height: geometry.size.width * 1.3)
                .offset(x: geometry.size.width * 0.36, y: -geometry.size.height * 0.55)
        }.allowsHitTesting(false)
    }
}

private struct WeatherTemperatureChart: View {
    let hours: [WeatherHour]
    let unit: WeatherUnit
    private var values: [Double] { hours.map { unit == .fahrenheit || (unit == .auto && Locale.current.measurementSystem == .us) ? $0.temperature * 9 / 5 + 32 : $0.temperature } }
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack { Text("TODAY").font(.system(size: 6, weight: .bold)).tracking(0.7).foregroundStyle(.white.opacity(0.5)); Spacer(); if let high = values.max(), let low = values.min() { Text("H \(Int(high.rounded()))°  ·  L \(Int(low.rounded()))°").font(.system(size: 6, weight: .semibold, design: .monospaced)).foregroundStyle(.white.opacity(0.65)) } }
            GeometryReader { geometry in
                let width = geometry.size.width
                let height = geometry.size.height
                let low = (values.min() ?? 0) - 1
                let span = max(1, (values.max() ?? 1) - low)
                let points = values.enumerated().map { index, value in CGPoint(x: values.count < 2 ? width / 2 : width * CGFloat(index) / CGFloat(values.count - 1), y: height - CGFloat((value - low) / span) * (height - 7) - 3) }
                ZStack {
                    Path { path in
                        for guide in [0.35, 0.72] { let y = height * guide; path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: width, y: y)) }
                    }.stroke(.white.opacity(0.09), style: StrokeStyle(lineWidth: 0.6, dash: [2, 3]))
                    if let first = points.first, let last = points.last {
                        Path { path in path.move(to: CGPoint(x: first.x, y: height)); path.addLines(points); path.addLine(to: CGPoint(x: last.x, y: height)); path.closeSubpath() }
                            .fill(LinearGradient(colors: [Color(hex: "70D9FF").opacity(0.25), Color(hex: "8C6BFF").opacity(0.02)], startPoint: .top, endPoint: .bottom))
                        Path { path in path.addLines(points) }.stroke(LinearGradient(colors: [Color(hex: "61D9FF"), Color(hex: "B1E7FF"), Color(hex: "FFD75E")], startPoint: .leading, endPoint: .trailing), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        Circle().fill(Color(hex: "A4F1FF")).frame(width: 4, height: 4).position(first)
                        Circle().fill(Color(hex: "FFD75E")).frame(width: 4, height: 4).position(last)
                    }
                }
            }
            HStack { ForEach(Array(hours.prefix(6).enumerated()), id: \.offset) { index, hour in if index == 0 || index == 2 || index == 4 || index == 5 { Text(index == 0 ? "Now" : String(hour.label.prefix(2))).font(.system(size: 6, weight: .medium, design: .monospaced)).foregroundStyle(.white.opacity(0.48)); if index != 5 { Spacer(minLength: 0) } } } }
        }
    }
}

private struct GeoResponse: Decodable { var results: [GeoPlace]? }
private struct GeoPlace: Decodable { var name: String; var admin1: String?; var latitude: Double; var longitude: Double }
private struct ForecastResponse: Decodable {
    var timezone: String
    var current: Current
    var hourly: Hourly
    var daily: Daily
    enum CodingKeys: String, CodingKey { case timezone, current; case hourly; case daily }
    struct Current: Decodable {
        var temperature: Double; var apparent: Double; var humidity: Int; var code: Int; var wind: Double; var isDay: Int?
        enum CodingKeys: String, CodingKey { case temperature = "temperature_2m", apparent = "apparent_temperature", humidity = "relative_humidity_2m", code = "weather_code", wind = "wind_speed_10m", isDay = "is_day" }
    }
    struct Hourly: Decodable { var time: [String]; var temperature: [Double]; var code: [Int]; var isDay: [Int]?; enum CodingKeys: String, CodingKey { case time; case temperature = "temperature_2m"; case code = "weather_code"; case isDay = "is_day" } }
    struct Daily: Decodable { var time: [String]; var code: [Int]; var high: [Double]; var low: [Double]; var sunrise: [String]; var sunset: [String]; enum CodingKeys: String, CodingKey { case time; case code = "weather_code"; case high = "temperature_2m_max"; case low = "temperature_2m_min"; case sunrise, sunset } }
}
private struct AirQualityResponse: Decodable {
    var current: Current
    struct Current: Decodable { var aqi: Int?; var pm25: Double?; enum CodingKeys: String, CodingKey { case aqi = "us_aqi"; case pm25 = "pm2_5" } }
}
struct WeatherSnapshot {
    var location: String; var temperature: Double; var apparent: Double; var humidity: Int; var wind: Double; var currentCode: Int; var high: Double; var low: Double; var hours: [WeatherHour]; var days: [WeatherDay]; var sunset: String; var aqi: Int?; var isDay = true
}
struct WeatherHour { var label: String; var temperature: Double; var code: Int; var isDay = true }
struct WeatherDay { var label: String; var low: Double; var high: Double; var code: Int }

private enum SpeedTestState {
    case idle
    case running(String)
    case done(LiveFeed.SpeedTestResult)
    case failed(String)
    var isRunning: Bool { if case .running = self { return true }; return false }
    var isIdle: Bool { if case .idle = self { return true }; return false }
}

/// Animated audio bars. Draws a flowing wave while playing and freezes on a
/// static pattern when paused, so the card never idles at full CPU.
private struct LiveEqualizer: View {
    var count: Int
    var accent: Color
    var active: Bool
    var body: some View {
        Group {
            if active {
                TimelineView(.animation(minimumInterval: 1.0 / 10.0)) { context in bars(time: context.date.timeIntervalSinceReferenceDate) }
            } else { bars(time: 0) }
        }
    }
    private func bars(time: TimeInterval) -> some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<count, id: \.self) { i in
                Capsule().fill(i < count * 3 / 8 ? accent : .white.opacity(0.16)).frame(maxWidth: .infinity).frame(height: barHeight(index: i, time: time))
            }
        }
    }
    private func barHeight(index: Int, time: TimeInterval) -> CGFloat {
        if active {
            let speed = 1.15 + Double(index % 5) * 0.27
            let phase = time * speed + Double(index) * 0.83
            return 5 + CGFloat((sin(phase) + 1.0) / 2.0) * 17
        }
        return CGFloat([8, 13, 7, 17, 12, 21, 9, 15, 24, 12, 18, 8, 13, 20, 10, 15][index % 16]) * 0.6 + 3
    }
}

/// Custom battery gauge: outlined body, gradient fill scaled to the level, and
/// a glowing bolt while charging.
private struct BatteryGlyph: View {
    var percent: Int
    var charging: Bool
    var color: Color
    var width: CGFloat
    var body: some View {
        let bodyHeight = width * 0.46
        let fillFraction = max(0.06, min(1, CGFloat(percent) / 100))
        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: width * 0.16, style: .continuous)
                .stroke(.white.opacity(0.42), lineWidth: 2.5)
                .frame(width: width, height: bodyHeight)
            Capsule()
                .fill(.white.opacity(0.42))
                .frame(width: width * 0.055, height: bodyHeight * 0.42)
                .offset(x: width + width * 0.045)
            RoundedRectangle(cornerRadius: width * 0.1, style: .continuous)
                .fill(LinearGradient(colors: [color.opacity(0.75), color], startPoint: .top, endPoint: .bottom))
                .frame(width: max(width * 0.09, (width - width * 0.16) * fillFraction), height: bodyHeight - width * 0.13)
                .padding(.leading, width * 0.08)
                .animation(.easeInOut(duration: 0.6), value: percent)
            if charging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: width * 0.2, weight: .bold))
                    .foregroundStyle(Palette.background)
                    .shadow(color: color, radius: 5)
                    .frame(width: width, height: bodyHeight)
                    .phaseAnimator([0.55, 1, 0.7], trigger: charging) { view, phase in
                        view.opacity(phase)
                    } animation: { _ in
                        .easeInOut(duration: 0.8)
                    }
            }
        }
        .frame(width: width + width * 0.11, height: bodyHeight)
    }
}

/// Circular battery ring in the BetterMacWidgets style: icon in the middle,
/// progress arc around it, percent and label below, gentle breathing glow while
/// charging.
private struct BatteryRing: View {
    var percent: Int
    var charging: Bool
    var color: Color
    var icon: String
    var size: CGFloat
    var label: String?
    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(.white.opacity(0.13), lineWidth: size * 0.07)
                Circle()
                    .trim(from: 0, to: max(0.02, CGFloat(percent) / 100))
                    .stroke(color, style: StrokeStyle(lineWidth: size * 0.07, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.7), value: percent)
                Circle()
                    .stroke(color.opacity(0.35), lineWidth: size * 0.07)
                    .blur(radius: size * 0.09)
                    .phaseAnimator(charging ? [0, 0.5] : [0], trigger: charging) { view, phase in
                        view.opacity(phase)
                    } animation: { _ in
                        .easeInOut(duration: 1.4)
                    }
                Image(systemName: icon)
                    .font(.system(size: size * 0.3, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
            }
            .frame(width: size, height: size)
            .phaseAnimator(charging ? [1, 1.035, 1] : [1], trigger: charging) { view, phase in
                view.scaleEffect(phase)
            } animation: { _ in
                .easeInOut(duration: 1.4)
            }
            VStack(spacing: 1) {
                Text("\(percent)%").font(.system(size: size * 0.21, weight: .semibold, design: .rounded)).monospacedDigit()
                if let label {
                    Text(label).font(.system(size: max(7, size * 0.1), weight: .medium)).foregroundStyle(.white.opacity(0.55)).lineLimit(1).frame(maxWidth: size + 26)
                }
            }
        }
    }
}

/// Tiny analog clock face for World Clock rows and tiles: just hour and minute
/// hands over a soft dial, accurate to the city's time zone.
private struct MiniClockFace: View {
    let date: Date
    let timeZone: TimeZone
    let accent: Color
    var size: CGFloat
    var body: some View {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let hour = Double(components.hour ?? 0).truncatingRemainder(dividingBy: 12)
        let minute = Double(components.minute ?? 0)
        return ZStack {
            Circle().fill(.white.opacity(0.1))
            Circle().stroke(.white.opacity(0.22), lineWidth: size * 0.045)
            Capsule().fill(.white.opacity(0.85)).frame(width: max(1, size * 0.045), height: size * 0.26)
                .offset(y: -size * 0.13)
                .rotationEffect(.degrees(hour * 30 + minute / 2))
            Capsule().fill(.white.opacity(0.6)).frame(width: max(1, size * 0.04), height: size * 0.34)
                .offset(y: -size * 0.16)
                .rotationEffect(.degrees(minute * 6))
            Circle().fill(accent).frame(width: size * 0.09, height: size * 0.09)
        }
        .frame(width: size, height: size)
    }
}

private struct MiniSparkline: View {
    let values: [Double]
    let up: Bool
    var body: some View {
        GeometryReader { geometry in
            let clean = values.filter { $0.isFinite }
            let low = clean.min() ?? 0
            let high = clean.max() ?? 1
            let span = max(0.0001, high - low)
            let points = clean.enumerated().map { index, value in
                CGPoint(x: clean.count < 2 ? geometry.size.width / 2 : geometry.size.width * CGFloat(index) / CGFloat(clean.count - 1),
                        y: geometry.size.height - CGFloat((value - low) / span) * (geometry.size.height - 4) - 2)
            }
            if points.count > 1 {
                Path { path in path.addLines(points) }
                    .stroke(up ? Color(hex: "30D158") : Color(hex: "FF453A"), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

private struct InlineWebView: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        view.navigationDelegate = context.coordinator
        view.load(URLRequest(url: url))
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        guard context.coordinator.loadedURL != url else { return }
        context.coordinator.loadedURL = url
        view.load(URLRequest(url: url))
    }
    func makeCoordinator() -> Coordinator { Coordinator(url) }
    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedURL: URL
        init(_ url: URL) { loadedURL = url }
    }
}
