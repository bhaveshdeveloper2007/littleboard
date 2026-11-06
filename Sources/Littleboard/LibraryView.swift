import AppKit
import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var model: BoardModel
    @StateObject private var uiState = LibraryUIState()
    @State private var calendarAppearanceExpanded = false
    @State private var githubTokenDraft = ""
    @State private var githubTokenSaved = false
    private let tabs = ["Library", "Lock Screen", "Custom", "Stacks"]

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 232)
            VStack(spacing: 0) {
                topbar
                if uiState.tab == "Lock Screen" { lockScreenPage }
                else if uiState.tab == "Custom" { customPage }
                else if uiState.tab == "Stacks" { stackPage }
                else { libraryPage }
            }
            .background(Palette.background)
        }
        .background(Palette.background)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $uiState.showingSettings) { SettingsView().environmentObject(model).frame(width: 650, height: 760) }
        .sheet(isPresented: Binding(get: { model.widgetSettingsID != nil }, set: { if !$0 { model.widgetSettingsID = nil } })) {
            if let id = model.widgetSettingsID {
                WidgetSettingsSheet(id: id).environmentObject(model).frame(width: 400, height: 470)
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                ZStack { RoundedRectangle(cornerRadius: 11).fill(Palette.accent(model.theme)).frame(width: 38, height: 38); Image(systemName: "square.grid.2x2.fill").font(.system(size: 16, weight: .bold)).foregroundStyle(Palette.background) }
                VStack(alignment: .leading, spacing: 2) { Text("littleboard").font(.system(size: 17, weight: .bold, design: .rounded)); Text("DESKTOP WIDGETS").font(.system(size: 8, weight: .semibold)).tracking(1.8).foregroundStyle(Palette.muted) }
            }.padding(.bottom, 30)

            Text("YOUR SPACE").font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(Palette.muted).padding(.bottom, 10)
            ForEach(tabs, id: \.self) { item in
                Button { uiState.tab = item } label: {
                    HStack(spacing: 11) { Image(systemName: icon(for: item)).frame(width: 18); Text(item); Spacer(); if item == "Library" { Text("\(WidgetKind.allCases.count)").font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(Palette.muted) } }
                        .font(.system(size: 12, weight: uiState.tab == item ? .semibold : .regular)).foregroundStyle(uiState.tab == item ? Palette.accent(model.theme) : Color.white.opacity(0.73)).padding(.horizontal, 11).frame(height: 39).background(uiState.tab == item ? Palette.raised : .clear, in: RoundedRectangle(cornerRadius: 10))
                }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle())
            }

            Text("CATEGORIES").font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(Palette.muted).padding(.top, 28).padding(.bottom, 10)
            ForEach(LibrarySection.allCases) { section in
                Button { model.selectedSection = section; uiState.tab = "Library" } label: {
                    HStack { Text(section.rawValue); Spacer(); if section == model.selectedSection && uiState.tab == "Library" { Circle().fill(Palette.accent(model.theme)).frame(width: 5, height: 5) } }
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(section == model.selectedSection && uiState.tab == "Library" ? .white : Palette.muted).padding(.horizontal, 11).frame(height: 32)
                }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle())
            }
            Spacer(minLength: 16)
            HStack { Image(systemName: "circle.grid.2x2.fill").foregroundStyle(Palette.accent(model.theme)); VStack(alignment: .leading, spacing: 3) { Text("DESKTOP").font(.system(size: 8, weight: .bold)).tracking(1.1).foregroundStyle(Palette.muted); Text("\(model.widgets.filter(\.isOnDesktop).count) widgets active").font(.system(size: 11, weight: .medium)) }; Spacer() }.padding(12).background(Palette.panel, in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(18).background(Color(hex: "151713")).overlay(alignment: .trailing) { Rectangle().fill(.white.opacity(0.06)).frame(width: 1) }
    }

    private var topbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) { Text(uiState.tab).font(.system(size: 19, weight: .bold, design: .rounded)); Text(subtitle).font(.system(size: 10)).foregroundStyle(Palette.muted) }
            Spacer()
            if uiState.tab == "Library" {
                HStack(spacing: 8) { Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted); TextField("Find a widget", text: $model.search).textFieldStyle(.plain).font(.system(size: 11)).frame(width: 135) }.padding(9).background(Palette.panel, in: RoundedRectangle(cornerRadius: 9))
            }
            Menu { ForEach(model.profiles, id: \.self) { profile in Button(profile) { model.profileName = profile } }; Divider(); Button("Save current profile…") { model.addProfile() } } label: { HStack(spacing: 7) { Circle().fill(Palette.accent(model.theme)).frame(width: 6, height: 6); Text(model.profileName); Image(systemName: "chevron.down").font(.system(size: 8)) }.font(.system(size: 10, weight: .semibold)).padding(9).background(Palette.panel, in: RoundedRectangle(cornerRadius: 9)) }
            IconButton(symbol: "gearshape", help: "Settings") { uiState.showingSettings = true }
        }.padding(.horizontal, 24).padding(.vertical, 16).overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.06)).frame(height: 1) }
    }
    private var subtitle: String {
        switch uiState.tab { case "Library": return "Pick a widget and make your desktop yours."; case "Lock Screen": return "Choose which widgets appear when this Mac is locked."; case "Custom": return "Create a note card with your own words."; default: return "Group a few favorites into one desktop card." }
    }
    private func icon(for item: String) -> String { switch item { case "Library": return "square.grid.2x2"; case "Lock Screen": return "lock"; case "Custom": return "plus.square.dashed"; default: return "square.3.layers.3d" } }

    private var libraryPage: some View {
        HStack(spacing: 0) {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 148), spacing: 12)], spacing: 12) {
                    ForEach(model.filteredKinds) { kind in
                        WidgetTile(kind: kind, selected: model.current?.kind == kind, active: model.widgets.first(where: { $0.kind == kind })?.isOnDesktop ?? false) { model.select(kind) }
                    }
                }.padding(20)
            }.frame(maxWidth: .infinity)
            Rectangle().fill(.white.opacity(0.06)).frame(width: 1)
            detailPane.frame(width: 300)
        }
    }

    private var detailPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack { Text("PREVIEW").font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(Palette.muted); Spacer(); Pill(title: model.current?.size.rawValue ?? "Widget") }
                WidgetCard(model: model, id: model.selectedWidget, desktop: false)
                    .aspectRatio(itemAspectRatio, contentMode: .fit)
                    .background(previewWallpaper)
                if let item = model.current {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) { ForEach([WidgetSize.tile1x1, .tile1x2, .tile2x1, .tile2x2, .tile2x3, .tile3x1, .tile3x2]) { size in Button { model.update(item.id) { $0.size = size } } label: { Text(size.rawValue).font(.system(size: 10, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 9).background(item.size == size ? Palette.raised : .clear, in: RoundedRectangle(cornerRadius: 8)).foregroundStyle(item.size == size ? .white : Palette.muted) }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle()) } }
                    Rectangle().fill(.white.opacity(0.06)).frame(height: 1)
                    HStack { Text(item.kind.rawValue).font(.system(size: 15, weight: .bold, design: .rounded)); Spacer(); Pill(title: item.kind == .weather ? "Live" : item.kind == .system ? "Local" : "Ready") }
                    Text(description(item.kind)).font(.system(size: 10)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                    widgetDesignControls(item)
                    widgetOptions(item)
                    if item.isOnDesktop { desktopPositionControls(item) }
                    Button { item.isOnDesktop ? model.removeFromDesktop(item.id) : model.addCurrentToDesktop() } label: { Label(item.isOnDesktop ? "Remove from Desktop" : "Add to Desktop", systemImage: item.isOnDesktop ? "minus" : "plus") }.buttonStyle(AccentButtonStyle()).frame(maxWidth: .infinity)
                    Text("Drag the widget anywhere on your desktop. Position and size are saved locally.").font(.system(size: 9)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                } else { Text("Choose a widget to preview it.").foregroundStyle(Palette.muted) }
            }.padding(18)
        }.background(Color(hex: "131511"))
    }

    private var itemAspectRatio: CGFloat {
        guard let size = model.current?.size else { return 1 }
        return size.dimensions.width / size.dimensions.height
    }

    // The preview floats over a bright stock scene instead of the library's dark
    // chrome, so transparency and glass settings read the way they will on the
    // real desktop.
    private var previewWallpaper: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                LinearGradient(colors: [Color(hex: "9CC0E0"), Color(hex: "E8D9AE")], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [Color(hex: "FFF3C4").opacity(0.95), .clear], center: UnitPoint(x: 0.74, y: 0.2), startRadius: 4, endRadius: geometry.size.width * 0.6)
                Ellipse()
                    .fill(LinearGradient(colors: [Color(hex: "5C6B4C"), Color(hex: "3A4531")], startPoint: .top, endPoint: .bottom))
                    .frame(width: geometry.size.width * 1.7, height: geometry.size.height * 0.6)
                    .offset(y: geometry.size.height * 0.24)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.white.opacity(0.1), lineWidth: 1))
    }

    private func desktopPositionControls(_ item: WidgetInstance) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text("PLACEMENT").font(.system(size: 9, weight: .bold)).tracking(1.2).foregroundStyle(Palette.muted); Spacer(); Text("Drag on desktop to fine tune").font(.system(size: 8)).foregroundStyle(Palette.muted) }
            HStack(spacing: 8) {
                coordinateField("X", value: item.x) { model.setWidgetPosition(item.id, x: $0, y: item.y) }
                coordinateField("Y", value: item.y) { model.setWidgetPosition(item.id, x: item.x, y: $0) }
            }
            HStack(spacing: 6) {
                ForEach(["Top Left", "Top Right", "Center", "Bottom Left", "Bottom Right"], id: \.self) { anchor in
                    Button(anchor) { model.placeWidget(item.id, anchor: anchor) }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle()).font(.system(size: 8, weight: .semibold)).padding(.horizontal, 7).padding(.vertical, 6).background(Palette.raised, in: Capsule())
                }
            }
        }
        .padding(12).background(Palette.panel, in: RoundedRectangle(cornerRadius: 11))
    }

    private func coordinateField(_ title: String, value: Double, set: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 5) { Text(title).font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.muted); TextField(title, value: Binding(get: { value }, set: set), format: .number.precision(.fractionLength(0))).textFieldStyle(.plain).font(.system(size: 10, design: .monospaced)).frame(minWidth: 42).multilineTextAlignment(.trailing) }.padding(8).background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 7))
    }

    private func widgetDesignControls(_ item: WidgetInstance) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack { Text("ACCENT COLOR").font(.system(size: 8, weight: .bold)).tracking(1).foregroundStyle(Palette.muted); Spacer(); Text(item.accentStyle.rawValue).font(.system(size: 8, weight: .medium)).foregroundStyle(Palette.muted) }
                HStack(spacing: 8) {
                    ForEach(WidgetAccent.allCases) { accent in
                        Button { model.update(item.id) { $0.accentStyle = accent } } label: {
                            Circle().fill(accent.hex.map(Color.init(hex:)) ?? Palette.accent(model.theme)).frame(width: 16, height: 16).padding(4)
                                .overlay(Circle().stroke(item.accentStyle == accent ? .white.opacity(0.9) : .white.opacity(0.12), lineWidth: item.accentStyle == accent ? 1.5 : 1))
                        }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle()).help(accent.rawValue)
                    }
                    Spacer()
                }
            }
            transparencySlider(item.id, level: item.backgroundOpacity)
        }.padding(10).background(Palette.panel, in: RoundedRectangle(cornerRadius: 10))
    }

    private func transparencySlider(_ id: UUID, level: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text("BACKGROUND").font(.system(size: 8, weight: .bold)).tracking(1).foregroundStyle(Palette.muted); Spacer(); Text("\(Int((level * 100).rounded()))% opaque").font(.system(size: 8, weight: .medium)).foregroundStyle(Palette.muted) }
            HStack(spacing: 10) {
                Image(systemName: "square.on.square").font(.system(size: 10)).foregroundStyle(Palette.muted).help("More transparent")
                Slider(value: Binding(get: { model.widgets.first(where: { $0.id == id })?.backgroundOpacity ?? 1 }, set: { value in model.update(id) { $0.backgroundOpacity = value } }), in: 0.15...1)
                Image(systemName: "square.fill").font(.system(size: 10)).foregroundStyle(Palette.muted).help("Fully opaque")
            }
        }
    }

    @ViewBuilder private func widgetOptions(_ item: WidgetInstance) -> some View {
        switch item.kind {
        case .worldClock:
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    Toggle("24-hour time", isOn: binding(item.id, \.use24Hour)).toggleStyle(.switch).font(.system(size: 10))
                    Toggle("Seconds", isOn: binding(item.id, \.showSeconds)).toggleStyle(.switch).font(.system(size: 10))
                }
                Text("CITIES").font(.system(size: 8, weight: .bold)).tracking(0.8).foregroundStyle(Palette.muted)
                ForEach(Array(item.worldClockCities.enumerated()), id: \.element) { index, city in
                    HStack(spacing: 8) {
                        Text("\(index + 1)").font(.system(size: 8, weight: .bold, design: .rounded)).foregroundStyle(Palette.muted).frame(width: 12)
                        Text(WorldClockCities.displayName(for: city)).font(.system(size: 10, weight: .medium)).lineLimit(1)
                        Spacer(minLength: 4)
                        Button { model.update(item.id) { $0.worldClockCities.move(fromOffsets: IndexSet(integer: index), toOffset: max(0, index - 1)) } } label: { Image(systemName: "chevron.up").font(.system(size: 8, weight: .semibold)) }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle()).foregroundStyle(Palette.muted).disabled(index == 0).help("Move up")
                        Button { model.update(item.id) { $0.worldClockCities.move(fromOffsets: IndexSet(integer: index), toOffset: min($0.worldClockCities.count, index + 2)) } } label: { Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold)) }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle()).foregroundStyle(Palette.muted).help("Move down")
                        Button { model.update(item.id) { $0.worldClockCities.removeAll { $0 == city } } } label: { Image(systemName: "minus.circle.fill").font(.system(size: 11)) }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle()).foregroundStyle(.red.opacity(0.7)).help("Remove city")
                    }.padding(.horizontal, 9).padding(.vertical, 6).background(Palette.panel, in: RoundedRectangle(cornerRadius: 8))
                }
                Menu { ForEach(WorldClockCities.presets, id: \.zone) { preset in
                    Button { model.update(item.id) { if !$0.worldClockCities.contains(preset.zone) { $0.worldClockCities.append(preset.zone) } } } label: {
                        if item.worldClockCities.contains(preset.zone) { Label(preset.name, systemImage: "checkmark") } else { Text(preset.name) }
                    }
                } } label: {
                    Label("Add city", systemImage: "plus.circle.fill").font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.accent(model.theme))
                }.menuStyle(.borderlessButton)
            }
        case .clock, .simpleClock, .flipClock, .wordClock:
            HStack(spacing: 7) { ForEach(ClockDisplayStyle.allCases) { style in Button { model.update(item.id) { $0.clockStyle = style } } label: { Text(style.rawValue).font(.system(size: 10, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 8).background(item.clockStyle == style ? Palette.raised : .clear, in: RoundedRectangle(cornerRadius: 8)).foregroundStyle(item.clockStyle == style ? .white : Palette.muted) }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle()) } }
            Text("CLOCK THEME").font(.system(size: 8, weight: .bold)).tracking(1).foregroundStyle(Palette.muted)
            HStack(spacing: 6) { ForEach(ClockTheme.allCases) { theme in Button { model.update(item.id) { $0.clockTheme = theme } } label: { HStack(spacing: 5) { Circle().fill(Color(hex: theme.color)).frame(width: 8, height: 8); Text(theme.rawValue).font(.system(size: 9, weight: .semibold)) }.frame(maxWidth: .infinity).padding(.vertical, 7).background(item.clockTheme == theme ? Palette.raised : .clear, in: RoundedRectangle(cornerRadius: 8)).foregroundStyle(item.clockTheme == theme ? .white : Palette.muted) }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle()) } }
            Text("TIME ZONE").font(.system(size: 8, weight: .bold)).tracking(1).foregroundStyle(Palette.muted)
            Menu {
                Button { model.update(item.id) { $0.clockTimeZone = "system" } } label: { if item.clockTimeZone == "system" { Label("This Mac · \(TimeZone.current.identifier)", systemImage: "checkmark") } else { Text("This Mac · \(TimeZone.current.identifier)") } }
                Divider()
                ForEach([("New York", "America/New_York"), ("Los Angeles", "America/Los_Angeles"), ("London", "Europe/London"), ("Paris", "Europe/Paris"), ("Dubai", "Asia/Dubai"), ("Mumbai", "Asia/Kolkata"), ("Singapore", "Asia/Singapore"), ("Tokyo", "Asia/Tokyo"), ("Sydney", "Australia/Sydney")], id: \.1) { city, identifier in
                    Button { model.update(item.id) { $0.clockTimeZone = identifier } } label: { if item.clockTimeZone == identifier { Label(city, systemImage: "checkmark") } else { Text(city) } }
                }
            } label: { HStack { Image(systemName: "globe"); Text(item.clockTimeZone == "system" ? "This Mac · \(TimeZone.current.identifier)" : TimeZone(identifier: item.clockTimeZone)?.identifier ?? item.clockTimeZone); Spacer(); Image(systemName: "chevron.down") }.font(.system(size: 10, weight: .medium)).padding(9).background(Palette.panel, in: RoundedRectangle(cornerRadius: 8)) }.menuStyle(.borderlessButton)
            Toggle("Show date", isOn: binding(item.id, \.showDate)).toggleStyle(.switch); Toggle("24-hour time", isOn: binding(item.id, \.use24Hour)).toggleStyle(.switch); Toggle("Seconds", isOn: binding(item.id, \.showSeconds)).toggleStyle(.switch)
        case .calendar:
            calendarChoiceRow("VIEW", choices: CalendarViewMode.allCases.map(\.rawValue), selected: item.calendarViewMode.rawValue) { value in if let mode = CalendarViewMode(rawValue: value) { model.update(item.id) { $0.calendarViewMode = mode } } }
            Text("Agenda shows upcoming events. The 1×2 layout always uses Agenda.").font(.system(size: 8)).foregroundStyle(Palette.muted)
            calendarChoiceRow("WEEK STARTS ON", choices: [CalendarWeekStart.monday.rawValue, CalendarWeekStart.sunday.rawValue], selected: item.calendarWeekStart == .system ? (Calendar.current.firstWeekday == 2 ? "Monday" : "Sunday") : item.calendarWeekStart.rawValue) { value in if let start = CalendarWeekStart(rawValue: value) { model.update(item.id) { $0.calendarWeekStart = start } } }
            VStack(spacing: 0) {
                Button { calendarAppearanceExpanded.toggle() } label: {
                    HStack { Text("Appearance").font(.system(size: 10, weight: .semibold)); Spacer(); Text("\(item.calendarAppearanceColor.rawValue) · \(item.calendarAppearanceFont.rawValue) · \(Int(item.calendarScale * 100))%").font(.system(size: 8, weight: .medium)).foregroundStyle(Palette.muted); Image(systemName: calendarAppearanceExpanded ? "chevron.up" : "chevron.right").font(.system(size: 8, weight: .bold)).foregroundStyle(Palette.muted) }.padding(10).contentShape(Rectangle())
                }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle())
                if calendarAppearanceExpanded {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack { Text("Scale").font(.system(size: 9, weight: .semibold)); Slider(value: Binding(get: { item.calendarScale }, set: { value in model.update(item.id) { $0.calendarScale = value } }), in: 0.75...1.15); Text("\(Int(item.calendarScale * 100))%").font(.system(size: 8, design: .monospaced)).foregroundStyle(Palette.muted) }
                        Toggle("Lock Position", isOn: Binding(get: { model.widgets.first(where: { $0.id == item.id })?.positionLocked ?? false }, set: { value in model.update(item.id) { $0.positionLocked = value } })).toggleStyle(.switch)
                        Text("COLOUR").font(.system(size: 8, weight: .bold)).tracking(0.8).foregroundStyle(Palette.muted)
                        HStack(spacing: 4) { ForEach(CalendarColor.allCases) { color in Button { model.update(item.id) { $0.calendarAppearanceColor = color } } label: { Circle().fill(color.hex.map(Color.init(hex:)) ?? Palette.accent(model.theme)).frame(width: 15, height: 15).padding(3).overlay(Circle().stroke(item.calendarAppearanceColor == color ? .white : .white.opacity(0.12), lineWidth: item.calendarAppearanceColor == color ? 1.5 : 1)) }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle()).help(color.rawValue) } }
                        HStack(spacing: 4) { ForEach(CalendarFont.allCases) { font in Button { model.update(item.id) { $0.calendarAppearanceFont = font } } label: { Text(font.rawValue).font(.system(size: 8, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 6).background(item.calendarAppearanceFont == font ? Palette.raised : .clear, in: Capsule()).foregroundStyle(item.calendarAppearanceFont == font ? .white : Palette.muted) }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle()) } }
                    }.padding(10)
                }
            }.background(Palette.panel, in: RoundedRectangle(cornerRadius: 10))
            VStack(spacing: 0) {
                Menu { ForEach(CalendarClickAction.allCases) { action in Button(action.rawValue) { model.update(item.id) { $0.calendarClickAction = action } } } } label: {
                    HStack { Text("On Click").font(.system(size: 10, weight: .semibold)); Spacer(); Text(item.calendarClickAction.rawValue).font(.system(size: 8, weight: .medium)).foregroundStyle(Palette.muted); Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold)).foregroundStyle(Palette.muted) }.padding(10).contentShape(Rectangle())
                }.menuStyle(.borderlessButton)
                if item.calendarClickAction == .openURL { TextField("URL", text: Binding(get: { model.widgets.first(where: { $0.id == item.id })?.calendarClickURL ?? item.calendarClickURL }, set: { value in model.update(item.id) { $0.calendarClickURL = value } })).textFieldStyle(.roundedBorder).font(.system(size: 9)).padding(.horizontal, 10).padding(.bottom, 8) }
                if item.calendarClickAction == .runShortcut { TextField("Shortcut name", text: Binding(get: { model.widgets.first(where: { $0.id == item.id })?.calendarShortcutName ?? item.calendarShortcutName }, set: { value in model.update(item.id) { $0.calendarShortcutName = value } })).textFieldStyle(.roundedBorder).font(.system(size: 9)).padding(.horizontal, 10).padding(.bottom, 8) }
            }.background(Palette.panel, in: RoundedRectangle(cornerRadius: 10))
        case .weather:
            VStack(alignment: .leading, spacing: 6) {
                Text("SCENE").font(.system(size: 8, weight: .bold)).tracking(0.8).foregroundStyle(Palette.muted)
                HStack(spacing: 4) {
                    ForEach(WeatherScene.allCases) { scene in
                        Button { model.update(item.id) { $0.weatherScene = scene } } label: {
                            VStack(spacing: 4) { Image(systemName: weatherSceneIcon(scene)).font(.system(size: 11)); Text(scene.rawValue).font(.system(size: 7, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7) }
                                .frame(maxWidth: .infinity).frame(height: 40).background(item.weatherScene == scene ? Palette.accent(model.theme).opacity(0.16) : Palette.panel, in: RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(item.weatherScene == scene ? Palette.accent(model.theme) : .white.opacity(0.05), lineWidth: 1)).foregroundStyle(item.weatherScene == scene ? Palette.accent(model.theme) : .white.opacity(0.72))
                        }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle())
                    }
                }
                Text("Auto follows the live forecast; other scenes change the look only.").font(.system(size: 8)).foregroundStyle(Palette.muted)
            }
            weatherChoiceRow("BACKDROP", choices: WeatherBackdrop.allCases.map(\.rawValue), selected: item.weatherBackdrop.rawValue) { value in if let style = WeatherBackdrop(rawValue: value) { model.update(item.id) { $0.weatherBackdrop = style } } }
            weatherChoiceRow("BACKGROUND", choices: WeatherBackground.allCases.map(\.rawValue), selected: item.weatherBackground.rawValue) { value in if let style = WeatherBackground(rawValue: value) { model.update(item.id) { $0.weatherBackground = style } } }
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("LOCATION").font(.system(size: 8, weight: .bold)).tracking(0.8).foregroundStyle(Palette.muted)
                }
                HStack(spacing: 5) { ForEach(["This Mac", "Choose City"], id: \.self) { choice in Button(choice) { model.update(item.id) { $0.weatherUsesCurrentLocation = choice == "This Mac" } }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle()).font(.system(size: 8, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 6).background((item.weatherUsesCurrentLocation == (choice == "This Mac")) ? Palette.raised : .clear, in: Capsule()) } }
                if item.weatherUsesCurrentLocation {
                    Text(item.weatherLocationName ?? (model.locationStatus.isEmpty ? "Uses this Mac’s location; updates with weather refreshes." : model.locationStatus)).font(.system(size: 8)).foregroundStyle(Palette.muted)
                    HStack {
                        Button { model.requestWeatherLocation(item.id) } label: { Label("Allow Location Access", systemImage: "location.fill") }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle()).font(.system(size: 9, weight: .semibold)).foregroundStyle(Palette.accent(model.theme))
                        Button { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!) } label: { Label("System Settings", systemImage: "gearshape") }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle()).font(.system(size: 9, weight: .semibold)).foregroundStyle(Palette.accent(model.theme))
                    }
                } else {
                    TextField("City", text: Binding(get: { model.widgets.first(where: { $0.id == item.id })?.city ?? item.city }, set: { city in model.update(item.id) { $0.city = city; $0.weatherLatitude = nil; $0.weatherLongitude = nil; $0.weatherLocationName = nil } })).textFieldStyle(.roundedBorder).font(.system(size: 10))
                }
            }
            weatherChoiceRow("UNITS", choices: WeatherUnit.allCases.map(\.rawValue), selected: item.weatherUnit.rawValue) { value in if let unit = WeatherUnit(rawValue: value) { model.update(item.id) { $0.weatherUnit = unit } } }
            Toggle("Live weather animation", isOn: binding(item.id, \.weatherLiveAnimation)).toggleStyle(.switch)
        case .webPage: TextField("Web address", text: binding(item.id, \.webAddress)).textFieldStyle(.roundedBorder).font(.system(size: 10))
        case .stocks: csvField("Symbols, comma separated", item, \.stocksSymbols)
        case .crypto: csvField("Coins, comma separated", item, \.cryptoCoins)
        case .currencies:
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) { Text("BASE").font(.system(size: 8, weight: .bold)).tracking(0.8).foregroundStyle(Palette.muted); TextField("Base", text: binding(item.id, \.currencyBase)).textFieldStyle(.roundedBorder).font(.system(size: 10)) }
                csvField("Show rates for, comma separated", item, \.currencyQuotes)
            }
        case .github:
            VStack(alignment: .leading, spacing: 8) {
                Text("ACCESS TOKEN").font(.system(size: 8, weight: .bold)).tracking(0.8).foregroundStyle(Palette.muted)
                HStack(spacing: 6) {
                    SecureField("ghp_…", text: $githubTokenDraft).textFieldStyle(.roundedBorder).font(.system(size: 10))
                    Button("Save") {
                        LiveFeed.GitHubKeychain.save(githubTokenDraft.trimmingCharacters(in: .whitespaces))
                        githubTokenDraft = ""
                        githubTokenSaved = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { githubTokenSaved = false }
                    }
                    .font(.system(size: 9, weight: .semibold)).buttonStyle(FullAreaButtonStyle()).foregroundStyle(Palette.accent(model.theme))
                    if LiveFeed.GitHubKeychain.load() != nil {
                        Button { LiveFeed.GitHubKeychain.delete() } label: { Image(systemName: "trash").font(.system(size: 9)) }
                            .buttonStyle(FullAreaButtonStyle()).foregroundStyle(.red.opacity(0.7)).help("Remove stored token")
                    }
                }
                Text(githubTokenSaved ? "Token saved to the macOS Keychain." : "Create a token on github.com under Settings → Developer settings. \"repo\" (read) and \"notifications\" are enough. It is stored in the macOS Keychain, never in a layout or backup.")
                    .font(.system(size: 8)).foregroundStyle(githubTokenSaved ? Color(hex: "30D158") : Palette.muted).fixedSize(horizontal: false, vertical: true)
                Text("REPOSITORY FOR THE BUILD STATE").font(.system(size: 8, weight: .bold)).tracking(0.8).foregroundStyle(Palette.muted)
                TextField("owner/name", text: binding(item.id, \.githubRepo)).textFieldStyle(.roundedBorder).font(.system(size: 10)).autocorrectionDisabled()
                Text("Optional. Shows the latest GitHub Actions run, stars and open issues.").font(.system(size: 8)).foregroundStyle(Palette.muted)
            }
        case .battery:
            VStack(alignment: .leading, spacing: 6) {
                Text("STYLE").font(.system(size: 8, weight: .bold)).tracking(0.8).foregroundStyle(Palette.muted)
                HStack(spacing: 6) {
                    ForEach(BatteryStyle.allCases) { style in
                        Button { model.update(item.id) { $0.batteryStyle = style } } label: {
                            Text(style.rawValue).font(.system(size: 10, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 8)
                                .background(item.batteryStyle == style ? Palette.raised : .clear, in: RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(item.batteryStyle == style ? .white : Palette.muted)
                        }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle())
                    }
                }
                Text("Devices shows this Mac plus connected Bluetooth accessories as battery rings.").font(.system(size: 8)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            }
        case .toolbox:
            VStack(alignment: .leading, spacing: 6) {
                Text("TOOLS ON THE WIDGET").font(.system(size: 8, weight: .bold)).tracking(0.8).foregroundStyle(Palette.muted)
                ForEach(ToolboxTool.allCases) { tool in
                    let enabled = item.toolboxTools.contains(tool.rawValue)
                    HStack(spacing: 9) {
                        Image(systemName: tool.symbol).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.accent(model.theme)).frame(width: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(tool.name).font(.system(size: 10, weight: .semibold))
                            Text(toolSubtitle(tool)).font(.system(size: 7.5)).foregroundStyle(Palette.muted).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Toggle("", isOn: Binding(
                            get: { model.widgets.first(where: { $0.id == item.id })?.toolboxTools.contains(tool.rawValue) ?? false },
                            set: { on in model.update(item.id) { widget in
                                if on { if !widget.toolboxTools.contains(tool.rawValue) { widget.toolboxTools.append(tool.rawValue) } }
                                else { widget.toolboxTools.removeAll { $0 == tool.rawValue } }
                            } }
                        )).toggleStyle(.switch).labelsHidden()
                    }.padding(.horizontal, 9).padding(.vertical, 6).background(Palette.panel, in: RoundedRectangle(cornerRadius: 9))
                }
                Text("Hide icons and Hidden files restart Finder briefly. Dark Mode and Mute may ask for automation permission once.").font(.system(size: 7.5)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            }
        case .temperature:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("UNIT").font(.system(size: 8, weight: .bold)).tracking(0.8).foregroundStyle(Palette.muted)
                    Spacer(minLength: 4)
                    HStack(spacing: 4) {
                        ForEach([WeatherUnit.auto, .celsius, .fahrenheit]) { unit in
                            Button { model.update(item.id) { $0.temperatureUnit = unit } } label: {
                                Text(unit.rawValue).font(.system(size: 9, weight: .semibold)).padding(.horizontal, 9).padding(.vertical, 5)
                                    .background(item.temperatureUnit == unit ? Palette.raised : .clear, in: Capsule())
                                    .foregroundStyle(item.temperatureUnit == unit ? .white : Palette.muted)
                            }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle())
                        }
                    }.background(Palette.panel, in: Capsule())
                }
                HStack(spacing: 6) {
                    Text("FAN SPEED").font(.system(size: 8, weight: .bold)).tracking(0.8).foregroundStyle(Palette.muted)
                    Spacer(minLength: 4)
                    HStack(spacing: 4) {
                        Button { model.update(item.id) { $0.showFanSpeed = true } } label: {
                            Text("Show").font(.system(size: 9, weight: .semibold)).padding(.horizontal, 9).padding(.vertical, 5)
                                .background(item.showFanSpeed ? Palette.raised : .clear, in: Capsule())
                                .foregroundStyle(item.showFanSpeed ? .white : Palette.muted)
                        }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle())
                        Button { model.update(item.id) { $0.showFanSpeed = false } } label: {
                            Text("Hide").font(.system(size: 9, weight: .semibold)).padding(.horizontal, 9).padding(.vertical, 5)
                                .background(item.showFanSpeed ? .clear : Palette.raised, in: Capsule())
                                .foregroundStyle(item.showFanSpeed ? Palette.muted : .white)
                        }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle())
                    }.background(Palette.panel, in: Capsule())
                }
                Text("Read from the Mac's own sensors every three seconds, only while the widget is on screen. Nothing leaves your Mac.").font(.system(size: 8)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            }
        case .devices:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("SORT BY").font(.system(size: 8, weight: .bold)).tracking(0.8).foregroundStyle(Palette.muted)
                    Spacer(minLength: 4)
                    HStack(spacing: 4) {
                        ForEach(["recent", "battery"], id: \.self) { sort in
                            Button { model.update(item.id) { $0.deviceSort = sort } } label: {
                                Text(sort == "recent" ? "Recent" : "Battery").font(.system(size: 9, weight: .semibold)).padding(.horizontal, 9).padding(.vertical, 5)
                                    .background(item.deviceSort == sort ? Palette.raised : .clear, in: Capsule())
                                    .foregroundStyle(item.deviceSort == sort ? .white : Palette.muted)
                            }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle())
                        }
                    }.background(Palette.panel, in: Capsule())
                }
                HStack(spacing: 6) {
                    Text("DISCONNECTED").font(.system(size: 8, weight: .bold)).tracking(0.8).foregroundStyle(Palette.muted)
                    Spacer(minLength: 4)
                    HStack(spacing: 4) {
                        Button { model.update(item.id) { $0.showDisconnectedDevices = true } } label: {
                            Text("Show").font(.system(size: 9, weight: .semibold)).padding(.horizontal, 9).padding(.vertical, 5)
                                .background(item.showDisconnectedDevices ? Palette.raised : .clear, in: Capsule())
                                .foregroundStyle(item.showDisconnectedDevices ? .white : Palette.muted)
                        }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle())
                        Button { model.update(item.id) { $0.showDisconnectedDevices = false } } label: {
                            Text("Hide").font(.system(size: 9, weight: .semibold)).padding(.horizontal, 9).padding(.vertical, 5)
                                .background(item.showDisconnectedDevices ? .clear : Palette.raised, in: Capsule())
                                .foregroundStyle(item.showDisconnectedDevices ? Palette.muted : .white)
                        }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle())
                    }.background(Palette.panel, in: Capsule())
                }
                Text("Remembered devices stay listed after they disconnect, so reconnecting is one click.").font(.system(size: 8)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            }
        case .apps:
            let catalog = LiveFeed.applicationCatalog()
            let capacityHint = "\(item.appsList.count) added"
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("LOOK").font(.system(size: 8, weight: .bold)).tracking(0.8).foregroundStyle(Palette.muted)
                    Spacer(minLength: 4)
                    HStack(spacing: 4) {
                        ForEach(["grid", "dock", "list", "tiles"], id: \.self) { look in
                            Button { model.update(item.id) { $0.appsLook = look } } label: {
                                Text(look.capitalized).font(.system(size: 9, weight: .semibold)).padding(.horizontal, 8).padding(.vertical, 5)
                                    .background(item.appsLook == look ? Palette.raised : .clear, in: Capsule())
                                    .foregroundStyle(item.appsLook == look ? .white : Palette.muted)
                            }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle())
                        }
                    }.background(Palette.panel, in: Capsule())
                }
                HStack(spacing: 6) {
                    Text("ICON SIZE").font(.system(size: 8, weight: .bold)).tracking(0.8).foregroundStyle(Palette.muted)
                    Spacer(minLength: 4)
                    HStack(spacing: 4) {
                        ForEach(["small", "medium", "auto", "large"], id: \.self) { size in
                            Button { model.update(item.id) { $0.appsIconSize = size } } label: {
                                Text(size.capitalized).font(.system(size: 9, weight: .semibold)).padding(.horizontal, 8).padding(.vertical, 5)
                                    .background(item.appsIconSize == size ? Palette.raised : .clear, in: Capsule())
                                    .foregroundStyle(item.appsIconSize == size ? .white : Palette.muted)
                            }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle())
                        }
                    }.background(Palette.panel, in: Capsule())
                }
                HStack(spacing: 6) {
                    Text("APP NAMES").font(.system(size: 8, weight: .bold)).tracking(0.8).foregroundStyle(Palette.muted)
                    Spacer(minLength: 4)
                    HStack(spacing: 4) {
                        ForEach([true, false], id: \.self) { show in
                            Button { model.update(item.id) { $0.appsShowNames = show } } label: {
                                Text(show ? "Show" : "Hide").font(.system(size: 9, weight: .semibold)).padding(.horizontal, 8).padding(.vertical, 5)
                                    .background(item.appsShowNames == show ? Palette.raised : .clear, in: Capsule())
                                    .foregroundStyle(item.appsShowNames == show ? .white : Palette.muted)
                            }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle())
                        }
                    }.background(Palette.panel, in: Capsule())
                }
                HStack(spacing: 6) {
                    Text("OPEN APPS").font(.system(size: 8, weight: .bold)).tracking(0.8).foregroundStyle(Palette.muted)
                    Spacer(minLength: 4)
                    HStack(spacing: 4) {
                        ForEach([true, false], id: \.self) { mark in
                            Button { model.update(item.id) { $0.appsMarkRunning = mark } } label: {
                                Text(mark ? "Mark with a dot" : "Hide").font(.system(size: 9, weight: .semibold)).padding(.horizontal, 8).padding(.vertical, 5)
                                    .background(item.appsMarkRunning == mark ? Palette.raised : .clear, in: Capsule())
                                    .foregroundStyle(item.appsMarkRunning == mark ? .white : Palette.muted)
                            }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle())
                        }
                    }.background(Palette.panel, in: Capsule())
                }
                Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
                Text("APPS").font(.system(size: 8, weight: .bold)).tracking(0.8).foregroundStyle(Palette.muted)
                ForEach(item.appsList, id: \.self) { appName in
                    HStack(spacing: 8) {
                        if let entry = catalog.first(where: { $0.name == appName }) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: entry.path)).resizable().frame(width: 17, height: 17).clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        Text(appName).font(.system(size: 10, weight: .medium)).lineLimit(1)
                        Spacer(minLength: 4)
                        Button { model.update(item.id) { $0.appsList.removeAll { $0 == appName } } } label: { Image(systemName: "minus.circle.fill").font(.system(size: 11)) }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle()).foregroundStyle(.red.opacity(0.7)).help("Remove")
                    }.padding(.horizontal, 9).padding(.vertical, 5).background(Palette.panel, in: RoundedRectangle(cornerRadius: 8))
                }
                Menu {
                    ForEach(catalog.prefix(80), id: \.path) { entry in
                        Button { model.update(item.id) { if !$0.appsList.contains(entry.name) { $0.appsList.append(entry.name) } } } label: {
                            if item.appsList.contains(entry.name) { Label(entry.name, systemImage: "checkmark") } else { Text(entry.name) }
                        }
                    }
                } label: {
                    Label("Add App…", systemImage: "plus.circle.fill").font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.accent(model.theme))
                }.menuStyle(.borderlessButton)
                Text("\(capacityHint). This size shows the first ones that fit.").font(.system(size: 8)).foregroundStyle(Palette.muted)
            }
        case .disks:
            VStack(alignment: .leading, spacing: 8) {
                Text("SHOW").font(.system(size: 8, weight: .bold)).tracking(0.8).foregroundStyle(Palette.muted)
                HStack(spacing: 4) {
                    ForEach([true, false], id: \.self) { showAll in
                        Button { model.update(item.id) { $0.disksShowAll = showAll } } label: {
                            Text(showAll ? "All disks" : "Startup disk").font(.system(size: 9, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 7)
                                .background(item.disksShowAll == showAll ? Palette.raised : .clear, in: RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(item.disksShowAll == showAll ? .white : Palette.muted)
                        }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle())
                    }
                }.background(Palette.panel, in: Capsule())
                Text("Click a disk to open it in Finder. External drives get an eject button on hover. A disk with less than a tenth free turns red and pulses.").font(.system(size: 8)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            }
        case .activity:
            VStack(alignment: .leading, spacing: 8) {
                Text("PROGRAM LIST").font(.system(size: 8, weight: .bold)).tracking(0.8).foregroundStyle(Palette.muted)
                HStack(spacing: 4) {
                    ForEach([true, false], id: \.self) { on in
                        Button { model.update(item.id) { $0.showProgramList = on } } label: {
                            Text(on ? "On" : "Off").font(.system(size: 9, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 7)
                                .background(item.showProgramList == on ? Palette.raised : .clear, in: RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(item.showProgramList == on ? .white : Palette.muted)
                        }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle())
                    }
                }.background(Palette.panel, in: Capsule())
                Text("Measured every two seconds while the tile is visible. Programs with several processes are added up, like a browser and its helpers. Only names and sizes are read.").font(.system(size: 8)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            }
        case .dayProgress:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("COUNTS").font(.system(size: 8, weight: .bold)).tracking(0.8).foregroundStyle(Palette.muted)
                    Spacer(minLength: 4)
                    HStack(spacing: 4) {
                        ForEach(["whole", "hours"], id: \.self) { counts in
                            Button { model.update(item.id) { $0.dayProgressCounts = counts } } label: {
                                Text(counts == "whole" ? "Whole day" : "My hours").font(.system(size: 9, weight: .semibold)).padding(.horizontal, 9).padding(.vertical, 5)
                                    .background(item.dayProgressCounts == counts ? Palette.raised : .clear, in: Capsule())
                                    .foregroundStyle(item.dayProgressCounts == counts ? .white : Palette.muted)
                            }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle())
                        }
                    }.background(Palette.panel, in: Capsule())
                }
                if item.dayProgressCounts == "hours" {
                    HStack(spacing: 10) {
                        Text("FROM").font(.system(size: 8, weight: .bold)).tracking(0.8).foregroundStyle(Palette.muted)
                        Spacer(minLength: 4)
                        Stepper(value: Binding(get: { model.widgets.first(where: { $0.id == item.id })?.dayProgressFrom ?? 9 }, set: { value in model.update(item.id) { $0.dayProgressFrom = min(max(value, 0), 24) } }), in: 0...24, step: 0.5) {
                            Text(Self.clockLabel(item.dayProgressFrom)).font(.system(size: 10, weight: .semibold, design: .monospaced)).monospacedDigit()
                        }
                    }.padding(.horizontal, 9).padding(.vertical, 6).background(Palette.panel, in: RoundedRectangle(cornerRadius: 9))
                    HStack(spacing: 10) {
                        Text("UNTIL").font(.system(size: 8, weight: .bold)).tracking(0.8).foregroundStyle(Palette.muted)
                        Spacer(minLength: 4)
                        Stepper(value: Binding(get: { model.widgets.first(where: { $0.id == item.id })?.dayProgressUntil ?? 17 }, set: { value in model.update(item.id) { $0.dayProgressUntil = min(max(value, 0), 24) } }), in: 0...24, step: 0.5) {
                            Text(Self.clockLabel(item.dayProgressUntil)).font(.system(size: 10, weight: .semibold, design: .monospaced)).monospacedDigit()
                        }
                    }.padding(.horizontal, 9).padding(.vertical, 6).background(Palette.panel, in: RoundedRectangle(cornerRadius: 9))
                    Text("A work day, a school day, your waking hours. An end before the start runs past midnight.").font(.system(size: 8)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 6) {
                    Text("COLOURS").font(.system(size: 8, weight: .bold)).tracking(0.8).foregroundStyle(Palette.muted)
                    Spacer(minLength: 4)
                    HStack(spacing: 4) {
                        ForEach(["sky", "theme"], id: \.self) { colors in
                            Button { model.update(item.id) { $0.dayProgressColors = colors } } label: {
                                Text(colors == "sky" ? "Sky" : "Theme").font(.system(size: 9, weight: .semibold)).padding(.horizontal, 9).padding(.vertical, 5)
                                    .background(item.dayProgressColors == colors ? Palette.raised : .clear, in: Capsule())
                                    .foregroundStyle(item.dayProgressColors == colors ? .white : Palette.muted)
                            }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle())
                        }
                    }.background(Palette.panel, in: Capsule())
                }
                Text("The arc takes the colours of the sky as the day goes by — dawn, daylight, dusk and night.").font(.system(size: 8)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            }
        case .network:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("INTERFACE").font(.system(size: 8, weight: .bold)).tracking(0.8).foregroundStyle(Palette.muted)
                    Spacer(minLength: 4)
                    Menu {
                        Button { model.update(item.id) { $0.networkInterfaceFilter = "all" } } label: {
                            if item.networkInterfaceFilter == "all" { Label("All interfaces", systemImage: "checkmark") } else { Text("All interfaces") }
                        }
                        ForEach(LiveFeed.interfaceTraffic(), id: \.name) { sample in
                            Button { model.update(item.id) { $0.networkInterfaceFilter = sample.name } } label: {
                                if item.networkInterfaceFilter == sample.name { Label(sample.name, systemImage: "checkmark") } else { Text(sample.name) }
                            }
                        }
                    } label: {
                        HStack(spacing: 5) { Text(item.networkInterfaceFilter == "all" ? "All" : item.networkInterfaceFilter); Image(systemName: "chevron.down").font(.system(size: 7)) }
                            .font(.system(size: 9, weight: .semibold)).padding(.horizontal, 9).padding(.vertical, 5).background(Palette.panel, in: Capsule())
                    }.menuStyle(.borderlessButton)
                }
                HStack(spacing: 6) {
                    Text("UNIT").font(.system(size: 8, weight: .bold)).tracking(0.8).foregroundStyle(Palette.muted)
                    Spacer(minLength: 4)
                    HStack(spacing: 4) {
                        ForEach(["mbs", "mbit"], id: \.self) { unit in
                            Button { model.update(item.id) { $0.networkUnit = unit } } label: {
                                Text(unit == "mbs" ? "MB/s" : "Mbit/s").font(.system(size: 9, weight: .semibold)).padding(.horizontal, 9).padding(.vertical, 5)
                                    .background(item.networkUnit == unit ? Palette.raised : .clear, in: Capsule())
                                    .foregroundStyle(item.networkUnit == unit ? .white : Palette.muted)
                            }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle())
                        }
                    }.background(Palette.panel, in: Capsule())
                }
                HStack(spacing: 6) {
                    Text("LOCAL ADDRESS").font(.system(size: 8, weight: .bold)).tracking(0.8).foregroundStyle(Palette.muted)
                    Spacer(minLength: 4)
                    HStack(spacing: 4) {
                        Button { model.update(item.id) { $0.showLocalAddress = true } } label: {
                            Text("Show").font(.system(size: 9, weight: .semibold)).padding(.horizontal, 9).padding(.vertical, 5)
                                .background(item.showLocalAddress ? Palette.raised : .clear, in: Capsule())
                                .foregroundStyle(item.showLocalAddress ? .white : Palette.muted)
                        }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle())
                        Button { model.update(item.id) { $0.showLocalAddress = false } } label: {
                            Text("Hide").font(.system(size: 9, weight: .semibold)).padding(.horizontal, 9).padding(.vertical, 5)
                                .background(item.showLocalAddress ? .clear : Palette.raised, in: Capsule())
                                .foregroundStyle(item.showLocalAddress ? Palette.muted : .white)
                        }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle())
                    }.background(Palette.panel, in: Capsule())
                }
                Text("Every active connection added together. On a Mac with a VPN up, that counts the same traffic twice. Mbit/s is what an internet plan is sold in.").font(.system(size: 8)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            }
        case .stickyNote, .custom: TextField("Note", text: binding(item.id, \.note), axis: .vertical).textFieldStyle(.roundedBorder).font(.system(size: 10)).lineLimit(3...5)
        case .reminders:
            ForEach(Array(item.reminderItems.enumerated()), id: \.offset) { index, _ in
                TextField("Reminder", text: Binding(get: { let values = model.widgets.first(where: { $0.id == item.id })?.reminderItems ?? []; return values.indices.contains(index) ? values[index] : "" }, set: { value in model.update(item.id) { if $0.reminderItems.indices.contains(index) { $0.reminderItems[index] = value } } })).textFieldStyle(.roundedBorder).font(.system(size: 10))
            }
            Button("Add reminder") { model.addReminder(item.id) }.font(.system(size: 10))
        case .widgetStack: Menu("Choose cards") { ForEach([WidgetKind.clock, .weather, .calendar, .quote, .dayProgress]) { kind in Button { model.update(item.id) { if $0.stack.contains(kind) { $0.stack.removeAll { $0 == kind } } else if $0.stack.count < 3 { $0.stack.append(kind) } } } label: { if item.stack.contains(kind) { Label(kind.rawValue, systemImage: "checkmark") } else { Text(kind.rawValue) } } } }
        default: EmptyView()
        }
    }
    private func weatherChoiceRow(_ title: String, choices: [String], selected: String, action: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 8, weight: .bold)).tracking(0.8).foregroundStyle(Palette.muted)
            HStack(spacing: 5) {
                ForEach(choices, id: \.self) { choice in
                    Button(choice) { action(choice) }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle()).font(.system(size: 8, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 6).background(selected == choice ? Palette.raised : .clear, in: Capsule()).foregroundStyle(selected == choice ? .white : Palette.muted)
                }
            }.background(Palette.panel, in: Capsule())
        }
    }
    private func calendarChoiceRow(_ title: String, choices: [String], selected: String, action: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 8, weight: .bold)).tracking(0.8).foregroundStyle(Palette.muted)
            HStack(spacing: 4) { ForEach(choices, id: \.self) { choice in Button(choice) { action(choice) }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle()).font(.system(size: 8, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 6).background(selected == choice ? Palette.raised : .clear, in: Capsule()).foregroundStyle(selected == choice ? .white : Palette.muted) } }.background(Palette.panel, in: Capsule())
        }
    }
    private func weatherSceneIcon(_ scene: WeatherScene) -> String {
        switch scene { case .auto: return "sparkles"; case .clear: return "sun.max.fill"; case .partlyCloudy: return "cloud.sun.fill"; case .rain: return "cloud.rain.fill"; case .snow: return "cloud.snow.fill"; case .night: return "moon.stars.fill" }
    }
    private func binding<T>(_ id: UUID, _ keyPath: WritableKeyPath<WidgetInstance, T>) -> Binding<T> { Binding(get: { model.widgets.first(where: { $0.id == id })?[keyPath: keyPath] ?? model.widgets[0][keyPath: keyPath] }, set: { newValue in model.update(id) { $0[keyPath: keyPath] = newValue } }) }
    private func csvField(_ label: String, _ item: WidgetInstance, _ keyPath: WritableKeyPath<WidgetInstance, [String]>) -> some View {
        TextField(label, text: Binding(
            get: { (model.widgets.first(where: { $0.id == item.id })?[keyPath: keyPath] ?? []).joined(separator: ", ") },
            set: { value in model.update(item.id) { $0[keyPath: keyPath] = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } } }
        )).textFieldStyle(.roundedBorder).font(.system(size: 10))
    }
    static func clockLabel(_ hours: Double) -> String {
        let total = Int((hours * 60).rounded())
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
    private func toolSubtitle(_ tool: ToolboxTool) -> String {
        switch tool {
        case .stayAwake: return "Keeps the Mac from sleeping, for as long as you choose"
        case .darkMode: return "Switches the whole system between light and dark"
        case .hideIcons: return "Clears the desktop for a screen share or screenshot"
        case .hiddenFiles: return "Shows files Finder normally hides"
        case .mute: return "Mutes and unmutes the sound output"
        case .ejectAll: return "Ejects every external drive and disk image"
        case .displayOff: return "Turns the display off right away"
        case .screenSaver: return "Starts your screen saver now"
        case .screenshot: return "Saves a screenshot to the Desktop"
        }
    }
    private func description(_ kind: WidgetKind) -> String {
        switch kind { case .clock: return "A custom clock face with your choice of style, timezone, and display options."; case .weather: return "Live current conditions, hourly and seven-day forecasts, and air quality. Enter a city to change the location."; case .calendar: return "A compact view of the current month, rendered locally."; case .stickyNote, .custom: return "Write a short note. Its text is saved on this Mac."; case .widgetStack: return "A simple card that rotates among selected local widget previews."; default: return "A native widget preview. Some integrations require a data source that is not configured in this open example." }
    }

    private var lockScreenPage: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("LOCK SCREEN WIDGETS").font(.system(size: 9, weight: .bold)).tracking(1.2).foregroundStyle(Palette.muted).padding(.bottom, 4)
                    ForEach(LockScreenWidgetKind.allCases) { option in
                        let selected = model.lockScreenSettings.widgets.contains(option)
                        Button { model.setLockScreenWidget(option, enabled: !selected) } label: {
                            HStack(spacing: 9) {
                                Image(systemName: option.symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.accent(model.theme)).frame(width: 30, height: 30).background(Palette.raised, in: RoundedRectangle(cornerRadius: 9))
                                VStack(alignment: .leading, spacing: 2) { Text(option.rawValue).font(.system(size: 10, weight: .semibold)); Text(lockWidgetSubtitle(option)).font(.system(size: 7, weight: .medium)).foregroundStyle(Palette.muted).lineLimit(1) }
                                Spacer(minLength: 4)
                                Image(systemName: selected ? "checkmark.circle.fill" : "plus.circle").font(.system(size: 12)).foregroundStyle(selected ? Palette.accent(model.theme) : Palette.muted)
                            }.padding(8).background(selected ? Palette.raised : Palette.panel.opacity(0.55), in: RoundedRectangle(cornerRadius: 11)).overlay(RoundedRectangle(cornerRadius: 11).stroke(selected ? Palette.accent(model.theme).opacity(0.45) : .white.opacity(0.04), lineWidth: 1))
                        }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle())
                    }
                    Spacer(minLength: 12)
                    Text("Notch features are intentionally excluded.").font(.system(size: 8)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                }.padding(16)
            }.frame(width: 205)
            Rectangle().fill(.white.opacity(0.06)).frame(width: 1)
            VStack(spacing: 0) {
                HStack { Text("PREVIEW").font(.system(size: 9, weight: .bold)).tracking(1.4).foregroundStyle(Palette.muted); Spacer(); Pill(title: "Lock Screen") }.padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 10)
                LockScreenDashboard(model: model).padding(.horizontal, 18).frame(maxWidth: .infinity, maxHeight: 310)
                Text("The overlay is shown after macOS locks and is removed when the session unlocks.").font(.system(size: 8)).foregroundStyle(Palette.muted).multilineTextAlignment(.center).padding(.horizontal, 20).padding(.top, 9)
                Spacer(minLength: 8)
            }.frame(minWidth: 360, maxWidth: .infinity)
            Rectangle().fill(.white.opacity(0.06)).frame(width: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle("Show widgets when locked", isOn: lockScreenBinding(\.enabled)).toggleStyle(.switch).font(.system(size: 10, weight: .semibold))
                    lockSettingsSection("APPEARANCE") {
                        lockScreenChoiceRow(choices: LockScreenAppearance.allCases, selection: model.lockScreenSettings.appearance) { value in updateLockSettings { $0.appearance = value } }
                    }
                    lockSettingsSection("GLASS") {
                        lockScreenChoiceRow(choices: LockScreenGlass.allCases, selection: model.lockScreenSettings.glass) { value in updateLockSettings { $0.glass = value } }
                    }
                    lockSettingsSection("WEATHER LAYOUT") {
                        lockScreenChoiceRow(choices: LockScreenWeatherStyle.allCases, selection: model.lockScreenSettings.weatherStyle) { value in updateLockSettings { $0.weatherStyle = value } }
                    }
                    lockSettingsSection("POSITION") {
                        lockScreenChoiceRow(choices: LockScreenAlignment.allCases, selection: model.lockScreenSettings.alignment) { value in updateLockSettings { $0.alignment = value } }
                        HStack { Text("Vertical position").font(.system(size: 9)); Slider(value: lockScreenBinding(\.verticalOffset), in: -120...120); Text("\(Int(model.lockScreenSettings.verticalOffset))").font(.system(size: 8, design: .monospaced)).foregroundStyle(Palette.muted) }
                    }
                    Text("Uses the open-source SkyLightWindow layer to place widgets above the macOS lock screen. Lock state is monitored locally; widgets are hidden immediately on unlock.").font(.system(size: 8)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                }.padding(16)
            }.frame(width: 285).background(Color(hex: "131511"))
        }
    }

    private func lockWidgetSubtitle(_ option: LockScreenWidgetKind) -> String {
        switch option { case .music: return "Playback controls and now playing"; case .timer: return "Timer and countdown controls"; case .weather: return "Conditions and forecast"; case .calendar: return "Month and upcoming events"; case .reminders: return "Your saved checklist"; case .battery: return "Mac battery status"; case .devices: return "Connected Bluetooth devices" }
    }
    private func updateLockSettings(_ change: (inout LockScreenSettings) -> Void) { var settings = model.lockScreenSettings; change(&settings); model.lockScreenSettings = settings }
    private func lockScreenBinding<Value>(_ keyPath: WritableKeyPath<LockScreenSettings, Value>) -> Binding<Value> {
        Binding(get: { model.lockScreenSettings[keyPath: keyPath] }, set: { value in updateLockSettings { $0[keyPath: keyPath] = value } })
    }
    private func lockSettingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) { Text(title).font(.system(size: 8, weight: .bold)).tracking(1).foregroundStyle(Palette.muted); content() }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(Palette.panel, in: RoundedRectangle(cornerRadius: 11))
    }
    private func lockScreenChoiceRow<Choice: RawRepresentable & CaseIterable & Identifiable & Equatable>(choices: Choice.AllCases, selection: Choice, action: @escaping (Choice) -> Void) -> some View where Choice.RawValue == String {
        HStack(spacing: 3) {
            ForEach(Array(choices)) { choice in Button(choice.rawValue) { action(choice) }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle()).font(.system(size: 8, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7).frame(maxWidth: .infinity).padding(.vertical, 7).background(selection == choice ? Palette.raised : .clear, in: Capsule()).foregroundStyle(selection == choice ? .white : Palette.muted) }
        }.background(Color.black.opacity(0.15), in: Capsule())
    }
    private var customPage: some View { VStack(alignment: .leading, spacing: 18) { Text("A personal widget, made simple.").font(.system(size: 22, weight: .bold, design: .rounded)); Text("Create a desktop note card, then edit its words in the preview settings.").font(.system(size: 12)).foregroundStyle(Palette.muted); HStack(spacing: 16) { WidgetCard(model: model, id: model.widgets.first(where: { $0.kind == .custom })?.id, desktop: false).frame(width: 250, height: 210); VStack(alignment: .leading, spacing: 12) { Button("Create custom card") { model.select(.custom) }.buttonStyle(AccentButtonStyle()); Text("Change the note from the widget preview panel after selecting the card.").font(.system(size: 10)).foregroundStyle(Palette.muted) }; Spacer() }.frame(height: 230); Spacer() }.padding(30) }
    private var stackPage: some View { VStack(alignment: .leading, spacing: 18) { Text("A small stack for your desktop").font(.system(size: 22, weight: .bold, design: .rounded)); Text("Combine local cards and keep the group in one movable window.").font(.system(size: 12)).foregroundStyle(Palette.muted); HStack(spacing: 20) { WidgetCard(model: model, id: model.widgets.first(where: { $0.kind == .widgetStack })?.id, desktop: false).frame(width: 260, height: 240); VStack(alignment: .leading, spacing: 12) { Button("Create widget stack") { model.select(.widgetStack) }.buttonStyle(AccentButtonStyle()); Text("Select the stack tile to choose the cards it cycles through.").font(.system(size: 10)).foregroundStyle(Palette.muted) }; Spacer() }.frame(height: 260); Spacer() }.padding(30) }
}

