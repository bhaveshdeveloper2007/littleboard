import Foundation

enum WidgetKind: String, CaseIterable, Codable, Identifiable {
    case clock = "Clock", simpleClock = "Simple Clock", weather = "Weather", calendar = "Calendar"
    case reminders = "Reminders", worldClock = "World Clock", timer = "Timer", stopwatch = "Stopwatch"
    case countdown = "Countdown", trash = "Trash", photos = "Photos", toolbox = "Toolbox"
    case terminal = "Terminal", airQuality = "Air Quality", music = "Music", battery = "Battery"
    case audio = "Audio", soundMixer = "Sound Mixer", system = "System", temperature = "Temperature"
    case devices = "Devices", network = "Network", disks = "Disks", activity = "Activity"
    case appTime = "App Time", github = "GitHub", speedTest = "Speed Test", stickyNote = "Sticky Note"
    case quote = "Quote", apps = "Apps", shortcut = "Shortcut", smartHome = "Smart Home"
    case webPage = "Web Page", flipClock = "Flip Clock", wordClock = "Word Clock", pomodoro = "Pomodoro"
    case yearProgress = "Year Progress", dayProgress = "Day Progress", clipboard = "Clipboard"
    case dropZone = "Drop Zone", folder = "Folder", calculator = "Calculator", unitConverter = "Unit Converter"
    case currencies = "Currencies", stocks = "Stocks", crypto = "Crypto", passwordGenerator = "Password Generator"
    case worldMap = "World Map", moon = "Moon", companion = "Companion", ambientSound = "Ambient Sound"
    case starfield = "Starfield", mirror = "Mirror", widgetStack = "Widget Stack", custom = "Custom Widget"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .clock, .simpleClock, .flipClock, .worldClock, .wordClock: return "clock"
        case .weather, .airQuality: return "cloud.sun.fill"
        case .webPage: return "safari.fill"
        case .calendar, .countdown, .yearProgress, .dayProgress: return "calendar"
        case .reminders, .stickyNote, .quote, .custom: return "note.text"
        case .timer, .stopwatch, .pomodoro: return "timer"
        case .battery: return "battery.100percent"
        case .music, .audio, .soundMixer, .ambientSound: return "waveform"
        case .calculator, .unitConverter, .currencies: return "function"
        case .worldMap: return "globe.americas.fill"
        case .github: return "chevron.left.forwardslash.chevron.right"
        case .network, .speedTest: return "wifi"
        case .disks, .folder, .trash, .dropZone: return "folder.fill"
        case .photos, .mirror: return "photo"
        case .terminal: return "terminal.fill"
        case .system, .temperature, .devices, .activity, .appTime: return "cpu"
        case .stocks, .crypto: return "chart.line.uptrend.xyaxis"
        case .smartHome: return "house.fill"
        case .shortcut, .apps, .toolbox: return "square.grid.2x2.fill"
        case .passwordGenerator: return "key.fill"
        case .moon: return "moon.fill"
        case .companion: return "sparkles"
        case .starfield: return "starfield.fill"
        case .clipboard: return "doc.on.clipboard"
        case .widgetStack: return "square.3.layers.3d"
        }
    }
}

enum WidgetSize: String, Codable, CaseIterable, Identifiable {
    case small = "Small", medium = "Medium", large = "Large"
    case tile1x1 = "1×1", tile1x2 = "1×2", tile2x1 = "2×1", tile2x2 = "2×2", tile2x3 = "2×3", tile3x1 = "3×1", tile3x2 = "3×2"
    var id: String { rawValue }
    var dimensions: CGSize {
        switch self {
        case .small, .tile1x1: return CGSize(width: 190, height: 190)
        case .tile1x2: return CGSize(width: 190, height: 310)
        case .medium, .tile2x1: return CGSize(width: 310, height: 190)
        case .large, .tile2x2: return CGSize(width: 310, height: 310)
        case .tile2x3: return CGSize(width: 310, height: 465)
        case .tile3x1: return CGSize(width: 465, height: 155)
        case .tile3x2: return CGSize(width: 465, height: 310)
        }
    }
}

