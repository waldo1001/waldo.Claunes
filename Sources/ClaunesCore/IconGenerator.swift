import AppKit
import Foundation

/// Draws the Claune icon: Claude's own icon, read from the installed Claude.app and drawn unmodified,
/// with a corner badge in the profile color. Without that icon: a rounded tile in the profile color.
/// No Anthropic artwork is shipped or altered.
public enum IconGenerator {
    public static func color(fromHex hex: String) -> NSColor {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return NSColor(red: 0.8, green: 0.47, blue: 0.36, alpha: 1) }
        return NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255,
                       blue: CGFloat(v & 0xff) / 255, alpha: 1)
    }

    /// Renders one tile at exactly `pixels` x `pixels` (independent of the screen scale).
    public static func tile(badge: String, colorHex: String, pixels: Int, inset: CGFloat = 0.08) -> NSImage {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = NSSize(width: pixels, height: pixels)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let px = CGFloat(pixels)
        let i = px * inset
        let rect = NSRect(x: i, y: i, width: px - 2 * i, height: px - 2 * i)
        let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.height * 0.225)
        color(fromHex: colorHex).setFill()
        path.fill()
        let text = badge.isEmpty ? "C" : badge
        let fontSize = px * (text.count > 1 ? 0.38 : 0.52)
        let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white, .paragraphStyle: paragraph]
        let str = NSAttributedString(string: text, attributes: attrs)
        let bounds = str.boundingRect(with: NSSize(width: px, height: px), options: [.usesLineFragmentOrigin])
        let origin = NSPoint(x: (px - bounds.width) / 2, y: (px - bounds.height) / 2 - bounds.minY)
        str.draw(with: NSRect(origin: origin, size: bounds.size), options: [.usesLineFragmentOrigin])
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.addRepresentation(rep)
        return image
    }

    /// Claude's icon (`base`) as-is with a corner badge; the plain tile when `base` is nil.
    public static func icon(badge: String, colorHex: String, pixels: Int, base: NSImage?) -> NSImage {
        guard let base else { return tile(badge: badge, colorHex: colorHex, pixels: pixels) }
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = NSSize(width: pixels, height: pixels)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        let px = CGFloat(pixels)
        base.draw(in: NSRect(x: 0, y: 0, width: px, height: px), from: .zero, operation: .copy, fraction: 1)
        // Badge: circle in the bottom-right corner, white ring, profile color, white letter(s).
        let d = px * 0.46
        let circle = NSRect(x: px * 0.74 - d / 2, y: px * 0.26 - d / 2, width: d, height: d)
        NSColor.white.setFill()
        NSBezierPath(ovalIn: circle).fill()
        color(fromHex: colorHex).setFill()
        NSBezierPath(ovalIn: circle.insetBy(dx: px * 0.025, dy: px * 0.025)).fill()
        let text = badge.isEmpty ? "C" : badge
        let font = NSFont.systemFont(ofSize: d * (text.count > 1 ? 0.40 : 0.55), weight: .bold)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let str = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.white, .paragraphStyle: paragraph])
        let bounds = str.boundingRect(with: circle.size, options: [.usesLineFragmentOrigin])
        let origin = NSPoint(x: circle.midX - bounds.width / 2, y: circle.midY - bounds.height / 2 - bounds.minY)
        str.draw(with: NSRect(origin: origin, size: bounds.size), options: [.usesLineFragmentOrigin])
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.addRepresentation(rep)
        return image
    }

    public static func pngData(_ image: NSImage) throws -> Data {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return png
    }

    /// Writes an .icns using /usr/bin/iconutil (present on every Mac).
    /// `baseIcon`: Claude's icon file; when given and readable, the icon is that icon with a corner badge.
    public static func writeICNS(badge: String, colorHex: String, baseIcon: URL? = nil, to url: URL) throws {
        let base = baseIcon.flatMap { NSImage(contentsOf: $0) }
        let fm = FileManager.default
        let iconset = fm.temporaryDirectory.appendingPathComponent("claune-\(UUID().uuidString).iconset", isDirectory: true)
        try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: iconset) }
        let sizes: [(String, Int)] = [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
                                      ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256),
                                      ("icon_256x256@2x", 512), ("icon_512x512", 512), ("icon_512x512@2x", 1024)]
        for (name, px) in sizes {
            try pngData(icon(badge: badge, colorHex: colorHex, pixels: px, base: base)).write(to: iconset.appendingPathComponent("\(name).png"))
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        p.arguments = ["-c", "icns", iconset.path, "-o", url.path]
        let err = Pipe()
        p.standardError = err
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(domain: "IconGenerator", code: Int(p.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "iconutil failed: \(msg)"])
        }
    }
}
