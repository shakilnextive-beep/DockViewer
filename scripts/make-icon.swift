// Draws the Dock Viewer app icon (1024×1024 PNG).
// Usage: swift scripts/make-icon.swift out.png
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(deviceRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}
func rounded(_ r: NSRect, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
}

// Background squircle (macOS icon grid: 824 px body, 100 px margin)
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let bg = rounded(body, 185)
NSGradient(colors: [rgb(44, 52, 72), rgb(16, 19, 28)])!.draw(in: bg, angle: -90)
rgb(255, 255, 255, 0.10).setStroke(); bg.lineWidth = 4; bg.stroke()

// Dock bar along the bottom
let dock = NSRect(x: 190, y: 170, width: 644, height: 120)
rgb(255, 255, 255, 0.16).setFill(); rounded(dock, 36).fill()
let iconColors = [rgb(255, 95, 87), rgb(77, 176, 255), rgb(40, 200, 64), rgb(254, 188, 46)]
for (i, c) in iconColors.enumerated() {
    let x = 222 + CGFloat(i) * 152
    c.setFill(); rounded(NSRect(x: x, y: 192, width: 120, height: 76), 22).fill()
}
// Highlight dot under the hovered (blue) icon
rgb(255, 255, 255, 0.9).setFill()
NSBezierPath(ovalIn: NSRect(x: 428, y: 178, width: 12, height: 12)).fill()

// Preview popup with two window thumbnails, rising from the blue icon
let popup = NSRect(x: 170, y: 350, width: 684, height: 470)
let shadow = NSShadow(); shadow.shadowBlurRadius = 40; shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.shadowColor = rgb(0, 0, 0, 0.5)
NSGraphicsContext.saveGraphicsState(); shadow.set()
rgb(32, 32, 32).setFill(); rounded(popup, 44).fill()
NSGraphicsContext.restoreGraphicsState()
rgb(255, 255, 255, 0.12).setStroke(); let pp = rounded(popup, 44); pp.lineWidth = 3; pp.stroke()

// Little pointer from popup to the hovered icon
let tip = NSBezierPath()
tip.move(to: NSPoint(x: 404, y: 352)); tip.line(to: NSPoint(x: 434, y: 318)); tip.line(to: NSPoint(x: 464, y: 352))
rgb(32, 32, 32).setFill(); tip.fill()

for i in 0..<2 {
    let x = 205 + CGFloat(i) * 315
    // title bar: traffic lights
    for (j, c) in [rgb(255, 95, 87), rgb(254, 188, 46), rgb(40, 200, 64)].enumerated() {
        c.setFill(); NSBezierPath(ovalIn: NSRect(x: x + CGFloat(j) * 34, y: 745, width: 24, height: 24)).fill()
    }
    rgb(255, 255, 255, 0.55).setFill(); rounded(NSRect(x: x + 112, y: 750, width: 150, height: 14), 7).fill()
    // window thumbnail
    let thumb = NSRect(x: x, y: 395, width: 300, height: 325)
    NSGradient(colors: [i == 0 ? rgb(77, 150, 255) : rgb(160, 110, 255),
                        i == 0 ? rgb(40, 90, 200) : rgb(100, 60, 200)])!.draw(in: rounded(thumb, 18), angle: -90)
    rgb(255, 255, 255, 0.85).setFill()
    rounded(NSRect(x: x + 28, y: 640, width: 180, height: 22), 11).fill()
    rgb(255, 255, 255, 0.45).setFill()
    for k in 0..<4 { rounded(NSRect(x: x + 28, y: 590 - CGFloat(k) * 44, width: CGFloat(240 - k * 35), height: 18), 9).fill() }
}
// Hover ring around the first thumbnail
rgb(77, 176, 255).setStroke()
let ring = rounded(NSRect(x: 197, y: 387, width: 316, height: 341), 24); ring.lineWidth = 6; ring.stroke()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