enum ClockDisplayStyle: String, Codable, CaseIterable, Identifiable {
    case analog = "Analog", digital = "Digital", minimal = "Minimal", world = "World"
    var id: String { rawValue }
}

struct WidgetInstance: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var kind: WidgetKind
    var size: WidgetSize = .tile2x2
    var title: String = ""
    var note: String = "A little space for a thought."
    var city: String = "San Francisco"
    var weatherScene: WeatherScene = .auto
    var weatherBackdrop: WeatherBackdrop = .soft
    var weatherBackground: WeatherBackground = .transparent
    var weatherUnit: WeatherUnit = .auto
    var weatherLiveAnimation = true
    var weatherUsesCurrentLocation = false
    var weatherLatitude: Double?
    var weatherLongitude: Double?
    var weatherLocationName: String?
    var webAddress = "https://example.com"
    var isOnDesktop = false
    var glassStyle: GlassStyle = .off
    var glass = false // Legacy field for decoding boards saved by earlier versions.
    var accentStyle: WidgetAccent = .system
    var positionLocked = false
    var showDate = true
    var use24Hour = false
    var showSeconds = false
    var clockStyle: ClockDisplayStyle = .digital
    var clockTheme: ClockTheme = .classic
    var clockTimeZone = "system"
    var x: Double = 180
    var y: Double = 180
    var stack: [WidgetKind] = [.clock, .weather, .calendar]
    var timerDuration = 1500
    var timerRemaining = 1500
    var timerEndsAt: Date?
    var timerRunning = false
    var calculatorDisplay = "0"
    var calculatorStoredValue: Double?
    var calculatorOperation: String?
    var calculatorStartsNew = false
    var reminderCompleted: [Bool] = [false, false, false]
    var reminderItems: [String] = ["Pick up groceries", "Stretch for a moment", "Take a short walk"]
    var calendarMonthOffset = 0
    var calendarViewMode: CalendarViewMode = .month
    var calendarWeekStart: CalendarWeekStart = .system
    var calendarAppearanceColor: CalendarColor = .theme
    var calendarAppearanceFont: CalendarFont = .rounded
    var calendarScale = 1.0
    var calendarClickAction: CalendarClickAction = .none
    var calendarClickURL = "https://calendar.google.com"
    var calendarShortcutName = ""
    var quoteIndex = 0
    var backgroundOpacity = 1.0
    var stocksSymbols: [String] = ["AAPL", "MSFT", "NVDA"]
    var cryptoCoins: [String] = ["bitcoin", "ethereum", "solana"]
    var currencyBase = "USD"
    var currencyQuotes: [String] = ["EUR", "GBP", "JPY", "INR"]
    var githubRepo = "morluto/rea"
    var batteryStyle: BatteryStyle = .gauge
    var toolboxTools: [String] = ToolboxTool.allCases.map(\.rawValue)
    var worldClockCities: [String] = ["America/New_York", "Europe/London", "Asia/Tokyo", "Australia/Sydney"]
    var temperatureUnit: WeatherUnit = .auto
    var showFanSpeed = true
    var deviceSort: String = "recent"
    var showDisconnectedDevices = true
    var networkUnit: String = "mbs"
    var showLocalAddress = true
    var networkInterfaceFilter: String = "all"
    var disksShowAll = true
    var showProgramList = true
    var appsList: [String] = ["Safari", "Mail", "Notes", "Calendar", "Music", "Photos", "Messages", "Maps", "App Store", "System Settings"]
    var appsLook = "grid"
    var appsIconSize = "auto"
    var appsShowNames = false
    var appsMarkRunning = true
    var dayProgressCounts = "whole"
    var dayProgressFrom = 9.0
    var dayProgressUntil = 17.0
    var dayProgressColors = "sky"

    init(kind: WidgetKind) {
        self.kind = kind
        self.title = kind.rawValue
        timerDuration = kind == .pomodoro ? 1500 : (kind == .timer ? 300 : 0)
        timerRemaining = timerDuration
    }
    enum CodingKeys: String, CodingKey { case id, kind, size, title, note, city, weatherScene, weatherBackdrop, weatherBackground, weatherUnit, weatherLiveAnimation, weatherUsesCurrentLocation, weatherLatitude, weatherLongitude, weatherLocationName, webAddress, isOnDesktop, glass, glassStyle, accentStyle, positionLocked, showDate, use24Hour, showSeconds, clockStyle, clockTheme, clockTimeZone, x, y, stack, timerDuration, timerRemaining, timerEndsAt, timerRunning, calculatorDisplay, calculatorStoredValue, calculatorOperation, calculatorStartsNew, reminderCompleted, reminderItems, calendarMonthOffset, calendarViewMode, calendarWeekStart, calendarAppearanceColor, calendarAppearanceFont, calendarScale, calendarClickAction, calendarClickURL, calendarShortcutName, quoteIndex, backgroundOpacity, stocksSymbols, cryptoCoins, currencyBase, currencyQuotes, githubRepo, batteryStyle, worldClockCities, toolboxTools, temperatureUnit, showFanSpeed, deviceSort, showDisconnectedDevices, networkUnit, showLocalAddress, networkInterfaceFilter, disksShowAll, showProgramList, appsList, appsLook, appsIconSize, appsShowNames, appsMarkRunning, dayProgressCounts, dayProgressFrom, dayProgressUntil, dayProgressColors }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try c.decode(WidgetKind.self, forKey: .kind)
        let savedSize = (try? c.decode(WidgetSize.self, forKey: .size)) ?? .tile2x2
        switch savedSize {
        case .small: size = .tile1x1
        case .medium: size = .tile2x1
        case .large: size = .tile2x2
        default: size = savedSize
        }
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? kind.rawValue
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? "A little space for a thought."
        city = try c.decodeIfPresent(String.self, forKey: .city) ?? "San Francisco"
        weatherScene = try c.decodeIfPresent(WeatherScene.self, forKey: .weatherScene) ?? .auto
        weatherBackdrop = try c.decodeIfPresent(WeatherBackdrop.self, forKey: .weatherBackdrop) ?? .soft
        weatherBackground = try c.decodeIfPresent(WeatherBackground.self, forKey: .weatherBackground) ?? .transparent
        weatherUnit = try c.decodeIfPresent(WeatherUnit.self, forKey: .weatherUnit) ?? .auto
        weatherLiveAnimation = try c.decodeIfPresent(Bool.self, forKey: .weatherLiveAnimation) ?? true
        weatherUsesCurrentLocation = try c.decodeIfPresent(Bool.self, forKey: .weatherUsesCurrentLocation) ?? false
        weatherLatitude = try c.decodeIfPresent(Double.self, forKey: .weatherLatitude)
        weatherLongitude = try c.decodeIfPresent(Double.self, forKey: .weatherLongitude)
        weatherLocationName = try c.decodeIfPresent(String.self, forKey: .weatherLocationName)
        webAddress = try c.decodeIfPresent(String.self, forKey: .webAddress) ?? "https://example.com"
        isOnDesktop = try c.decodeIfPresent(Bool.self, forKey: .isOnDesktop) ?? false
        if let style = try c.decodeIfPresent(GlassStyle.self, forKey: .glassStyle) { glassStyle = style }
        else { glassStyle = (try c.decodeIfPresent(Bool.self, forKey: .glass) ?? false) ? .frosted : .off }
        glass = glassStyle != .off
        accentStyle = try c.decodeIfPresent(WidgetAccent.self, forKey: .accentStyle) ?? .system
        positionLocked = try c.decodeIfPresent(Bool.self, forKey: .positionLocked) ?? false
        showDate = try c.decodeIfPresent(Bool.self, forKey: .showDate) ?? true
        use24Hour = try c.decodeIfPresent(Bool.self, forKey: .use24Hour) ?? false
        showSeconds = try c.decodeIfPresent(Bool.self, forKey: .showSeconds) ?? false
        clockStyle = try c.decodeIfPresent(ClockDisplayStyle.self, forKey: .clockStyle) ?? .digital
        clockTheme = try c.decodeIfPresent(ClockTheme.self, forKey: .clockTheme) ?? .classic
        clockTimeZone = try c.decodeIfPresent(String.self, forKey: .clockTimeZone) ?? "system"
        x = try c.decodeIfPresent(Double.self, forKey: .x) ?? 180
        y = try c.decodeIfPresent(Double.self, forKey: .y) ?? 180
        stack = try c.decodeIfPresent([WidgetKind].self, forKey: .stack) ?? [.clock, .weather, .calendar]
        timerDuration = try c.decodeIfPresent(Int.self, forKey: .timerDuration) ?? 1500
        timerRemaining = try c.decodeIfPresent(Int.self, forKey: .timerRemaining) ?? timerDuration
        timerEndsAt = try c.decodeIfPresent(Date.self, forKey: .timerEndsAt)
        timerRunning = try c.decodeIfPresent(Bool.self, forKey: .timerRunning) ?? false
        calculatorDisplay = try c.decodeIfPresent(String.self, forKey: .calculatorDisplay) ?? "0"
        calculatorStoredValue = try c.decodeIfPresent(Double.self, forKey: .calculatorStoredValue)
        calculatorOperation = try c.decodeIfPresent(String.self, forKey: .calculatorOperation)
        calculatorStartsNew = try c.decodeIfPresent(Bool.self, forKey: .calculatorStartsNew) ?? false
        reminderCompleted = try c.decodeIfPresent([Bool].self, forKey: .reminderCompleted) ?? [false, false, false]
        reminderItems = try c.decodeIfPresent([String].self, forKey: .reminderItems) ?? ["Pick up groceries", "Stretch for a moment", "Take a short walk"]
        calendarMonthOffset = try c.decodeIfPresent(Int.self, forKey: .calendarMonthOffset) ?? 0
        calendarViewMode = try c.decodeIfPresent(CalendarViewMode.self, forKey: .calendarViewMode) ?? .month
        calendarWeekStart = try c.decodeIfPresent(CalendarWeekStart.self, forKey: .calendarWeekStart) ?? .system
        calendarAppearanceColor = try c.decodeIfPresent(CalendarColor.self, forKey: .calendarAppearanceColor) ?? .theme
        calendarAppearanceFont = try c.decodeIfPresent(CalendarFont.self, forKey: .calendarAppearanceFont) ?? .rounded
        calendarScale = try c.decodeIfPresent(Double.self, forKey: .calendarScale) ?? 1.0
        calendarClickAction = try c.decodeIfPresent(CalendarClickAction.self, forKey: .calendarClickAction) ?? .none
        calendarClickURL = try c.decodeIfPresent(String.self, forKey: .calendarClickURL) ?? "https://calendar.google.com"
        calendarShortcutName = try c.decodeIfPresent(String.self, forKey: .calendarShortcutName) ?? ""
        quoteIndex = try c.decodeIfPresent(Int.self, forKey: .quoteIndex) ?? 0
        backgroundOpacity = try c.decodeIfPresent(Double.self, forKey: .backgroundOpacity) ?? 1.0
        stocksSymbols = try c.decodeIfPresent([String].self, forKey: .stocksSymbols) ?? ["AAPL", "MSFT", "NVDA"]
        cryptoCoins = try c.decodeIfPresent([String].self, forKey: .cryptoCoins) ?? ["bitcoin", "ethereum", "solana"]
        currencyBase = try c.decodeIfPresent(String.self, forKey: .currencyBase) ?? "USD"
        currencyQuotes = try c.decodeIfPresent([String].self, forKey: .currencyQuotes) ?? ["EUR", "GBP", "JPY", "INR"]
        githubRepo = try c.decodeIfPresent(String.self, forKey: .githubRepo) ?? "morluto/rea"
        batteryStyle = try c.decodeIfPresent(BatteryStyle.self, forKey: .batteryStyle) ?? .gauge
        worldClockCities = try c.decodeIfPresent([String].self, forKey: .worldClockCities) ?? ["America/New_York", "Europe/London", "Asia/Tokyo", "Australia/Sydney"]
        toolboxTools = try c.decodeIfPresent([String].self, forKey: .toolboxTools) ?? ToolboxTool.allCases.map(\.rawValue)
        temperatureUnit = try c.decodeIfPresent(WeatherUnit.self, forKey: .temperatureUnit) ?? .auto
        showFanSpeed = try c.decodeIfPresent(Bool.self, forKey: .showFanSpeed) ?? true
        deviceSort = try c.decodeIfPresent(String.self, forKey: .deviceSort) ?? "recent"
        showDisconnectedDevices = try c.decodeIfPresent(Bool.self, forKey: .showDisconnectedDevices) ?? true
        networkUnit = try c.decodeIfPresent(String.self, forKey: .networkUnit) ?? "mbs"
        showLocalAddress = try c.decodeIfPresent(Bool.self, forKey: .showLocalAddress) ?? true
        networkInterfaceFilter = try c.decodeIfPresent(String.self, forKey: .networkInterfaceFilter) ?? "all"
        disksShowAll = try c.decodeIfPresent(Bool.self, forKey: .disksShowAll) ?? true
        showProgramList = try c.decodeIfPresent(Bool.self, forKey: .showProgramList) ?? true
        appsList = try c.decodeIfPresent([String].self, forKey: .appsList) ?? ["Safari", "Mail", "Notes", "Calendar", "Music", "Photos", "Messages", "Maps", "App Store", "System Settings"]
        appsLook = try c.decodeIfPresent(String.self, forKey: .appsLook) ?? "grid"
        appsIconSize = try c.decodeIfPresent(String.self, forKey: .appsIconSize) ?? "auto"
        appsShowNames = try c.decodeIfPresent(Bool.self, forKey: .appsShowNames) ?? false
        appsMarkRunning = try c.decodeIfPresent(Bool.self, forKey: .appsMarkRunning) ?? true
        dayProgressCounts = try c.decodeIfPresent(String.self, forKey: .dayProgressCounts) ?? "whole"
        dayProgressFrom = try c.decodeIfPresent(Double.self, forKey: .dayProgressFrom) ?? 9.0
        dayProgressUntil = try c.decodeIfPresent(Double.self, forKey: .dayProgressUntil) ?? 17.0
        dayProgressColors = try c.decodeIfPresent(String.self, forKey: .dayProgressColors) ?? "sky"
    }
}

