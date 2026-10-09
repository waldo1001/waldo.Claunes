import Foundation
import CoreServices
let scheme = CommandLine.arguments[1], bid = CommandLine.arguments[2]
let st = LSSetDefaultHandlerForURLScheme(scheme as CFString, bid as CFString)
print("LSSetDefaultHandlerForURLScheme(\(scheme), \(bid)) ->", st)
if let h = LSCopyDefaultHandlerForURLScheme(scheme as CFString)?.takeRetainedValue() { print("now:", h) }
