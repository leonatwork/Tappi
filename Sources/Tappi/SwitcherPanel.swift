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
    private var entries: [WindowEntry] = []
    private var visibleFrame: CGRect = .zero
    private var backingScale: CGFloat = 1
    private var tileWidth: Double = 0
    private var maxColumns: Int = 0

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

    /// Fix the screen, layout settings and initial capacity once per session,
    /// including delayed sessions. The controller discards entries without tiles.
    func prepare(count: Int, activeWindowFrame: CGRect?) -> Int {
        let screens = NSScreen.screens
        let mainIndex = NSScreen.main.flatMap { main in screens.firstIndex { $0 === main } }
        let settings = SettingsStore.shared.value
        guard let index = PanelScreenSelection.choose(
            mode: settings.panelScreen ?? .active, frames: screens.map { $0.frame },
            primaryTop: screens.first?.frame.maxY ?? 0, windowFrame: activeWindowFrame,
            mousePosition: NSEvent.mouseLocation, mainIndex: mainIndex)
        else {
            layout = TileLayout()
            return 0
        }
        let screen = screens[index]
        visibleFrame = screen.visibleFrame
        backingScale = screen.backingScaleFactor
        tileWidth = settings.tileSize
        maxColumns = settings.maxColumns
        layout = TileLayout.compute(count: count, tileWidth: tileWidth,
                                    maxColumns: maxColumns, visibleFrame: visibleFrame)
        return layout.tiles.count
    }

    func present(entries: [WindowEntry], selected: Int) {
        guard !entries.isEmpty, entries.count <= layout.tiles.count else { return }
        self.entries = entries
        // Closing or quitting reflows the surviving entries on the same screen
        // with the session's settings, without bringing back truncated windows.
        layout.reduceCount(to: entries.count, tileWidth: tileWidth,
                           maxColumns: maxColumns, visibleFrame: visibleFrame)

        let frame = CGRect(
            x: visibleFrame.midX - layout.panelSize.width / 2,
            y: visibleFrame.midY - layout.panelSize.height / 2,
            width: layout.panelSize.width, height: layout.panelSize.height)
        window.setFrame(frame, display: false)

        let bounds = CGRect(origin: .zero, size: layout.panelSize)
        content.frame = bounds
        content.entries = entries
        content.layout = layout
        content.needsDisplay = true

        applySelectionColors()
        select(selected, animated: false)

        window.orderFrontRegardless()
        isPresented = true

        // Previews are requested a run loop turn later, so nothing about capturing
        // can share a turn with putting the panel on screen.
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
            ThumbnailProvider.shared.request(for: entry, size: previewSize, scale: backingScale)
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