enum LockScreenWidgetKind: String, Codable, CaseIterable, Identifiable {
    case music = "Music", timer = "Timer", weather = "Weather", calendar = "Calendar", reminders = "Reminders", battery = "Battery", devices = "Bluetooth"
    var id: String { rawValue }
    var kind: WidgetKind { self == .devices ? .devices : (WidgetKind(rawValue: rawValue) ?? .calendar) }
    var symbol: String { self == .devices ? "dot.radiowaves.left.and.right" : kind.symbol }
}

enum LockScreenAppearance: String, Codable, CaseIterable, Identifiable { case dark = "Dark", light = "Light", automatic = "Automatic"; var id: String { rawValue } }
enum LockScreenGlass: String, Codable, CaseIterable, Identifiable { case off = "Off", frosted = "Frosted", clear = "Clear", liquid = "Liquid"; var id: String { rawValue } }
enum LockScreenAlignment: String, Codable, CaseIterable, Identifiable { case leading = "Left", center = "Center", trailing = "Right"; var id: String { rawValue } }
enum LockScreenWeatherStyle: String, Codable, CaseIterable, Identifiable { case inline = "Inline", circular = "Circular"; var id: String { rawValue } }

struct LockScreenSettings: Codable, Equatable {
    var enabled = false
    var widgets: [LockScreenWidgetKind] = [.weather, .calendar]
    var appearance: LockScreenAppearance = .automatic
    var glass: LockScreenGlass = .frosted
    var alignment: LockScreenAlignment = .center
    var weatherStyle: LockScreenWeatherStyle = .inline
    var verticalOffset = 0.0
}

