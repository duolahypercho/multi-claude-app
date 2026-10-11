import AppKit

let palette: [String: NSColor] = [
    "orange": NSColor(srgbRed: 0.80, green: 0.39, blue: 0.27, alpha: 1),
    "blue": NSColor(srgbRed: 0.21, green: 0.39, blue: 0.69, alpha: 1),
    "purple": NSColor(srgbRed: 0.48, green: 0.32, blue: 0.65, alpha: 1),
    "teal": NSColor(srgbRed: 0.15, green: 0.49, blue: 0.47, alpha: 1),
    "yellow": NSColor(srgbRed: 0.74, green: 0.55, blue: 0.16, alpha: 1)
]
// Original artwork: a C over stacked profile cards. No vendor logo assets.
func profileImage(_ p: Profile, size: CGFloat) -> NSImage? { iconImage(p.iconColor, size: Int(size)) }
func iconImage(_ color: String, size: Int) -> NSImage {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.cgContext.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    let background = NSBezierPath(roundedRect: NSRect(x: 68, y: 68, width: 888, height: 888), xRadius: 196, yRadius: 196)
    (palette[color] ?? palette["orange"]!).setFill(); background.fill()
    NSColor.white.withAlphaComponent(0.18).setFill()
    NSBezierPath(roundedRect: NSRect(x: 247, y: 196, width: 570, height: 606), xRadius: 60, yRadius: 60).fill()
    NSColor.white.withAlphaComponent(0.12).setFill()
    NSBezierPath(roundedRect: NSRect(x: 202, y: 239, width: 570, height: 606), xRadius: 60, yRadius: 60).fill()
    let text = NSAttributedString(string: "C", attributes: [.font: NSFont.systemFont(ofSize: 560, weight: .semibold), .foregroundColor: NSColor.white])
    let textSize = text.size(); text.draw(at: NSPoint(x: (1024 - textSize.width) / 2 - 4, y: (1024 - textSize.height) / 2 + 15))
    NSGraphicsContext.restoreGraphicsState()
    let image = NSImage(size: NSSize(width: size, height: size)); image.addRepresentation(rep); return image
}
func renderProfileIcon(_ color: String, _ destination: String) throws {
    let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".iconset")
    try fm.createDirectory(at: temp, withIntermediateDirectories: true); defer { try? fm.removeItem(at: temp) }
    for size in [16, 32, 64, 128, 256, 512, 1024] {
        let rep = iconImage(color, size: size).representations[0] as! NSBitmapImageRep
        let data = rep.representation(using: .png, properties: [:])!
        if size <= 512 { try data.write(to: temp.appendingPathComponent("icon_\(size)x\(size).png")) }
        if size >= 32 { let base = size / 2; try data.write(to: temp.appendingPathComponent("icon_\(base)x\(base)@2x.png")) }
    }
    guard try run("/usr/bin/iconutil", ["-c", "icns", temp.path, "-o", destination]) == 0 else { throw fail("Could not create a profile icon.") }
}
