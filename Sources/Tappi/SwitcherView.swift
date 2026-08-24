import AppKit

/// Geometry for one session, computed once when the panel is presented.
///
/// Everything here is in AppKit's normal bottom-left coordinate space. A flipped
/// view would make the grid maths read more naturally, but it also mirrors every
/// image AppKit draws into it, so the rows are simply laid out top-down by hand.
struct TileLayout {
    var tiles: [CGRect] = []
    var panelSize: CGSize = .zero
    var columns: Int = 0
    var tileSize: CGSize = .zero

    static let outerPadding: CGFloat = 14
    static let gap: CGFloat = 8
    static let innerPadding: CGFloat = 8
    static let titleHeight: CGFloat = 18

    static func compute(count: Int, on screen: NSScreen) -> TileLayout {
        let settings = SettingsStore.shared.value
        let width = max(96, CGFloat(settings.tileSize))
        let height = titleHeight + innerPadding + (width * 0.60) + innerPadding * 2

        let available = screen.visibleFrame.width * 0.92 - outerPadding * 2
        let fitting = max(1, Int((available + gap) / (width + gap)))
        let columns = max(1, min(min(settings.maxColumns, fitting), count))
        let rows = Int(ceil(Double(count) / Double(columns)))

        var layout = TileLayout()
        layout.columns = columns
        layout.tileSize = CGSize(width: width, height: height)
        let panelHeight = outerPadding * 2 + CGFloat(rows) * height + CGFloat(rows - 1) * gap
        layout.panelSize = CGSize(
            width: outerPadding * 2 + CGFloat(columns) * width + CGFloat(columns - 1) * gap,
            height: panelHeight)

        layout.tiles = (0..<count).map { index in
            let column = index % columns
            let row = index / columns
            // Row 0 sits at the top, so count rows down from the panel's top edge.
            let top = panelHeight - outerPadding - CGFloat(row) * (height + gap)
            return CGRect(x: outerPadding + CGFloat(column) * (width + gap),
                          y: top - height, width: width, height: height)
        }
        return layout
    }
}

/// The regions inside a single tile. Shared by drawing and hit testing so the
/// close button is always exactly where it was painted.
struct TileGeometry {
    let title: CGRect
    let preview: CGRect
    let close: CGRect

    init(tile: CGRect) {
        let inner = TileLayout.innerPadding
        title = CGRect(x: tile.minX + inner,
                       y: tile.maxY - inner - TileLayout.titleHeight,
                       width: tile.width - inner * 2,
                       height: TileLayout.titleHeight)
        preview = CGRect(x: tile.minX + inner, y: tile.minY + inner,
                         width: tile.width - inner * 2,
                         height: title.minY - inner * 0.5 - (tile.minY + inner))
        close = CGRect(x: preview.maxX - 20, y: preview.maxY - 20, width: 16, height: 16)
    }
}

/// Draws the tiles. Deliberately a single `draw(_:)` view rather than a
/// collection view: no cell reuse machinery, no autolayout pass, no SwiftUI
/// diffing between a keypress and pixels on screen.
final class SwitcherContentView: NSView {
    var entries: [WindowEntry] = []
    var layout = TileLayout()
    var onHover: ((Int) -> Void)?
    var onClick: ((Int) -> Void)?
    var onClose: ((Int) -> Void)?

    private var trackingArea: NSTrackingArea?
    private var hoverIndex: Int?

