// Screenshot harness: draws Tappi's switcher with invented demo windows, offscreen.
//
// Compiled by render.sh together with the app's sources (minus the app's own
// main.swift), so the tiles come from the real `TileLayout` and
// `SwitcherContentView`. Nothing here captures the screen, enumerates real
// windows or reads the user's settings: render.sh points `Settings.directory`
// at a throwaway folder, and this file refuses to run if it does not.
//
// Usage (render.sh does this):
//   TappiScreenshots.app/Contents/MacOS/TappiScreenshots --out <dir> --lang <en|de> -AppleLanguages "(de)"
import AppKit
import ApplicationServices

// MARK: - Arguments and guards

func fail(_ message: String) -> Never {
    FileHandle.standardError.write("screenshots: \(message)\n".data(using: .utf8)!)
    exit(1)
}

func argument(_ flag: String) -> String? {
    let arguments = CommandLine.arguments
    guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
    return arguments[index + 1]
}

guard let outPath = argument("--out") else { fail("missing --out <dir>") }
let language = argument("--lang") ?? "en"
let outDir = URL(fileURLWithPath: outPath, isDirectory: true)

guard let sandbox = ProcessInfo.processInfo.environment["TAPPI_SCREENSHOT_SUPPORT"], !sandbox.isEmpty,
      Settings.directory.standardizedFileURL.path.hasPrefix(URL(fileURLWithPath: sandbox).standardizedFileURL.path)
else { fail("Settings.directory is not redirected into TAPPI_SCREENSHOT_SUPPORT; run via render.sh") }

// The README shows a 3 × 2 grid: six tiles in one row would make a 2× image far
// wider than GitHub displays. `maxColumns` is a real setting, so this is a
// layout the app produces as well. Written into the sandbox before
// SettingsStore first loads; never via `mutate`, which would touch ⌘Tab.
var demoSettings = Settings()
demoSettings.maxColumns = 3
demoSettings.save()
guard SettingsStore.shared.value.maxColumns == 3 else { fail("demo settings were not picked up") }

// Localization runs through the app's own lookup, against the .lproj folders
// render.sh copied into the temporary bundle.
let localizer = Localizer(language: .system)
guard localizer.language.code == language else {
    fail("interface language resolved to \(localizer.language.code ?? "?"), expected \(language); pass -AppleLanguages")
}
print("[\(language)] status line: \(tr("status.active.other", "⌘", 6, ""))")

let aqua = NSAppearance(named: .aqua)!

// MARK: - Placeholder previews

enum Preview { case mail, pdf, notes, text, web }

