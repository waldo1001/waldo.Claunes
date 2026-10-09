import Foundation
import CoreServices
let scheme = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "claude"
if let h = LSCopyDefaultHandlerForURLScheme(scheme as CFString)?.takeRetainedValue() { print("default handler for \(scheme)://  =", h) } else { print("no default handler for \(scheme)") }
if let all = LSCopyAllHandlersForURLScheme(scheme as CFString)?.takeRetainedValue() as? [String] { print("all handlers:", all) }
