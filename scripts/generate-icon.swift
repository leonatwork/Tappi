#!/usr/bin/env swift
// Draws the Tappi app icon: a switcher panel with three window tiles, the middle
// one selected — what you see after a single press of ⌘Tab.
//
// Usage:
//   swift scripts/generate-icon.swift <AppIcon.icns>            build.sh does this
//   swift scripts/generate-icon.swift --png <file.png> [pixels]  a single preview
//
// Drawn in code rather than shipped as a binary so it stays reviewable and
// in step with the menu bar glyph (StatusItem.swift), which shows the same idea.
import AppKit

/// Colours shared with the sibling apps' icons: a diagonal gradient, white motif.
let gradientTop = NSColor(srgbRed: 0.47, green: 0.36, blue: 0.96, alpha: 1)    // violet
let gradientBottom = NSColor(srgbRed: 0.13, green: 0.45, blue: 0.93, alpha: 1) // blue

func roundedRect(_ rect: CGRect, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

/// One rendition at an exact pixel size. Drawing straight into a bitmap of that
/// size (instead of `NSImage.lockFocus`) keeps Retina screens from doubling it.
func render(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    draw(size: CGFloat(pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func draw(size s: CGFloat) {
    // Small renditions (menu lists, Finder list view) drop the details and use
    // the whole canvas, so the three tiles stay distinguishable at 16 px.
    let small = s <= 32

    // Rounded-square body, macOS style.
    let inset = small ? s * 0.03 : s * 0.06
    let body = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let bodyPath = roundedRect(body, body.width * 0.225)
    NSGradient(starting: gradientTop, ending: gradientBottom)!.draw(in: bodyPath, angle: -60)

    if !small {
        // Soft top light and a hairline rim, as on the sibling icons.
        NSGraphicsContext.saveGraphicsState()
        bodyPath.addClip()
        let glow = NSGradient(colors: [NSColor.white.withAlphaComponent(0.16), NSColor.white.withAlphaComponent(0)])!
        glow.draw(in: CGRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: -90)
        NSGraphicsContext.restoreGraphicsState()
        NSColor.white.withAlphaComponent(0.22).setStroke()
        let rim = roundedRect(body.insetBy(dx: s * 0.006, dy: s * 0.006), body.width * 0.22)
        rim.lineWidth = s * 0.012
        rim.stroke()
    }

    // Three tiles in a row, the middle one selected.
    let tileWidth = s * 0.19
    let tileHeight = tileWidth * 1.05
    let gap = s * 0.055
    let rowWidth = tileWidth * 3 + gap * 2
    let rowX = (s - rowWidth) / 2
    let rowY = (s - tileHeight) / 2 - s * 0.01
    let tileRadius = tileWidth * 0.14
    var tiles = (0..<3).map { index in
        CGRect(x: rowX + CGFloat(index) * (tileWidth + gap), y: rowY, width: tileWidth, height: tileHeight)
    }
    if small {
        // At 16 and 32 px the selected tile is drawn larger than its neighbours,
        // which survives the downscale far better than a selection ring would.
        // Whole pixels keep the edges crisp.
        func px(_ fraction: CGFloat) -> CGFloat { max(1, (s * fraction).rounded()) }
        let side = CGSize(width: px(0.15), height: px(0.34))
        let middle = CGSize(width: px(0.40), height: px(0.50))
        let gap = px(0.06)
        let x = ((s - (side.width * 2 + middle.width + gap * 2)) / 2).rounded()
        tiles = [
            CGRect(x: x, y: ((s - side.height) / 2).rounded(), width: side.width, height: side.height),
            CGRect(x: x + side.width + gap, y: ((s - middle.height) / 2).rounded(),
                   width: middle.width, height: middle.height),
            CGRect(x: x + side.width + gap * 2 + middle.width, y: ((s - side.height) / 2).rounded(),
                   width: side.width, height: side.height),
        ]
    }

    if !small {
        // The switcher panel behind the tiles.
        let panel = CGRect(x: rowX - s * 0.06, y: rowY - s * 0.06,
                           width: rowWidth + s * 0.12, height: tileHeight + s * 0.12)
        NSColor.black.withAlphaComponent(0.22).setFill()
        roundedRect(panel, s * 0.07).fill()
    }

    for (index, tile) in tiles.enumerated() {
        let selected = index == 1
        let path = roundedRect(tile, small ? s * 0.04 : tileRadius)

        if selected && !small {
            // Selection ring, like the highlight around the chosen tile in the switcher.
            let ring = roundedRect(tile.insetBy(dx: -s * 0.022, dy: -s * 0.022), tileRadius + s * 0.022)
            ring.lineWidth = s * 0.016
            NSColor.white.withAlphaComponent(0.95).setStroke()
            ring.stroke()

            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
            shadow.shadowBlurRadius = s * 0.03
            shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
            shadow.set()
            NSColor.white.setFill()
            path.fill()
            NSGraphicsContext.restoreGraphicsState()
        } else {
            NSColor.white.withAlphaComponent(selected ? 1.0 : (small ? 0.55 : 0.42)).setFill()
            path.fill()
        }

        guard !small else { continue }
        // Title bar: tints the top of each tile so it reads as a window.
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        let bar = CGRect(x: tile.minX, y: tile.maxY - tileHeight * 0.22, width: tile.width, height: tileHeight * 0.22)
        (selected ? gradientBottom.withAlphaComponent(0.85) : NSColor.white.withAlphaComponent(0.35)).setFill()
        NSBezierPath(rect: bar).fill()
        NSGraphicsContext.restoreGraphicsState()

        // A few content lines on the selected window only, to keep the others quiet.
        if selected {
            gradientTop.withAlphaComponent(0.35).setFill()
            let lineHeight = tileHeight * 0.07
            for (row, fraction) in [(0, 0.72), (1, 0.52), (2, 0.62)] {
                let line = CGRect(x: tile.minX + tileWidth * 0.14,
                                  y: tile.maxY - tileHeight * 0.38 - CGFloat(row) * lineHeight * 2.1,
                                  width: tileWidth * CGFloat(fraction), height: lineHeight)
                roundedRect(line, lineHeight / 2).fill()
            }
        }
    }
}

func writePNG(_ rep: NSBitmapImageRep, to url: URL) throws {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try data.write(to: url)
}

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.first == "--png", arguments.count >= 2 {
    let pixels = arguments.count >= 3 ? Int(arguments[2]) ?? 512 : 512
    try writePNG(render(pixels: pixels), to: URL(fileURLWithPath: arguments[1]))
    exit(0)
}
guard let output = arguments.first else {
    FileHandle.standardError.write("usage: generate-icon.swift <AppIcon.icns> | --png <file.png> [pixels]\n".data(using: .utf8)!)
    exit(2)
}

let iconset = FileManager.default.temporaryDirectory
    .appendingPathComponent("Tappi-\(ProcessInfo.processInfo.processIdentifier).iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
    try writePNG(render(pixels: points * scale), to: iconset.appendingPathComponent(name))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
exit(iconutil.terminationStatus)