/// A small, schematic window: title bar with traffic lights and a content
/// sketch per app. Drawn as vectors, so it stays sharp at any scale.
func thumbnail(_ kind: Preview) -> NSImage {
    let size = NSSize(width: 160, height: 100)
    return NSImage(size: size, flipped: true) { _ in
        let window = CGRect(origin: .zero, size: size)
        let windowPath = NSBezierPath(roundedRect: window, xRadius: 6, yRadius: 6)
        NSGraphicsContext.saveGraphicsState()
        windowPath.addClip()
        NSColor.white.setFill()
        window.fill()

        func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: NSColor, radius: CGFloat = 1.2) {
            color.setFill()
            NSBezierPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), xRadius: radius, yRadius: radius).fill()
        }
        func gray(_ white: CGFloat) -> NSColor { NSColor(white: white, alpha: 1) }
        let ink = gray(0.78), inkDark = gray(0.45), hairline = gray(0.88)
        let blue = NSColor(srgbRed: 0.20, green: 0.48, blue: 0.96, alpha: 1)

        // Title bar.
        let bar: CGFloat = kind == .web ? 16 : 12
        gray(kind == .pdf ? 0.93 : 0.96).setFill()
        CGRect(x: 0, y: 0, width: size.width, height: bar).fill()
        hairline.setFill()
        CGRect(x: 0, y: bar - 0.5, width: size.width, height: 0.5).fill()
        for (index, color) in [NSColor(srgbRed: 1.00, green: 0.37, blue: 0.34, alpha: 1),
                               NSColor(srgbRed: 1.00, green: 0.74, blue: 0.18, alpha: 1),
                               NSColor(srgbRed: 0.16, green: 0.79, blue: 0.25, alpha: 1)].enumerated() {
            color.setFill()
            NSBezierPath(ovalIn: CGRect(x: 5 + CGFloat(index) * 6.5, y: bar / 2 - 2.2, width: 4.4, height: 4.4)).fill()
        }

        switch kind {
        case .mail:
            box(0, bar, 34, size.height - bar, gray(0.95), radius: 0)
            for row in 0..<5 {
                box(5, bar + 7 + CGFloat(row) * 8, row == 0 ? 22 : 16 + CGFloat(row % 2) * 6, 3,
                    row == 0 ? blue.withAlphaComponent(0.8) : ink)
            }
            hairline.setFill()
            CGRect(x: 86, y: bar, width: 0.5, height: size.height - bar).fill()
            for row in 0..<6 {
                let y = bar + CGFloat(row) * 14.5
                if row == 1 { box(34, y, 52, 14.5, blue.withAlphaComponent(0.16), radius: 0) }
                if row < 3 {
                    blue.setFill()
                    NSBezierPath(ovalIn: CGRect(x: 36.5, y: y + 3.2, width: 2.6, height: 2.6)).fill()
                }
                box(41, y + 3, 26, 2.6, inkDark)
                box(41, y + 8, 40, 2.2, ink)
                hairline.setFill()
                CGRect(x: 40, y: y + 14.2, width: 46, height: 0.4).fill()
            }
            box(93, bar + 8, 40, 4, inkDark)
            box(93, bar + 15, 28, 2.6, ink)
            for line in 0..<7 {
                box(93, bar + 26 + CGFloat(line) * 7, line == 6 ? 34 : 58 - CGFloat(line % 3) * 5, 2.4, ink)
            }

        case .pdf:
            box(0, bar, size.width, size.height - bar, gray(0.86), radius: 0)
            let page = CGRect(x: 48, y: bar + 6, width: 64, height: 90)
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
            shadow.shadowBlurRadius = 2
            shadow.set()
            NSColor.white.setFill()
            page.fill()
            NSGraphicsContext.restoreGraphicsState()
            box(page.minX + 6, page.minY + 6, 30, 3.6, inkDark)
            box(page.minX + 6, page.minY + 12, 44, 2, ink)
            let colors = [NSColor(srgbRed: 0.27, green: 0.55, blue: 0.96, alpha: 1),
                          NSColor(srgbRed: 0.42, green: 0.36, blue: 0.93, alpha: 1),
                          NSColor(srgbRed: 0.20, green: 0.74, blue: 0.62, alpha: 1),
                          NSColor(srgbRed: 0.98, green: 0.62, blue: 0.22, alpha: 1)]
            let heights: [CGFloat] = [14, 20, 17, 27]
            let baseline = page.minY + 48
            for (index, height) in heights.enumerated() {
                box(page.minX + 9 + CGFloat(index) * 12, baseline - height, 8, height, colors[index], radius: 0.8)
            }
            hairline.setFill()
            CGRect(x: page.minX + 6, y: baseline + 0.5, width: page.width - 12, height: 0.5).fill()
            for row in 0..<5 {
                let y = baseline + 6 + CGFloat(row) * 6.5
                box(page.minX + 6, y, 18, 2, row == 0 ? inkDark : ink)
                box(page.minX + 30, y, 10, 2, row == 0 ? inkDark : ink)
                box(page.minX + 46, y, 12, 2, row == 0 ? inkDark : ink)
            }

        case .notes:
            box(0, bar, 46, size.height - bar, NSColor(srgbRed: 0.97, green: 0.96, blue: 0.93, alpha: 1), radius: 0)
            box(3, bar + 5, 40, 12, NSColor(srgbRed: 0.99, green: 0.84, blue: 0.29, alpha: 0.85), radius: 2)
            for row in 0..<5 {
                let y = bar + 7 + CGFloat(row) * 15
                box(6, y, 26 - CGFloat(row % 2) * 6, 2.8, inkDark)
                box(6, y + 5, 32, 2.2, ink)
            }
            box(56, bar + 9, 54, 5, gray(0.25))
            box(56, bar + 19, 88, 2.4, ink)
            box(56, bar + 25, 72, 2.4, ink)
            for row in 0..<4 {
                let y = bar + 36 + CGFloat(row) * 9
                let done = row < 2
                let circle = NSBezierPath(ovalIn: CGRect(x: 56, y: y - 1, width: 5, height: 5))
                if done {
                    NSColor(srgbRed: 0.96, green: 0.70, blue: 0.10, alpha: 1).setFill()
                    circle.fill()
                } else {
                    gray(0.70).setStroke()
                    circle.lineWidth = 0.7
                    circle.stroke()
                }
                box(65, y, 40 + CGFloat((row * 13) % 30), 2.6, done ? ink : inkDark)
            }

        case .text:
            box(0, bar, size.width, 8, gray(0.97), radius: 0)
            for tick in stride(from: CGFloat(10), to: size.width, by: 8) {
                gray(0.75).setFill()
                CGRect(x: tick, y: bar + 5, width: 0.5, height: 3).fill()
            }
            hairline.setFill()
            CGRect(x: 0, y: bar + 8, width: size.width, height: 0.5).fill()
            let left: CGFloat = 12
            box(left, bar + 15, 38, 5, gray(0.22))
            for line in 0..<3 { box(left, bar + 26 + CGFloat(line) * 6, line == 2 ? 70 : 132, 2.4, ink) }
            box(left, bar + 47, 30, 3.6, gray(0.30))
            box(left, bar + 55, 136, 20, gray(0.95), radius: 2)
            let code = [NSColor(srgbRed: 0.70, green: 0.25, blue: 0.62, alpha: 0.8),
                        NSColor(srgbRed: 0.18, green: 0.45, blue: 0.85, alpha: 0.8),
                        NSColor(srgbRed: 0.80, green: 0.36, blue: 0.20, alpha: 0.8)]
            for line in 0..<3 {
                box(left + 4, bar + 59 + CGFloat(line) * 5.5, 14, 2.2, code[line])
                box(left + 21, bar + 59 + CGFloat(line) * 5.5, 30 + CGFloat(line) * 14, 2.2, ink)
            }

        case .web:
            box(44, 4, 72, 8, gray(0.88), radius: 4)
            box(66, 7, 28, 2, gray(0.62))
            let hero = CGRect(x: 0, y: bar, width: size.width, height: 42)
            NSGradient(starting: NSColor(srgbRed: 0.33, green: 0.62, blue: 0.98, alpha: 1),
                       ending: NSColor(srgbRed: 0.62, green: 0.82, blue: 1.00, alpha: 1))!
                .draw(in: hero, angle: 90)
            NSColor(srgbRed: 1.00, green: 0.82, blue: 0.30, alpha: 1).setFill()
            NSBezierPath(ovalIn: CGRect(x: 118, y: bar + 8, width: 18, height: 18)).fill()
            NSColor.white.withAlphaComponent(0.92).setFill()
            NSBezierPath(roundedRect: CGRect(x: 104, y: bar + 20, width: 30, height: 10), xRadius: 5, yRadius: 5).fill()
            NSBezierPath(ovalIn: CGRect(x: 110, y: bar + 15, width: 13, height: 12)).fill()
            box(12, bar + 12, 50, 5, NSColor.white)
            box(12, bar + 22, 34, 3, NSColor.white.withAlphaComponent(0.8))
            for card in 0..<4 {
                let x = 10 + CGFloat(card) * 36
                box(x, bar + 50, 32, 30, gray(0.96), radius: 3)
                box(x + 4, bar + 54, 14, 2.4, inkDark)
                NSColor(srgbRed: 0.98, green: 0.72, blue: 0.20, alpha: card == 2 ? 0.45 : 0.9).setFill()
                NSBezierPath(ovalIn: CGRect(x: x + 10, y: bar + 60, width: 11, height: 11)).fill()
                box(x + 8, bar + 74, 16, 2.4, ink)
            }
        }
        NSGraphicsContext.restoreGraphicsState()

        hairline.setStroke()
        let border = NSBezierPath(roundedRect: window.insetBy(dx: 0.25, dy: 0.25), xRadius: 6, yRadius: 6)
        border.lineWidth = 0.5
        border.stroke()
        return true
    }
}

