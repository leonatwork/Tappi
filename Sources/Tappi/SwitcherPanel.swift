import AppKit

/// The overlay itself.
///
/// It is created once at launch and merely ordered in and out afterwards, so the
/// cost of showing it is a window-server order operation rather than allocating
/// and compositing a fresh window on the critical path.
final class SwitcherPanel {
    var onSelect: ((Int) -> Void)?
    var onActivate: ((Int) -> Void)?
    var onClose: ((Int) -> Void)?

    private(set) var isPresented = false

    private let window: NSPanel
    private let background: NSVisualEffectView
    private let selectionView: NSView
    private let content: SwitcherContentView
    private var layout = TileLayout()
    private(set) var entries: [WindowEntry] = []

    func containsScreenPoint(_ point: CGPoint) -> Bool {
        isPresented && window.frame.contains(point)
    }

    init() {
        window = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 10, height: 10),
                         styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered, defer: false)
        window.level = .popUpMenu
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.hidesOnDeactivate = false
        window.isMovable = false
        window.acceptsMouseMovedEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        window.animationBehavior = .none

        background = NSVisualEffectView()
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.cornerCurve = .continuous
        background.layer?.masksToBounds = true
        background.layer?.borderWidth = 1
        background.layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor

        selectionView = NSView()
        selectionView.wantsLayer = true
        selectionView.layer?.cornerRadius = 8
        selectionView.layer?.cornerCurve = .continuous
        selectionView.layer?.borderWidth = 1.5
        selectionView.isHidden = true

        content = SwitcherContentView()
        content.wantsLayer = false

        window.contentView = background
        background.addSubview(selectionView)
        background.addSubview(content)

        content.onHover = { [weak self] index in self?.onSelect?(index) }
        content.onClick = { [weak self] index in self?.onActivate?(index) }
        content.onClose = { [weak self] index in self?.onClose?(index) }

        NotificationCenter.default.addObserver(
            self, selector: #selector(thumbnailArrived(_:)),
            name: ThumbnailProvider.didUpdate, object: nil)
    }

    /// Force the window server to allocate the surface before the user ever needs
    /// it, so the very first Alt-Tab is as fast as the hundredth.
    func warmUp() {
        window.setFrame(CGRect(x: -10_000, y: -10_000, width: 400, height: 200), display: false)
        window.orderFront(nil)
        window.displayIfNeeded()
        window.orderOut(nil)
    }

    // MARK: - Presenting

    func present(entries: [WindowEntry], selected: Int) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) })
            ?? NSScreen.main ?? NSScreen.screens[0]
        let layout = TileLayout.compute(count: entries.count, on: screen)
        let frame = CGRect(x: screen.visibleFrame.midX - layout.panelSize.width / 2,
                           y: screen.visibleFrame.midY - layout.panelSize.height / 2,
                           width: layout.panelSize.width, height: layout.panelSize.height)
        configure(entries: entries, layout: layout, frame: frame, selected: selected)
    }

    func presentDock(entries: [WindowEntry], on screen: NSScreen, anchoredTo dockItem: CGRect) {
        let preferred = CGFloat(SettingsStore.shared.value.dockPreviewSize ?? 190)
        let available = CGSize(width: screen.visibleFrame.width * 0.90,
                               height: min(screen.visibleFrame.height * 0.45, 420))
        let layout = TileLayout.compute(count: entries.count, availableSize: available,
                                        preferredWidth: preferred)
        let visible = screen.visibleFrame
        let gap: CGFloat = 8
        var origin = CGPoint(x: dockItem.midX - layout.panelSize.width / 2,
                             y: dockItem.maxY + gap)
        let distances = [dockItem.minY - screen.frame.minY,
                         screen.frame.maxY - dockItem.maxY,
                         dockItem.minX - screen.frame.minX,
                         screen.frame.maxX - dockItem.maxX]
        switch distances.firstIndex(of: distances.min()!) {
        case 1:
            origin.y = dockItem.minY - layout.panelSize.height - gap
        case 2:
            origin.x = dockItem.maxX + gap
            origin.y = dockItem.midY - layout.panelSize.height / 2
        case 3:
            origin.x = dockItem.minX - layout.panelSize.width - gap
            origin.y = dockItem.midY - layout.panelSize.height / 2
        default:
            break
        }
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - layout.panelSize.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - layout.panelSize.height - 8)
        let frame = CGRect(origin: origin, size: layout.panelSize)
        configure(entries: entries, layout: layout, frame: frame, selected: nil)
    }

    private func configure(entries: [WindowEntry], layout: TileLayout, frame: CGRect,
                           selected: Int?) {
        self.entries = entries
        self.layout = layout
        window.setFrame(frame, display: false)
        content.frame = CGRect(origin: .zero, size: layout.panelSize)
        content.entries = entries
        content.layout = layout
        content.needsDisplay = true
        selectionView.isHidden = selected == nil
        applySelectionColors()
        if let selected { select(selected, animated: false) }
        window.orderFrontRegardless()
        isPresented = true
        DispatchQueue.main.async {
            ThumbnailProvider.shared.prepare { [weak self] in self?.requestThumbnails() }
        }
    }

    /// Ask for every tile's preview at once; each one repaints its own tile when
    /// it lands, and stays cached for the next session.
    private func requestThumbnails() {
        guard isPresented else { return }
        let previewSize = TileGeometry(tile: CGRect(origin: .zero, size: layout.tileSize)).preview.size
        for entry in entries {
            if let cached = ThumbnailProvider.shared.cached(for: entry) {
                if entry.thumbnail !== cached { entry.thumbnail = cached }
            }
            ThumbnailProvider.shared.request(for: entry, size: previewSize)
        }
        content.needsDisplay = true
    }

    func dismiss() {
        guard isPresented else { return }
        window.orderOut(nil)
        isPresented = false
        entries = []
        content.entries = []
    }

    // MARK: - Selection

    func select(_ index: Int, animated: Bool = true) {
        guard layout.tiles.indices.contains(index) else { return }
        let frame = layout.tiles[index]
        selectionView.isHidden = false
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.09
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                context.allowsImplicitAnimation = true
                selectionView.animator().frame = frame
            }
        } else {
            selectionView.frame = frame
        }
    }

    private func applySelectionColors() {
        let accent = NSColor.controlAccentColor
        selectionView.layer?.backgroundColor = accent.withAlphaComponent(0.30).cgColor
        selectionView.layer?.borderColor = accent.withAlphaComponent(0.85).cgColor
    }

    @objc private func thumbnailArrived(_ note: Notification) {
        guard isPresented, let entry = note.object as? WindowEntry,
              let index = entries.firstIndex(where: { $0 === entry }),
              layout.tiles.indices.contains(index)
        else { return }
        // Repaint only the tile that changed.
        content.setNeedsDisplay(layout.tiles[index])
    }
}
