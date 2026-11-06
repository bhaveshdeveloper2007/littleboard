import AppKit
import SwiftUI

@MainActor
final class DesktopWidgetController: NSObject, NSWindowDelegate {
    private let model: BoardModel
    private let id: UUID
    private var panel: NSPanel?
    private var renderedSignature: String?
    private var isDragging = false
    private var lastDragTranslation = CGSize.zero
    init(model: BoardModel, id: UUID) { self.model = model; self.id = id; super.init(); show() }

    func refresh() {
        guard let item = model.widgets.first(where: { $0.id == id }) else { close(); return }
        guard let panel else { show(); return }
        let size = item.size.dimensions
        // Recreate the SwiftUI tree only when the widget's shell changes. Data edits
        // flow through the observed model, so rebuilding here would reset view state
        // (feeds, timers, embedded web views) on every unrelated change.
        let signature = "\(item.kind.rawValue)-\(item.size.rawValue)-\(item.glassStyle.rawValue)"
        if signature != renderedSignature {
            renderedSignature = signature
            panel.contentView = makeContentView(item: item, size: size)
        }
        panel.setFrame(NSRect(origin: NSPoint(x: item.x, y: item.y), size: size), display: true)
        panel.isMovableByWindowBackground = false
        if panel.isVisible { return }
        panel.orderFrontRegardless()
    }
    func close() { panel?.orderOut(nil); panel = nil }
    func bringToFront() {
        guard let panel else { return }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }
    private func show() {
        guard let item = model.widgets.first(where: { $0.id == id }) else { return }
        let p = NSPanel(contentRect: NSRect(origin: NSPoint(x: item.x, y: item.y), size: item.size.dimensions), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isReleasedWhenClosed = false
        // Desktop widgets must sit above Finder's desktop window group (desktopIconWindow = 20).
        // Floating panels (level 3) are still behind that group, making widgets appear to vanish.
        p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 21)
        p.backgroundColor = .clear
        p.isOpaque = false
        // Littleboard's cards are designed dark. Without this, glass widgets follow
        // the system appearance and render light/washed out in light mode.
        p.appearance = NSAppearance(named: .darkAqua)
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.isMovableByWindowBackground = false
        p.delegate = self
        p.contentView = makeContentView(item: item, size: item.size.dimensions)
        renderedSignature = "\(item.kind.rawValue)-\(item.size.rawValue)-\(item.glassStyle.rawValue)"
        panel = p
        p.setFrameOrigin(NSPoint(x: item.x, y: item.y))
        p.makeKeyAndOrderFront(nil)
        p.orderFrontRegardless()
        NSLog("Littleboard widget %@ opened: visible=%@ frame=%@ level=%ld", item.kind.rawValue, p.isVisible.description, NSStringFromRect(p.frame), p.level.rawValue)
    }
    func windowDidMove(_ notification: Notification) {
        // setFrameOrigin during a drag also lands here; committing then would write
        // the model (and re-render every panel) on each move event.
        guard !isDragging, let frame = panel?.frame else { return }
        model.savePanelPosition(id, x: frame.origin.x, y: frame.origin.y)
    }
    private func makeContentView(item: WidgetInstance, size: CGSize) -> NSView {
        MovableWidgetHostingView(rootView: WidgetCard(model: model, id: id, desktop: true, onMove: { [weak self] translation in
            guard let self, let panel = self.panel else { return }
            guard self.model.widgets.first(where: { $0.id == item.id })?.positionLocked == false else { return }
            // Drag hot path: move the panel only. No model writes, no saves, no view
            // state — those ran per event and made dragging stutter.
            let delta = CGSize(width: translation.width - self.lastDragTranslation.width, height: translation.height - self.lastDragTranslation.height)
            self.lastDragTranslation = translation
            guard delta.width != 0 || delta.height != 0 else { return }
            self.isDragging = true
            panel.setFrameOrigin(NSPoint(x: panel.frame.origin.x + delta.width, y: panel.frame.origin.y - delta.height))
        }, onDragEnd: { [weak self] in
            guard let self else { return }
            self.lastDragTranslation = .zero
            guard self.isDragging else { return }
            self.isDragging = false
            guard let panel = self.panel else { return }
            self.model.savePanelPosition(item.id, x: panel.frame.origin.x, y: panel.frame.origin.y)
        }).frame(width: size.width, height: size.height)) { [weak model] in
            model?.widgets.first(where: { $0.id == item.id })?.positionLocked ?? true
        }
    }
}

@MainActor private final class MovableWidgetHostingView<Content: View>: NSHostingView<Content> {
    private let isLocked: () -> Bool
    init(rootView: Content, isLocked: @escaping () -> Bool) {
        self.isLocked = isLocked
        super.init(rootView: rootView)
    }
    required init(rootView: Content) {
        self.isLocked = { true }
        super.init(rootView: rootView)
    }
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var mouseDownCanMoveWindow: Bool { !isLocked() }
}
