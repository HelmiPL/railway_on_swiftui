import AppKit
// Draws the DMG window background. Usage: make-dmg-background.swift <output.png> <scale>
// Layout (in points, top-left origin) must match the icon positions in dmg-settings.py.
let args = CommandLine.arguments
let scale = CGFloat(Double(args[2])!)
// Taller than the visible 400pt so the gradient also fills the space when Finder hides the status bar.
let width: CGFloat = 640, height: CGFloat = 460
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: width, height: height)
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
let rgb = CGColorSpaceCreateDeviceRGB()
// Red gradient, matching the app icon. Mid-tone so Finder's labels stay legible in light and dark mode.
let red = CGGradient(colorsSpace: rgb, colors: [
    NSColor(red: 1.00, green: 0.45, blue: 0.43, alpha: 1).cgColor,
    NSColor(red: 0.88, green: 0.22, blue: 0.25, alpha: 1).cgColor,
    NSColor(red: 0.66, green: 0.07, blue: 0.13, alpha: 1).cgColor] as CFArray, locations: [0, 0.55, 1])!
ctx.drawLinearGradient(red, start: CGPoint(x: 0, y: height), end: CGPoint(x: width, y: 0), options: [])
// Soft light from the top
let glow = CGGradient(colorsSpace: rgb, colors: [
    NSColor.white.withAlphaComponent(0.22).cgColor, NSColor.white.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: width / 2, y: height + 60), startRadius: 0,
                       endCenter: CGPoint(x: width / 2, y: height + 60), endRadius: 380, options: [])
// Arrow between the app (x 180) and Applications (x 460), at icon height (y 190 from the top)
let arrowY = height - 190
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 278, y: arrowY))
arrow.line(to: NSPoint(x: 356, y: arrowY))
arrow.move(to: NSPoint(x: 338, y: arrowY + 18))
arrow.line(to: NSPoint(x: 358, y: arrowY))
arrow.line(to: NSPoint(x: 338, y: arrowY - 18))
arrow.lineWidth = 7
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 6, color: NSColor.black.withAlphaComponent(0.25).cgColor)
NSColor.white.withAlphaComponent(0.9).setStroke()
arrow.stroke()
ctx.restoreGState()
// Hint
let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
let shadow = NSShadow()
shadow.shadowOffset = NSSize(width: 0, height: -1)
shadow.shadowBlurRadius = 3
shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
let hint = NSAttributedString(string: "Drag Railway to the Applications folder to install", attributes: [
    .font: NSFont.systemFont(ofSize: 14, weight: .medium),
    .foregroundColor: NSColor.white.withAlphaComponent(0.92),
    .paragraphStyle: paragraph, .shadow: shadow])
hint.draw(in: NSRect(x: 0, y: height - 352, width: width, height: 22))
NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[1]))