enum ClockTheme: String, Codable, CaseIterable, Identifiable {
    case classic = "Classic", neon = "Neon", solar = "Solar", glass = "Glass", mono = "Mono"
    var id: String { rawValue }
    var color: String {
        switch self {
        case .classic: return "#B7F36B"
        case .neon: return "#50E9FF"
        case .solar: return "#FFB45E"
        case .glass: return "#C4D8FF"
        case .mono: return "#FFFFFF"
        }
    }
}

enum GlassStyle: String, Codable, CaseIterable, Identifiable {
    case off = "Off", frosted = "Frosted", solidDark = "Solid Dark", solidLight = "Solid Light", clear = "Clear", liquid = "Liquid"
    var id: String { rawValue }
}
enum WeatherScene: String, Codable, CaseIterable, Identifiable { case auto = "Auto", clear = "Clear", partlyCloudy = "Partly Cloudy", rain = "Rain", snow = "Snow", night = "Night"; var id: String { rawValue } }
enum WeatherBackdrop: String, Codable, CaseIterable, Identifiable { case full = "Full", soft = "Soft", none = "None"; var id: String { rawValue } }
enum WeatherUnit: String, Codable, CaseIterable, Identifiable { case auto = "Auto", celsius = "°C", fahrenheit = "°F"; var id: String { rawValue } }
enum WeatherBackground: String, Codable, CaseIterable, Identifiable { case transparent = "Transparent", sky = "Sky"; var id: String { rawValue } }
enum CalendarViewMode: String, Codable, CaseIterable, Identifiable { case month = "Month", agenda = "Agenda"; var id: String { rawValue } }
enum CalendarWeekStart: String, Codable, CaseIterable, Identifiable { case system = "This Mac", monday = "Monday", sunday = "Sunday"; var id: String { rawValue } }
enum CalendarColor: String, Codable, CaseIterable, Identifiable {
    case theme = "Theme", red = "Red", orange = "Orange", yellow = "Yellow", green = "Green", mint = "Mint", teal = "Teal", blue = "Blue", indigo = "Indigo", purple = "Purple", pink = "Pink", graphite = "Graphite"
    var id: String { rawValue }
    var hex: String? { switch self { case .theme: return nil; case .red: return "FF453A"; case .orange: return "FF9F0A"; case .yellow: return "FFD60A"; case .green: return "30D158"; case .mint: return "63E6BE"; case .teal: return "40C8E0"; case .blue: return "0A84FF"; case .indigo: return "5E5CE6"; case .purple: return "BF5AF2"; case .pink: return "FF375F"; case .graphite: return "8E8E93" } }
}
enum CalendarFont: String, Codable, CaseIterable, Identifiable { case rounded = "Rounded", system = "System", mono = "Mono", serif = "Serif"; var id: String { rawValue } }
enum CalendarClickAction: String, Codable, CaseIterable, Identifiable { case none = "None", openCalendar = "Open App", showAgenda = "Show Agenda", openURL = "Open URL", runShortcut = "Shortcut"; var id: String { rawValue } }
enum WidgetAccent: String, Codable, CaseIterable, Identifiable {
    case system = "System", lime = "Lime", cyan = "Cyan", violet = "Violet", amber = "Amber", rose = "Rose"
    var id: String { rawValue }
    var hex: String? { switch self { case .system: return nil; case .lime: return "B7F36B"; case .cyan: return "63D9FF"; case .violet: return "C5A0FF"; case .amber: return "FFBC68"; case .rose: return "FF8EA8" } }
}

