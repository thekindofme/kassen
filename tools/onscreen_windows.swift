import CoreGraphics
let opts = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
if let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] {
  for w in list {
    let owner = w[kCGWindowOwnerName as String] as? String ?? "?"
    if CommandLine.arguments.count > 1 && !owner.contains(CommandLine.arguments[1]) { continue }
    let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
    let layer = w[kCGWindowLayer as String] as? Int ?? 0
    print(owner, "layer", layer, b["X"] ?? "", b["Y"] ?? "", b["Width"] ?? "", b["Height"] ?? "")
  }
}
