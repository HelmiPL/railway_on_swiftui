import AppKit
let args = CommandLine.arguments
let train = NSImage(contentsOfFile: args[1])!
let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext
// macOS icon grid: 824pt body centred in a 1024pt canvas.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let path = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
// Soft drop shadow
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.3).cgColor)
ctx.addPath(path); ctx.setFillColor(NSColor.white.cgColor); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(path); ctx.clip()
// Sky gradient
let sky = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
    NSColor(red: 0.42, green: 0.72, blue: 0.98, alpha: 1).cgColor,
    NSColor(red: 0.16, green: 0.45, blue: 0.86, alpha: 1).cgColor] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(sky, start: CGPoint(x: 0, y: 924), end: CGPoint(x: 0, y: 100), options: [])
// Platform / ground
ctx.setFillColor(NSColor(red: 0.20, green: 0.22, blue: 0.27, alpha: 1).cgColor)
ctx.fill(CGRect(x: 0, y: 100, width: 1024, height: 190))
ctx.setFillColor(NSColor(red: 0.96, green: 0.80, blue: 0.25, alpha: 1).cgColor)
ctx.fill(CGRect(x: 0, y: 282, width: 1024, height: 14))
// Train: the artwork is cut off on the left, so align it with the body's left edge.
let trainRect = CGRect(x: 36, y: 226, width: 790, height: 790)
train.draw(in: trainRect, from: .zero, operation: .sourceOver, fraction: 1)
// Glassy top highlight
let shine = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
    NSColor.white.withAlphaComponent(0.28).cgColor, NSColor.white.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(shine, start: CGPoint(x: 0, y: 924), end: CGPoint(x: 0, y: 640), options: [])
ctx.restoreGState()
// Hairline edge
ctx.addPath(path); ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.12).cgColor); ctx.setLineWidth(2); ctx.strokePath()
image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