// MARK: - Demo windows

struct Demo {
    let app: String
    let title: [String: String]   // empty title: the tile shows the app name instead
    let preview: Preview?
    var minimized = false
}

/// Most recently used first, as the switcher lists them. Apps that ship with
/// every Mac, so the icons are the same wherever this runs.
let demos: [Demo] = [
    Demo(app: "/System/Applications/Mail.app",
         title: ["en": "Inbox", "de": "Posteingang"], preview: .mail),
    Demo(app: "/System/Applications/Preview.app",
         title: ["en": "Quarterly Report.pdf", "de": "Quartalsbericht.pdf"], preview: .pdf),
    Demo(app: "/System/Applications/Notes.app",
         title: ["en": "Trip to Lisbon", "de": "Reise nach Lissabon"], preview: .notes),
    Demo(app: "/System/Applications/TextEdit.app",
         title: ["en": "README.md", "de": "README.md"], preview: .text),
    Demo(app: "/Applications/Safari.app",
         title: ["en": "Weekend Weather Forecast", "de": "Wettervorhersage fürs Wochenende"], preview: .web),
    Demo(app: "/System/Applications/Calendar.app",
         title: [:], preview: nil, minimized: true),
]

/// A dummy accessibility handle for our own process. The entries are never
/// focused or queried, `WindowEntry` just needs something to hold.
let placeholderElement = AXUIElementCreateApplication(getpid())

