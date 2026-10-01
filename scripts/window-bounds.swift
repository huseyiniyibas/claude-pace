// Lists the on-screen windows of one process: "id layer x y width height", in points.
// Used by screenshots.sh to capture only this app's own windows. Usage: window-bounds <pid>
import CoreGraphics
import Foundation

guard CommandLine.arguments.count == 2, let pid = Int32(CommandLine.arguments[1]) else {
    FileHandle.standardError.write(Data("usage: window-bounds <pid>\n".utf8))
    exit(2)
}

let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
for window in windows where (window[kCGWindowOwnerPID as String] as? Int32) == pid {
    let id = window[kCGWindowNumber as String] as? Int ?? 0
    let layer = window[kCGWindowLayer as String] as? Int ?? 0
    let bounds = window[kCGWindowBounds as String] as? [String: Double] ?? [:]
    let x = Int((bounds["X"] ?? 0).rounded())
    let y = Int((bounds["Y"] ?? 0).rounded())
    let width = Int((bounds["Width"] ?? 0).rounded())
    let height = Int((bounds["Height"] ?? 0).rounded())
    print(id, layer, x, y, width, height)
}