@MainActor private final class LibraryUIState: ObservableObject {
    @Published var tab = "Library"
    @Published var showingSettings = false
}

private struct WidgetTile: View {
    @EnvironmentObject private var model: BoardModel
    let kind: WidgetKind; let selected: Bool; let active: Bool; let action: () -> Void
    var body: some View { Button(action: action) { VStack(alignment: .leading, spacing: 14) { HStack { Image(systemName: kind.symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.accent(model.theme)).frame(width: 34, height: 34).background(Palette.panel, in: RoundedRectangle(cornerRadius: 10)); Spacer(); if active { Circle().fill(Palette.accent(model.theme)).frame(width: 6, height: 6) } }; VStack(alignment: .leading, spacing: 4) { Text(kind.rawValue).font(.system(size: 11, weight: .semibold)); Text(kind == .weather ? "LIVE WEATHER" : kind == .system ? "LOCAL STATUS" : "DESKTOP WIDGET").font(.system(size: 7, weight: .bold)).tracking(1).foregroundStyle(Palette.muted) } }.padding(13).frame(maxWidth: .infinity, alignment: .leading).frame(height: 100).background(selected ? Color(hex: "272E21") : Palette.panel, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? Palette.accent(model.theme).opacity(0.7) : .white.opacity(0.035), lineWidth: 1)) }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle()) }
}