let entries: [WindowEntry] = demos.map { demo in
    // Safari lives in a cryptex; /Applications holds a symlink whose icon would
    // carry an alias arrow.
    let path = URL(fileURLWithPath: demo.app).resolvingSymlinksInPath().path
    guard FileManager.default.fileExists(atPath: path) else { fail("missing \(demo.app)") }
    var name = FileManager.default.displayName(atPath: path)
    if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
    let entry = WindowEntry(axWindow: placeholderElement, pid: getpid(),
                            title: demo.title[language] ?? demo.title["en"] ?? "",
                            appName: name, icon: NSWorkspace.shared.icon(forFile: path),
                            isMinimized: demo.minimized, isHidden: false, isOnActiveSpace: true,
                            frame: nil, cgWindowID: nil)
    // Minimized windows are never captured by the app, so they keep the icon.
    if let preview = demo.preview, !demo.minimized { entry.thumbnail = thumbnail(preview) }
    return entry
}

// After one press of the shortcut the second entry is selected.
let selected = 1

// MARK: - Compositing

guard let screen = NSScreen.main ?? NSScreen.screens.first else { fail("no screen to compute the layout for") }
let layout = TileLayout.compute(count: entries.count, on: screen)

let content = SwitcherContentView(frame: CGRect(origin: .zero, size: layout.panelSize))
content.appearance = aqua
content.entries = entries
content.layout = layout

let padding: CGFloat = 56
let canvas = CGSize(width: (layout.panelSize.width + padding * 2).rounded(.up),
                    height: (layout.panelSize.height + padding * 2).rounded(.up))
let scale: CGFloat = 2

