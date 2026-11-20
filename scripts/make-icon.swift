import AppKit

// Zeichnet ein 1024×1024 App-Icon: Verlauf + stilisiertes Dock mit bunten Kacheln.
// Aufruf: make-icon.swift <out.png> [light|dark] [fullbleed]
// "fullbleed" zeichnet ohne Rand/Rundung (für Icon-Composer-.icon, das System maskiert selbst).
// "foreground" lässt den Hintergrund weg (den liefert icon.json je nach Hell/Dunkel).
let dark = CommandLine.arguments.count > 2 && CommandLine.arguments[2] == "dark"
let foreground = CommandLine.arguments.contains("foreground")
let fullbleed = foreground || CommandLine.arguments.contains("fullbleed")
let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
let size: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
if fullbleed {
    let t = NSAffineTransform()
    t.scale(by: size / (size - 200)); t.translateX(by: -100, yBy: -100)
    t.concat()
}

let inset: CGFloat = 100
let body = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let bg = fullbleed ? NSBezierPath(rect: body) : NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
let gradient = dark
    ? [NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.13, alpha: 1),
       NSColor(calibratedRed: 0.17, green: 0.15, blue: 0.32, alpha: 1)]
    : [NSColor(calibratedRed: 0.16, green: 0.20, blue: 0.45, alpha: 1),
       NSColor(calibratedRed: 0.36, green: 0.30, blue: 0.85, alpha: 1)]
if !foreground { NSGradient(colors: gradient)!.draw(in: bg, angle: 90) }

// Raster oben (= organisierte Gruppen)
let cell: CGFloat = 120, gap: CGFloat = 36
let gridW = 3 * cell + 2 * gap
for r in 0..<2 { for c in 0..<3 {
    let x = (size - gridW) / 2 + CGFloat(c) * (cell + gap)
    let y = 560 + CGFloat(r) * (cell + gap)
    NSColor.white.withAlphaComponent(dark ? 0.10 : 0.18).setFill()
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: cell, height: cell), xRadius: 30, yRadius: 30).fill()
}}

// Dock-Leiste
let bar = NSRect(x: 190, y: 220, width: size - 380, height: 200)
NSColor.white.withAlphaComponent(dark ? 0.14 : 0.28).setFill()
NSBezierPath(roundedRect: bar, xRadius: 56, yRadius: 56).fill()

let colors: [NSColor] = [.systemPink, .systemOrange, .systemTeal, .systemGreen]
let tile: CGFloat = 120, tg: CGFloat = 26
let total = 4 * tile + 3 * tg
for (i, base) in colors.enumerated() {
    var col = base
    appearance.performAsCurrentDrawingAppearance { col = NSColor(cgColor: base.cgColor)! }
    let x = (size - total) / 2 + CGFloat(i) * (tile + tg)
    col.setFill()
    NSBezierPath(roundedRect: NSRect(x: x, y: bar.midY - tile / 2, width: tile, height: tile), xRadius: 30, yRadius: 30).fill()
}

NSGraphicsContext.current = nil
let out = CommandLine.arguments[1]
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
