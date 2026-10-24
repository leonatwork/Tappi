import Foundation

enum PanelScreen: String, Codable, CaseIterable {
    case active, mouse, main
}

/// Only cached geometry enters this decision; querying AX here would stall the hotkey.
enum PanelScreenSelection {
    /// AX/Quartz uses a top-left origin on the primary (menu-bar) screen. AppKit
    /// uses bottom-left coordinates; the desktop union's top is NOT the flip axis.
    static func appKitFrame(_ frame: CGRect, primaryTop: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: primaryTop - frame.maxY,
               width: frame.width, height: frame.height)
    }

    static func choose(mode: PanelScreen, frames: [CGRect], primaryTop: CGFloat,
                       windowFrame: CGRect?, mousePosition: CGPoint, mainIndex: Int?) -> Int? {
        if mode == .active, let windowFrame {
            let window = appKitFrame(windowFrame, primaryTop: primaryTop)
            var bestIndex: Int?
            var bestArea: CGFloat = 0
            for (index, frame) in frames.enumerated() {
                let intersection = frame.intersection(window)
                let area = intersection.isNull ? 0 : intersection.width * intersection.height
                if area > bestArea {
                    bestArea = area
                    bestIndex = index
                }
            }
            if let bestIndex { return bestIndex }
        }
        // NSEvent.mouseLocation is already in AppKit coordinates, including
        // negative coordinates on monitors left of or below the primary screen.
        if mode != .main, let index = frames.firstIndex(where: { $0.contains(mousePosition) }) {
            return index
        }
        if let mainIndex, frames.indices.contains(mainIndex) { return mainIndex }
        return frames.indices.first
    }
}
