import Foundation
// what does a process exec'd through a symlinked bundle see?
var buf = [CChar](repeating: 0, count: 4096); var sz = UInt32(buf.count)
_NSGetExecutablePath(&buf, &sz)
print("_NSGetExecutablePath:", String(cString: buf))
print("Bundle.main.bundlePath:", Bundle.main.bundlePath)
print("Bundle.main.executablePath:", Bundle.main.executablePath ?? "nil")
print("Bundle.main.bundleIdentifier:", Bundle.main.bundleIdentifier ?? "nil")
print("LSUIElement:", Bundle.main.infoDictionary?["LSUIElement"] ?? "nil")
print("realpath:", String(cString: realpath(buf, nil)))