private struct AccentButtonStyle: ButtonStyle {
    @EnvironmentObject private var model: BoardModel
    func makeBody(configuration: Configuration) -> some View { configuration.label.font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.background).padding(.vertical, 11).background(Palette.accent(model.theme).opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 10)) }
}

struct SettingsView: View {
    @EnvironmentObject private var model: BoardModel
    private let glassOptions: [GlassStyle] = [.frosted, .solidDark, .solidLight, .clear, .liquid]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                Text("Settings & Design").font(.system(size: 22, weight: .bold, design: .rounded))
                HStack(spacing: 4) {
                    ForEach(["Look", "Desktop", "Layouts", "App"], id: \.self) { tab in
                        Text(tab).font(.system(size: 10, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 9)
                            .foregroundStyle(tab == "Look" ? Palette.background : Palette.muted)
                            .background(tab == "Look" ? Palette.accent(model.theme) : .clear, in: RoundedRectangle(cornerRadius: 9))
                    }
                }.padding(4).background(Palette.panel, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 12) {
                    Text("LIVE LOOK · ALL DESKTOP WIDGETS").font(.system(size: 9, weight: .bold)).tracking(1.1).foregroundStyle(Palette.muted)
                    HStack(spacing: 9) {
                        lookPreviewTile("Clock", "clock", Date.now.formatted(.dateTime.hour().minute()), width: 1)
                        lookPreviewTile("Calendar", "calendar", Date.now.formatted(.dateTime.weekday(.wide)), width: 0.8)
                        lookPreviewTile("Battery", "battery.100percent", "95%", width: 0.8)
                    }.frame(height: 104)
                    Text("Changes update the widgets on your desktop. Per-widget settings can still override the shared glass style.").font(.system(size: 9)).foregroundStyle(Palette.muted)
                    Divider().overlay(.white.opacity(0.08))
                    Text("Glass").font(.system(size: 12, weight: .semibold))
                    HStack(spacing: 7) {
                        ForEach(glassOptions) { option in
                            Button { model.lookGlassStyle = option } label: {
                                VStack(spacing: 6) {
                                    RoundedRectangle(cornerRadius: 8).fill(glassSwatch(option)).frame(height: 36)
                                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(option == model.lookGlassStyle ? 0.8 : 0.14), lineWidth: option == model.lookGlassStyle ? 2 : 1))
                                    Text(option.rawValue).font(.system(size: 8, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                                }.padding(6).frame(maxWidth: .infinity).background(option == model.lookGlassStyle ? Palette.raised : .clear, in: RoundedRectangle(cornerRadius: 10))
                            }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle())
                        }
                    }
                    Text(glassDescription(model.lookGlassStyle)).font(.system(size: 9)).foregroundStyle(Palette.muted)
                    Divider().overlay(.white.opacity(0.08))
                    HStack { Text("Corner radius").font(.system(size: 11, weight: .medium)); Slider(value: $model.lookCornerRadius, in: 8...38); Text("\(Int(model.lookCornerRadius)) pt").font(.system(size: 9, design: .monospaced)).foregroundStyle(Palette.muted).frame(width: 46, alignment: .trailing) }
                    Toggle(isOn: $model.uniformColors) {
                        VStack(alignment: .leading, spacing: 3) { Text("Uniform colors").font(.system(size: 11, weight: .medium)); Text("Use one theme color for widget icons and accents.").font(.system(size: 9)).foregroundStyle(Palette.muted) }
                    }.toggleStyle(.switch)
                }.padding(13).background(Palette.panel, in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 10) {
                    Text("THEME PRESETS").font(.system(size: 9, weight: .bold)).tracking(1.1).foregroundStyle(Palette.muted)
                    HStack(spacing: 8) {
                        ForEach(BoardTheme.allCases) { theme in
                            Button { model.theme = theme } label: {
                                HStack(spacing: 7) { Circle().fill(Palette.accent(theme)).frame(width: 16, height: 16); Text(theme.rawValue).font(.system(size: 9, weight: .semibold)); Spacer(minLength: 0); if theme == model.theme { Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.accent(theme)) } }
                                    .padding(9).frame(maxWidth: .infinity).background(theme == model.theme ? Palette.raised : Palette.panel, in: RoundedRectangle(cornerRadius: 9))
                            }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle())
                        }
                    }
                    Text("The selected palette recolors widget icons and shared accents across the desktop.").font(.system(size: 9)).foregroundStyle(Palette.muted)
                }
            }.padding(20)
        }.background(Palette.background).preferredColorScheme(.dark)
    }
    private func lookPreviewTile(_ name: String, _ symbol: String, _ value: String, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(model.uniformColors ? Palette.accent(model.theme) : .white)
                .frame(width: 26, height: 26).background(model.lookGlassStyle == .clear ? .clear : .white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            Text(name).font(.system(size: 8, weight: .medium)).foregroundStyle(.white.opacity(0.65))
            Text(value).font(.system(size: 16, weight: .light, design: .rounded)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
        }.padding(9).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(glassSwatch(model.lookGlassStyle), in: RoundedRectangle(cornerRadius: model.lookCornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: model.lookCornerRadius, style: .continuous).stroke(.white.opacity(0.2), lineWidth: 1))
    }
    private func glassSwatch(_ style: GlassStyle) -> Color {
        switch style {
        case .off, .frosted: return Color(hex: "556070").opacity(0.72)
        case .solidDark: return Color.black.opacity(0.92)
        case .solidLight: return Color.white.opacity(0.86)
        case .clear: return Palette.accent(model.theme).opacity(0.12)
        case .liquid: return Palette.accent(model.theme).opacity(0.30)
        }
    }
    private func glassDescription(_ style: GlassStyle) -> String {
        switch style {
        case .off: return "Use each widget’s own glass setting."
        case .frosted: return "Soft blur with a tinted surface for readable widgets."
        case .solidDark: return "Opaque dark cards with crisp edges."
        case .solidLight: return "Bright translucent cards with a light surface."
        case .clear: return "Minimal fill so the desktop wallpaper shows through."
        case .liquid: return "Glossy liquid glass with a bright edge and highlight."
        }
    }
}