enum LibrarySection: String, CaseIterable, Identifiable {
    case all = "All Widgets", essentials = "Essentials", productivity = "Productivity", system = "System", lifestyle = "Lifestyle"
    var id: String { rawValue }
    var kinds: [WidgetKind] {
        switch self {
        case .all: return WidgetKind.allCases
        case .essentials: return [.clock, .weather, .calendar, .reminders, .worldClock, .timer, .stopwatch, .countdown, .battery]
        case .productivity: return [.stickyNote, .quote, .pomodoro, .clipboard, .dropZone, .folder, .calculator, .unitConverter, .shortcut, .apps]
        case .system: return [.terminal, .airQuality, .music, .audio, .soundMixer, .system, .temperature, .devices, .network, .disks, .activity, .appTime, .speedTest]
        case .lifestyle: return [.photos, .smartHome, .webPage, .worldMap, .moon, .ambientSound, .starfield, .mirror, .companion]
        }
    }
}

enum ToolboxTool: String, Codable, CaseIterable, Identifiable {
    case stayAwake, darkMode, hideIcons, hiddenFiles, mute, ejectAll, displayOff, screenSaver, screenshot
    var id: String { rawValue }
    var name: String {
        switch self {
        case .stayAwake: return "Stay awake"
        case .darkMode: return "Dark Mode"
        case .hideIcons: return "Hide icons"
        case .hiddenFiles: return "Hidden files"
        case .mute: return "Mute"
        case .ejectAll: return "Eject all"
        case .displayOff: return "Display off"
        case .screenSaver: return "Screen saver"
        case .screenshot: return "Screenshot"
        }
    }
    var symbol: String {
        switch self {
        case .stayAwake: return "cup.and.saucer.fill"
        case .darkMode: return "circle.lefthalf.filled"
        case .hideIcons: return "eye.slash"
        case .hiddenFiles: return "doc.badge.gearshape"
        case .mute: return "speaker.slash.fill"
        case .ejectAll: return "eject.fill"
        case .displayOff: return "display"
        case .screenSaver: return "desktopcomputer.and.arrow.down"
        case .screenshot: return "camera.viewfinder"
        }
    }
}

