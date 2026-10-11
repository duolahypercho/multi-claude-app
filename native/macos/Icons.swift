import AppKit

let palette: [String: NSColor] = [
    "orange": NSColor(srgbRed: 0.80, green: 0.39, blue: 0.27, alpha: 1),
    "blue": NSColor(srgbRed: 0.21, green: 0.39, blue: 0.69, alpha: 1),
    "purple": NSColor(srgbRed: 0.48, green: 0.32, blue: 0.65, alpha: 1),
    "teal": NSColor(srgbRed: 0.15, green: 0.49, blue: 0.47, alpha: 1),
    "yellow": NSColor(srgbRed: 0.74, green: 0.55, blue: 0.16, alpha: 1)
]
// Claude mark from https://claude.ai/favicon.svg. See assets/claude-mark.svg and NOTICE.md.
private let claudeMarkData = "M52.4285 162.873L98.7844 136.879L99.5485 134.602L98.7844 133.334H96.4921L88.7237 132.862L62.2346 132.153L39.3113 131.207L17.0249 130.026L11.4214 128.844L6.2 121.873L6.7094 118.447L11.4214 115.257L18.171 115.847L33.0711 116.911L55.485 118.447L71.6586 119.392L95.728 121.873H99.5485L100.058 120.337L98.7844 119.392L97.7656 118.447L74.5877 102.732L49.4995 86.1905L36.3823 76.62L29.3779 71.7757L25.8121 67.2858L24.2839 57.3608L30.6515 50.2716L39.3113 50.8623L41.4763 51.4531L50.2636 58.1879L68.9842 72.7209L93.4357 90.6804L97.0015 93.6343L98.4374 92.6652L98.6571 91.9801L97.0015 89.2625L83.757 65.2772L69.621 40.8192L63.2534 30.6579L61.5978 24.632C60.9565 22.1032 60.579 20.0111 60.579 17.4246L67.8381 7.49965L71.9133 6.19995L81.7193 7.49965L85.7946 11.0443L91.9074 24.9865L101.714 46.8451L116.996 76.62L121.453 85.4816L123.873 93.6343L124.764 96.1155H126.292V94.6976L127.566 77.9197L129.858 57.3608L132.15 30.8942L132.915 23.4505L136.608 14.4708L143.994 9.62643L149.725 12.344L154.437 19.0788L153.8 23.4505L150.998 41.6463L145.522 70.1215L141.957 89.2625H143.994L146.414 86.7813L156.093 74.0206L172.266 53.698L179.398 45.6635L187.803 36.802L193.152 32.5484H203.34L210.726 43.6549L207.415 55.1159L196.972 68.3492L188.312 79.5739L175.896 96.2095L168.191 109.585L168.882 110.689L170.738 110.53L198.755 104.504L213.91 101.787L231.994 98.7149L240.144 102.496L241.036 106.395L237.852 114.311L218.495 119.037L195.826 123.645L162.07 131.592L161.696 131.893L162.137 132.547L177.36 133.925L183.855 134.279H199.774L229.447 136.524L237.215 141.605L241.8 147.867L241.036 152.711L229.065 158.737L213.019 154.956L175.45 145.977L162.587 142.787H160.805V143.85L171.502 154.366L191.242 172.089L215.82 195.011L217.094 200.682L213.91 205.172L210.599 204.699L188.949 188.394L180.544 181.069L161.696 165.118H160.422V166.772L164.752 173.152L187.803 207.771L188.949 218.405L187.294 221.832L181.308 223.959L174.813 222.777L161.187 203.754L147.305 182.486L136.098 163.345L134.745 164.2L128.075 235.42L125.019 239.082L117.887 241.8L111.902 237.31L108.718 229.984L111.902 215.452L115.722 196.547L118.779 181.541L121.58 162.873L123.291 156.636L123.14 156.219L121.773 156.449L107.699 175.752L86.304 204.699L69.3663 222.777L65.291 224.431L58.2867 220.768L58.9235 214.27L62.8713 208.48L86.304 178.705L100.44 160.155L109.551 149.507L109.462 147.967L108.959 147.924L46.6977 188.512L35.6182 189.93L30.7788 185.44L31.4156 178.115L33.7079 175.752L52.4285 162.873Z"
private let claudeMark: NSBezierPath = {
    let regex = try! NSRegularExpression(pattern: "[MLHVCZ]|[-+]?[0-9]*\\.?[0-9]+")
    let tokens = regex.matches(in: claudeMarkData, range: NSRange(claudeMarkData.startIndex..., in: claudeMarkData)).map {
        String(claudeMarkData[Range($0.range, in: claudeMarkData)!])
    }
    let path = NSBezierPath(); var i = 0; var point = NSPoint.zero
    func number() -> CGFloat { defer { i += 1 }; return CGFloat(Double(tokens[i])!) }
    while i < tokens.count {
        let command = tokens[i]; i += 1
        switch command {
        case "M", "L": point = NSPoint(x: number(), y: number()); if command == "M" { path.move(to: point) } else { path.line(to: point) }
        case "H": point.x = number(); path.line(to: point)
        case "V": point.y = number(); path.line(to: point)
        case "C": let first = NSPoint(x: number(), y: number()); let second = NSPoint(x: number(), y: number()); point = NSPoint(x: number(), y: number()); path.curve(to: point, controlPoint1: first, controlPoint2: second)
        case "Z": path.close()
        default: preconditionFailure("Unsupported Claude mark path command")
        }
    }
    return path
}()
func accountTag(_ p: Profile) -> String {
    let label = p.name.hasPrefix("Account ") ? "" : String(p.name.prefix(1)).uppercased()
    return label + p.id
}
func profileImage(_ p: Profile, size: CGFloat) -> NSImage? {
    let image = iconImage(p.iconColor, size: Int(size * 2), tag: accountTag(p)); image.size = NSSize(width: size, height: size); return image
}
func iconImage(_ color: String, size: Int, tag: String? = nil) -> NSImage {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.cgContext.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    let background = NSBezierPath(roundedRect: NSRect(x: 80, y: 80, width: 864, height: 864), xRadius: 194, yRadius: 194)
    NSColor(srgbRed: 0.97, green: 0.95, blue: 0.90, alpha: 1).setFill(); background.fill()
    let mark = claudeMark.copy() as! NSBezierPath
    let transform = AffineTransform(translationByX: tag == nil ? 180 : 140, byY: 830)
    var placement = transform; placement.scale(x: 2.62, y: -2.62); mark.transform(using: placement)
    NSColor(srgbRed: 0.851, green: 0.467, blue: 0.341, alpha: 1).setFill(); mark.fill()
    if let tag {
        let badge = NSRect(x: 670, y: 363, width: 290, height: 216)
        let ring = badge.insetBy(dx: -13, dy: -13)
        NSColor(srgbRed: 0.97, green: 0.95, blue: 0.90, alpha: 1).setFill()
        NSBezierPath(roundedRect: ring, xRadius: 74, yRadius: 74).fill()
        (palette[color] ?? palette["orange"]!).setFill(); NSBezierPath(roundedRect: badge, xRadius: 62, yRadius: 62).fill()
        let fontSize: CGFloat = tag.count <= 3 ? 139 : tag.count <= 4 ? 108 : 82
        let text = NSAttributedString(string: tag, attributes: [.font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold), .foregroundColor: NSColor.white])
        let dimensions = text.size(); text.draw(at: NSPoint(x: badge.midX - dimensions.width / 2, y: badge.midY - dimensions.height / 2 + 7))
    }
    NSGraphicsContext.restoreGraphicsState()
    let image = NSImage(size: NSSize(width: size, height: size)); image.addRepresentation(rep); return image
}
func renderProfileIcon(_ color: String, _ destination: String, tag: String? = nil) throws {
    let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".iconset")
    try fm.createDirectory(at: temp, withIntermediateDirectories: true); defer { try? fm.removeItem(at: temp) }
    for size in [16, 32, 64, 128, 256, 512, 1024] {
        let rep = iconImage(color, size: size, tag: tag).representations[0] as! NSBitmapImageRep
        let data = rep.representation(using: .png, properties: [:])!
        if size <= 512 { try data.write(to: temp.appendingPathComponent("icon_\(size)x\(size).png")) }
        if size >= 32 { let base = size / 2; try data.write(to: temp.appendingPathComponent("icon_\(base)x\(base)@2x.png")) }
    }
    guard try run("/usr/bin/iconutil", ["-c", "icns", temp.path, "-o", destination]) == 0 else { throw fail("Could not create a profile icon.") }
    // Keep an editable vector copy next to the macOS icon.
    let badgeColor = (palette[color] ?? palette["orange"]!).usingColorSpace(.sRGB)!
    let hex = String(format: "#%02X%02X%02X", Int((badgeColor.redComponent * 255).rounded()), Int((badgeColor.greenComponent * 255).rounded()), Int((badgeColor.blueComponent * 255).rounded()))
    let escapedTag = (tag ?? "").replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    let fontSize = (tag?.count ?? 0) <= 3 ? 139 : (tag?.count ?? 0) <= 4 ? 108 : 82
    let badge = tag == nil ? "" : "<rect x=\"657\" y=\"432\" width=\"316\" height=\"242\" rx=\"74\" fill=\"#F7F2E6\"/><rect x=\"670\" y=\"445\" width=\"290\" height=\"216\" rx=\"62\" fill=\"\(hex)\"/><text x=\"815\" y=\"564\" text-anchor=\"middle\" dominant-baseline=\"middle\" font-family=\"monospace\" font-weight=\"bold\" font-size=\"\(fontSize)\" fill=\"white\">\(escapedTag)</text>"
    let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 1024 1024\"><rect x=\"80\" y=\"80\" width=\"864\" height=\"864\" rx=\"194\" fill=\"#F7F2E6\"/><path d=\"\(claudeMarkData)\" transform=\"translate(\(tag == nil ? 180 : 140) 194) scale(2.62)\" fill=\"#D97757\"/>\(badge)</svg>\n"
    try Data(svg.utf8).write(to: URL(fileURLWithPath: destination).deletingPathExtension().appendingPathExtension("svg"), options: .atomic)
}