private struct WidgetSettingsSheet: View {
    @EnvironmentObject private var model: BoardModel
    @Environment(\.dismiss) private var dismiss
    let id: UUID
    private var item: WidgetInstance? { model.widgets.first(where: { $0.id == id }) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Widget Settings").font(.system(size: 20, weight: .bold, design: .rounded))
                    Text(item?.kind.rawValue ?? "Widget").font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                Spacer()
                IconButton(symbol: "xmark", help: "Close") { dismiss() }
            }
            Text("SIZE").font(.system(size: 9, weight: .bold)).tracking(1.3).foregroundStyle(Palette.muted)
            if let item {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 3), spacing: 7) {
                    ForEach([WidgetSize.tile1x1, .tile1x2, .tile2x1, .tile2x2, .tile2x3, .tile3x1, .tile3x2]) { size in
                        Button { model.update(id) { $0.size = size } } label: {
                            Text(size.rawValue).font(.system(size: 11, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 10)
                                .background(item.size == size ? Palette.raised : Palette.panel, in: RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(item.size == size ? .white : Palette.muted)
                        }.contentShape(Rectangle()).buttonStyle(FullAreaButtonStyle())
                    }
                }
                HStack { Text("Glass style"); Spacer(); Picker("Glass style", selection: Binding(get: { model.widgets.first(where: { $0.id == id })?.glassStyle ?? .off }, set: { value in model.update(id) { $0.glassStyle = value } })) { ForEach(GlassStyle.allCases) { Text($0.rawValue).tag($0) } }.labelsHidden().frame(width: 130) }
                HStack { Text("Accent color"); Spacer(); Picker("Accent color", selection: Binding(get: { model.widgets.first(where: { $0.id == id })?.accentStyle ?? .system }, set: { value in model.update(id) { $0.accentStyle = value } })) { ForEach(WidgetAccent.allCases) { Text($0.rawValue).tag($0) } }.labelsHidden().frame(width: 130) }
                HStack(spacing: 10) {
                    Text("Background")
                    Spacer()
                    Image(systemName: "square.on.square").font(.system(size: 10)).foregroundStyle(Palette.muted).help("More transparent")
                    Slider(value: Binding(get: { model.widgets.first(where: { $0.id == id })?.backgroundOpacity ?? 1 }, set: { value in model.update(id) { $0.backgroundOpacity = value } }), in: 0.15...1).frame(width: 130)
                    Image(systemName: "square.fill").font(.system(size: 10)).foregroundStyle(Palette.muted).help("Fully opaque")
                }
                Toggle("Lock position", isOn: Binding(get: { model.widgets.first(where: { $0.id == id })?.positionLocked ?? false }, set: { value in model.update(id) { $0.positionLocked = value } }))
                if item.isOnDesktop {
                    Button("Remove Widget", role: .destructive) { model.removeFromDesktop(id); dismiss() }
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(22).background(Palette.background).preferredColorScheme(.dark)
    }
}

struct LockScreenPreview: View {
    var theme: BoardTheme
    var body: some View { ZStack { LinearGradient(colors: [Color(hex: "252A35"), Color(hex: "10120F")], startPoint: .topLeading, endPoint: .bottomTrailing); VStack(spacing: 12) { Text(Date.now.formatted(date: .complete, time: .omitted).uppercased()).font(.system(size: 9, weight: .bold)).tracking(2).foregroundStyle(.white.opacity(0.7)); Text(Date.now, format: .dateTime.hour().minute()).font(.system(size: 64, weight: .ultraLight, design: .rounded)); HStack(spacing: 10) { Label("72°", systemImage: "sun.max.fill"); Label(Date.now.formatted(.dateTime.weekday(.wide)), systemImage: "calendar") }.font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.accent(theme)) } }.clipShape(RoundedRectangle(cornerRadius: 20)).overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.08), lineWidth: 1)) }
}
