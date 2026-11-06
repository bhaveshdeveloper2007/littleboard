import SwiftUI

@main
struct LittleboardApp: App {
    @StateObject private var model = BoardModel()
    init() {
        if CommandLine.arguments.contains("--selftest") {
            Task { @MainActor in
                await SelfTest.perform()
                exit(SelfTest.failures == 0 ? 0 : 1)
            }
        }
    }
    var body: some Scene {
        WindowGroup("Littleboard") { LibraryView().environmentObject(model).frame(minWidth: 930, minHeight: 660) }
            .windowStyle(.hiddenTitleBar)
            .defaultSize(width: 1120, height: 760)
            .commands { CommandGroup(replacing: .newItem) { } }
    }
}

enum Palette {
    static let background = Color(hex: "10120F")
    static let panel = Color(hex: "191C18")
    static let raised = Color(hex: "232720")
    static let muted = Color(hex: "8D9488")
    static func accent(_ theme: BoardTheme) -> Color { Color(hex: theme.accent) }
}

extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var v: UInt64 = 0; Scanner(string: s).scanHexInt64(&v)
        self.init(.sRGB, red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255, blue: Double(v & 0xff) / 255, opacity: 1)
    }
}

struct IconButton: View {
    let symbol: String
    var help: String = ""
    var action: () -> Void
    var body: some View { Button(action: action) { Image(systemName: symbol).frame(width: 34, height: 34) }.buttonStyle(.plain).foregroundStyle(Palette.muted).background(Palette.raised, in: RoundedRectangle(cornerRadius: 10)).help(help) }
}

/// macOS plain buttons hit-test only their rendered content (text), so padded
/// pills ignore clicks on their empty area. This style makes the whole label
/// frame hittable.
struct FullAreaButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> AnyView {
        AnyView(configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.65 : 1))
    }
}

struct Pill: View {
    let title: String
    var body: some View { Text(title.uppercased()).font(.system(size: 9, weight: .bold, design: .rounded)).tracking(1).foregroundStyle(Palette.muted).padding(.horizontal, 8).padding(.vertical, 5).background(Palette.raised, in: Capsule()) }
}