func render() -> CGImage {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let context = CGContext(data: nil, width: Int(canvas.width * scale), height: Int(canvas.height * scale),
                                  bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { fail("could not create bitmap context") }
    context.scaleBy(x: scale, y: scale)
    context.interpolationQuality = .high

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    aqua.performAsCurrentDrawingAppearance {
        // Backdrop: a soft neutral card with transparent corners, so it sits well
        // on GitHub's light and dark themes alike. Two faint blobs in the icon's
        // violet and blue stand in for a desktop behind the translucent panel.
        let card = NSBezierPath(roundedRect: CGRect(origin: .zero, size: canvas), xRadius: 18, yRadius: 18)
        card.addClip()
        NSGradient(starting: NSColor(srgbRed: 0.945, green: 0.950, blue: 0.965, alpha: 1),
                   ending: NSColor(srgbRed: 0.880, green: 0.895, blue: 0.925, alpha: 1))!
            .draw(in: CGRect(origin: .zero, size: canvas), angle: -60)
        for (center, color) in [(CGPoint(x: canvas.width * 0.18, y: canvas.height * 0.80),
                                 NSColor(srgbRed: 0.62, green: 0.55, blue: 0.98, alpha: 0.20)),
                                (CGPoint(x: canvas.width * 0.85, y: canvas.height * 0.18),
                                 NSColor(srgbRed: 0.35, green: 0.62, blue: 0.98, alpha: 0.18))] {
            NSGradient(starting: color, ending: color.withAlphaComponent(0))!
                .draw(fromCenter: center, radius: 0, toCenter: center, radius: canvas.width * 0.45, options: [])
        }

        let panel = CGRect(x: padding, y: padding, width: layout.panelSize.width, height: layout.panelSize.height)
        let panelPath = NSBezierPath(roundedRect: panel, xRadius: 12, yRadius: 12)

        // Window shadow: a wide soft one plus a tight contour, like macOS draws.
        for (blur, offset, alpha) in [(CGFloat(28), CGFloat(-10), CGFloat(0.20)), (2, -0.5, 0.18)] {
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowBlurRadius = blur
            shadow.shadowOffset = NSSize(width: 0, height: offset)
            shadow.shadowColor = NSColor.black.withAlphaComponent(alpha)
            shadow.set()
            NSColor(white: 0.95, alpha: 1).setFill()
            panelPath.fill()
            NSGraphicsContext.restoreGraphicsState()
        }

        // The HUD material blurs whatever is behind the panel, which cannot be
        // rendered offscreen; a light frosted fill stands in for it.
        NSGradient(starting: NSColor(white: 0.955, alpha: 1), ending: NSColor(white: 0.915, alpha: 1))!
            .draw(in: panelPath, angle: -90)

        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: panel.minX, yBy: panel.minY)
        transform.concat()

        // Same look as SwitcherPanel's selection layer (default blue accent).
        let accent = NSColor.systemBlue
        let tile = layout.tiles[selected]
        let selection = NSBezierPath(roundedRect: tile, xRadius: 8, yRadius: 8)
        accent.withAlphaComponent(0.30).setFill()
        selection.fill()
        let ring = NSBezierPath(roundedRect: tile.insetBy(dx: 0.75, dy: 0.75), xRadius: 7.25, yRadius: 7.25)
        ring.lineWidth = 1.5
        accent.withAlphaComponent(0.85).setStroke()
        ring.stroke()

        // The tiles themselves: the app's own drawing code.
        content.draw(content.bounds)
        NSGraphicsContext.restoreGraphicsState()

        // Panel border, as SwitcherPanel sets it on its background layer.
        NSColor.white.withAlphaComponent(0.10).setStroke()
        let border = NSBezierPath(roundedRect: panel.insetBy(dx: 0.5, dy: 0.5), xRadius: 11.5, yRadius: 11.5)
        border.lineWidth = 1
        border.stroke()
    }
    NSGraphicsContext.restoreGraphicsState()
    guard let image = context.makeImage() else { fail("could not finish the image") }
    return image
}

func writePNG(_ image: CGImage, to url: URL) {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
    else { fail("cannot write \(url.path)") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fail("cannot write \(url.path)") }
}

try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
let suffix = language == "en" ? "" : ".\(language)"
let target = outDir.appendingPathComponent("switcher\(suffix).png")
let image = render()
writePNG(image, to: target)
print("[\(language)] wrote \(target.lastPathComponent) (\(image.width)×\(image.height) px)")
