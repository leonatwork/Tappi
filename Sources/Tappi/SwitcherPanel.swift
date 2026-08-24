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
        let screen = NSScreen.main ?? NSScreen.screens.first ?? NSScreen.screens[0]
        self.entries = entries
        layout = TileLayout.compute(count: entries.count, on: screen)

        let frame = CGRect(
            x: screen.visibleFrame.midX - layout.panelSize.width / 2,
            y: screen.visibleFrame.midY - layout.panelSize.height / 2,
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
