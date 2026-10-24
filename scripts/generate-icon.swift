import AppKit
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let preview = URL(fileURLWithPath: CommandLine.arguments[2])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
func render(_ size: Int) throws -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    let rect = NSRect(x: 84, y: 84, width: 856, height: 856)
    let shape = NSBezierPath(roundedRect: rect, xRadius: 190, yRadius: 190)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow(); shadow.shadowColor = NSColor(srgbRed: 0.145, green: 0.133, blue: 0.33, alpha: 0.25); shadow.shadowBlurRadius = 28; shadow.shadowOffset = NSSize(width: 0, height: -14); shadow.set()
    NSColor(srgbRed: 0.44, green: 0.41, blue: 0.89, alpha: 1).setFill(); shape.fill()
    NSGraphicsContext.restoreGraphicsState()
    let gradient = NSGradient(colorsAndLocations:
        (NSColor(srgbRed: 0.588, green: 0.565, blue: 1, alpha: 1), 0),
        (NSColor(srgbRed: 0.439, green: 0.408, blue: 0.886, alpha: 1), 0.5),
        (NSColor(srgbRed: 0.306, green: 0.286, blue: 0.702, alpha: 1), 1))!
    gradient.draw(in: shape, angle: -55)
    let rim = NSBezierPath(roundedRect: rect.insetBy(dx: 3, dy: 3), xRadius: 187, yRadius: 187)
    NSColor.white.withAlphaComponent(0.22).setStroke(); rim.lineWidth = 3; rim.stroke()
    // The source SVG uses downward-positive y coordinates.
    let points: [(CGFloat, CGFloat)] = [(230,512),(324,512),(381,364),(462,670),(553,264),(636,614),(688,512),(794,512)]
    let wave = NSBezierPath(); wave.move(to: NSPoint(x: points[0].0, y: 1024 - points[0].1))
    for (x,y) in points.dropFirst() { wave.line(to: NSPoint(x: x, y: 1024 - y)) }
    wave.lineWidth = 52; wave.lineCapStyle = .round; wave.lineJoinStyle = .round
    NSColor.white.setStroke(); wave.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}
for size in [16, 32, 128, 256, 512] {
    try render(size).write(to: output.appending(path: "icon_\(size)x\(size).png"))
    try render(size * 2).write(to: output.appending(path: "icon_\(size)x\(size)@2x.png"))
}
try render(1024).write(to: preview)
print("Rendered Tempo icon sizes and 1024px preview.")
