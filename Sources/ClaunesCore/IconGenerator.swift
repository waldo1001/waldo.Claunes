import AppKit
import Foundation

/// Draws the Claune icon: a Claude-style rounded tile in the profile color with the badge.
/// Generated programmatically; no Anthropic artwork is used.
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

    public static func pngData(_ image: NSImage) throws -> Data {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return png
    }

    /// Writes an .icns using /usr/bin/iconutil (present on every Mac).
    public static func writeICNS(badge: String, colorHex: String, to url: URL) throws {
        let fm = FileManager.default
        let iconset = fm.temporaryDirectory.appendingPathComponent("claune-\(UUID().uuidString).iconset", isDirectory: true)
        try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: iconset) }
        let sizes: [(String, Int)] = [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
                                      ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256),
                                      ("icon_256x256@2x", 512), ("icon_512x512", 512), ("icon_512x512@2x", 1024)]
        for (name, px) in sizes {
            try pngData(tile(badge: badge, colorHex: colorHex, pixels: px)).write(to: iconset.appendingPathComponent("\(name).png"))
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
