import Foundation
let bundleURL = Bundle.main.bundleURL
let contents = bundleURL.appendingPathComponent("Contents")
let plist = NSDictionary(contentsOf: contents.appendingPathComponent("Info.plist")) as? [String: Any] ?? [:]
// side-car config so the Info.plist can stay pristine
let side = NSDictionary(contentsOf: contents.appendingPathComponent("Resources/claune.plist")) as? [String: Any] ?? [:]
let dataDir = (side["ClauneDataDir"] ?? plist["ClauneDataDir"]) as? String ?? ""
let mode = (side["ClauneExecMode"] ?? plist["ClauneExecMode"]) as? String ?? "symlink"
let target: String
switch mode {
case "real": target = "/Applications/Claude.app/Contents/MacOS/Claude"
case "sibling": target = contents.appendingPathComponent("MacOS/Claude-real").path
default: target = contents.appendingPathComponent("MacOS/Claude").path
}
var args: [String] = [target]
if !dataDir.isEmpty { args.append("--user-data-dir=\(dataDir)") }
args.append(contentsOf: CommandLine.arguments.dropFirst())
let cargs = args.map { strdup($0) } + [nil]
execv(target, cargs)
perror("execv failed"); exit(1)
