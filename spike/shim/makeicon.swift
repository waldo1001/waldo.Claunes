// Generate a Claude-style rounded tile icon with a letter -> .icns via iconutil
import AppKit
let args = CommandLine.arguments
let letter = args[1], hex = args[2], out = args[3]
func color(_ h: String) -> NSColor {
    var s = h; if s.hasPrefix("#") { s.removeFirst() }
    let v = UInt32(s, radix: 16) ?? 0xCC785C
    return NSColor(red: CGFloat((v >> 16) & 0xff)/255, green: CGFloat((v >> 8) & 0xff)/255, blue: CGFloat(v & 0xff)/255, alpha: 1)
}
func render(_ px: Int) -> NSImage {
    let img = NSImage(size: NSSize(width: px, height: px))
    img.lockFocus()
    let inset = CGFloat(px) * 0.08
    let rect = NSRect(x: inset, y: inset, width: CGFloat(px) - 2*inset, height: CGFloat(px) - 2*inset)
    let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.height * 0.225)
    color(hex).setFill(); path.fill()
    let font = NSFont.systemFont(ofSize: CGFloat(px) * 0.5, weight: .semibold)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
    let str = NSAttributedString(string: letter, attributes: attrs)
    let sz = str.size()
    str.draw(at: NSPoint(x: (CGFloat(px) - sz.width)/2, y: (CGFloat(px) - sz.height)/2))
    img.unlockFocus()
    return img
}
let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("icon-\(UUID().uuidString).iconset")
try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
for (name, px) in [("icon_16x16",16),("icon_16x16@2x",32),("icon_32x32",32),("icon_32x32@2x",64),("icon_128x128",128),("icon_128x128@2x",256),("icon_256x256",256),("icon_256x256@2x",512),("icon_512x512",512),("icon_512x512@2x",1024)] {
    let img = render(px)
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    let png = rep.representation(using: .png, properties: [:])!
    try! png.write(to: tmp.appendingPathComponent("\(name).png"))
}
let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", tmp.path, "-o", out]; try! p.run(); p.waitUntilExit()
print("icns written:", out, p.terminationStatus)
