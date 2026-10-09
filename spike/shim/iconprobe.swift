import AppKit
// Print what the system associates with a running app: name, bundle, and a center-pixel sample of its icon
for pidStr in CommandLine.arguments.dropFirst() {
    guard let pid = Int32(pidStr), let app = NSRunningApplication(processIdentifier: pid) else { print(pidStr, "no running app"); continue }
    print("pid", pid, "localizedName:", app.localizedName ?? "nil", "bundleId:", app.bundleIdentifier ?? "nil", "bundleURL:", app.bundleURL?.path ?? "nil", "execURL:", app.executableURL?.path ?? "nil")
    if let icon = app.icon, let tiff = icon.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
        let x = rep.pixelsWide/2, y = rep.pixelsHigh/2
        let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)
        let c2 = rep.colorAt(x: rep.pixelsWide/4, y: rep.pixelsHigh/4)?.usingColorSpace(.sRGB)
        func s(_ c: NSColor?) -> String { guard let c = c else { return "nil" }; return String(format: "#%02X%02X%02X a=%.2f", Int(c.redComponent*255), Int(c.greenComponent*255), Int(c.blueComponent*255), c.alphaComponent) }
        print("  icon size:", rep.pixelsWide, "x", rep.pixelsHigh, "center:", s(c), "quarter:", s(c2))
    } else { print("  no icon") }
}
