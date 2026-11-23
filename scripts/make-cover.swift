// Draws the 1600×900 cover image used on SupportKori and GitHub.
// Usage: swift scripts/make-cover.swift icon1024.png out.png
import AppKit

let args = CommandLine.arguments
let iconPath = args.count > 1 ? args[1] : "docs/images/icon.png"
let out = args.count > 2 ? args[2] : "docs/images/cover.png"
let W: CGFloat = 1600, H: CGFloat = 900

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(deviceRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

// Background
NSGradient(colors: [rgb(24, 28, 40), rgb(10, 12, 18)])!.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -60)
rgb(77, 150, 255, 0.18).setFill()
NSBezierPath(ovalIn: NSRect(x: 1000, y: 300, width: 800, height: 800)).fill()
rgb(160, 110, 255, 0.14).setFill()
NSBezierPath(ovalIn: NSRect(x: -200, y: -300, width: 700, height: 700)).fill()

// Icon
if let icon = NSImage(contentsOfFile: iconPath) {
    icon.draw(in: NSRect(x: 980, y: 170, width: 560, height: 560))
}

func text(_ s: String, _ size: CGFloat, _ weight: NSFont.Weight, _ color: NSColor, at p: NSPoint, width: CGFloat = 900) {
    let para = NSMutableParagraphStyle(); para.lineSpacing = size * 0.18
    let str = NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                                         .foregroundColor: color, .paragraphStyle: para])
    // p is the bottom-left of the text block
    let h = str.boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude),
                             options: [.usesLineFragmentOrigin]).height
    str.draw(with: NSRect(x: p.x, y: p.y, width: width, height: h), options: [.usesLineFragmentOrigin])
}

// Badge
let badge = NSRect(x: 110, y: 690, width: 250, height: 52)
rgb(40, 200, 64, 0.18).setFill(); NSBezierPath(roundedRect: badge, xRadius: 26, yRadius: 26).fill()
text("FREE FOR MAC", 24, .bold, rgb(110, 230, 130), at: NSPoint(x: 140, y: 702))

text("Dock Viewer", 120, .heavy, .white, at: NSPoint(x: 104, y: 520))
text("Windows-style window and browser-tab\npreviews for the macOS Dock", 42, .medium,
     rgb(255, 255, 255, 0.78), at: NSPoint(x: 110, y: 380))

let bullets = ["Hover a Dock icon to see every window", "Preview and switch browser tabs",
               "Click the icon to minimize, like Windows", "Updates itself automatically"]
for (i, b) in bullets.enumerated() {
    let y = 300 - CGFloat(i) * 52
    rgb(77, 176, 255).setFill(); NSBezierPath(ovalIn: NSRect(x: 112, y: y + 10, width: 14, height: 14)).fill()
    text(b, 30, .regular, rgb(255, 255, 255, 0.85), at: NSPoint(x: 142, y: y))
}

text("by Creative Assistant  ·  supportkori.com", 24, .medium, rgb(255, 255, 255, 0.45), at: NSPoint(x: 110, y: 50))

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