enum BatteryStyle: String, Codable, CaseIterable, Identifiable {
    case gauge = "Gauge", ring = "Ring", devices = "Devices"
    var id: String { rawValue }
}

enum WorldClockCities {
    static let presets: [(name: String, zone: String)] = [
        ("New York", "America/New_York"), ("Los Angeles", "America/Los_Angeles"), ("Chicago", "America/Chicago"),
        ("Toronto", "America/Toronto"), ("Vancouver", "America/Vancouver"), ("Mexico City", "America/Mexico_City"),
        ("São Paulo", "America/Sao_Paulo"), ("London", "Europe/London"), ("Paris", "Europe/Paris"),
        ("Berlin", "Europe/Berlin"), ("Moscow", "Europe/Moscow"), ("Istanbul", "Europe/Istanbul"),
        ("Dubai", "Asia/Dubai"), ("Riyadh", "Asia/Riyadh"), ("Mumbai", "Asia/Kolkata"),
        ("Bangkok", "Asia/Bangkok"), ("Jakarta", "Asia/Jakarta"), ("Singapore", "Asia/Singapore"),
        ("Hong Kong", "Asia/Hong_Kong"), ("Shanghai", "Asia/Shanghai"), ("Seoul", "Asia/Seoul"),
        ("Tokyo", "Asia/Tokyo"), ("Sydney", "Australia/Sydney"), ("Auckland", "Pacific/Auckland"),
        ("Nairobi", "Africa/Nairobi"),
    ]
    static func displayName(for zone: String) -> String {
        presets.first { $0.zone == zone }?.name ?? zone.replacingOccurrences(of: "_", with: " ")
    }
}

enum BoardTheme: String, CaseIterable, Identifiable, Codable {
    case midnight = "Midnight", ocean = "Ocean", plum = "Plum", graphite = "Graphite"
    var id: String { rawValue }
    var accent: String {
        switch self { case .midnight: return "#B7F36B"; case .ocean: return "#73D7FF"; case .plum: return "#D5A7FF"; case .graphite: return "#F1C27D" }
    }
}