    override var acceptsFirstResponder: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        for (index, tile) in layout.tiles.enumerated() where tile.intersects(dirtyRect) {
            guard entries.indices.contains(index) else { continue }
            drawTile(entries[index], in: tile, index: index, context: context)
        }
    }

    private func drawTile(_ entry: WindowEntry, in rect: CGRect, index: Int, context: CGContext) {
        let geometry = TileGeometry(tile: rect)
        let alpha: CGFloat = entry.isMinimized ? 0.5 : 1.0

        // Title row: small app icon, then the window title.
        var textOrigin = geometry.title.minX
        if let icon = entry.icon {
            let iconRect = CGRect(x: geometry.title.minX, y: geometry.title.minY + 1,
                                  width: 16, height: 16)
            icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1)
            textOrigin = iconRect.maxX + 5
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11.5, weight: .regular),
            .foregroundColor: NSColor.labelColor.withAlphaComponent(entry.isMinimized ? 0.55 : 0.95),
            .paragraphStyle: paragraph,
        ]
        let textRect = CGRect(x: textOrigin, y: geometry.title.minY,
                              width: geometry.title.maxX - textOrigin, height: geometry.title.height)
        (entry.displayTitle as NSString).draw(in: textRect, withAttributes: attributes)

        // Preview area: thumbnail if we have one, otherwise the app icon large.
        let previewPath = NSBezierPath(roundedRect: geometry.preview, xRadius: 6, yRadius: 6)
        NSColor.white.withAlphaComponent(0.06).setFill()
        previewPath.fill()

        if let thumbnail = entry.thumbnail ?? ThumbnailProvider.shared.cached(for: entry) {
            entry.thumbnail = thumbnail
            let fitted = aspectFit(thumbnail.size, into: geometry.preview.insetBy(dx: 3, dy: 3))
            context.saveGState()
            previewPath.addClip()
            thumbnail.draw(in: fitted, from: .zero, operation: .sourceOver, fraction: alpha)
            context.restoreGState()
        } else if let icon = entry.icon {
            let side = min(geometry.preview.width, geometry.preview.height) * 0.62
            let iconRect = CGRect(x: geometry.preview.midX - side / 2,
                                  y: geometry.preview.midY - side / 2,
                                  width: side, height: side)
            icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: alpha)
        }

        if entry.isMinimized {
            drawBadge("▾", in: geometry.preview)
        } else if !entry.isOnActiveSpace {
            drawBadge("◈", in: geometry.preview)
        }

        if hoverIndex == index {
            drawCloseButton(in: geometry.close)
        }
    }

    private func drawBadge(_ glyph: String, in rect: CGRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .bold),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        (glyph as NSString).draw(at: CGPoint(x: rect.minX + 4, y: rect.maxY - 14),
                                 withAttributes: attributes)
    }

    /// The hover "x", straight out of the Windows switcher.
    private func drawCloseButton(in rect: CGRect) {
        NSColor.black.withAlphaComponent(0.55).setFill()
        NSBezierPath(ovalIn: rect).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let glyph = "✕" as NSString
        let size = glyph.size(withAttributes: attributes)
        glyph.draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
                   withAttributes: attributes)
    }

    private func aspectFit(_ size: CGSize, into rect: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return rect }
        let scale = min(rect.width / size.width, rect.height / size.height)
        let width = size.width * scale
        let height = size.height * scale
        return CGRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height)
    }

    // MARK: - Mouse

    private func index(at point: CGPoint) -> Int? {
        layout.tiles.firstIndex { $0.contains(point) }
    }

    override func mouseMoved(with event: NSEvent) {
        guard SettingsStore.shared.value.mouseHover else { return }
        let point = convert(event.locationInWindow, from: nil)
        let index = index(at: point)
        if index != hoverIndex {
            let previous = hoverIndex
            hoverIndex = index
            if let previous, layout.tiles.indices.contains(previous) { setNeedsDisplay(layout.tiles[previous]) }
            if let index { setNeedsDisplay(layout.tiles[index]) }
        }
        if let index { onHover?(index) }
    }

    override func mouseExited(with event: NSEvent) {
        if let hoverIndex, layout.tiles.indices.contains(hoverIndex) {
            setNeedsDisplay(layout.tiles[hoverIndex])
        }
        hoverIndex = nil
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let index = index(at: point) else { return }
        if TileGeometry(tile: layout.tiles[index]).close.contains(point) {
            onClose?(index)
        } else {
            onClick?(index)
        }
    }
}
