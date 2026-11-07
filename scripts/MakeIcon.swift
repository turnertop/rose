import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func drawIcon(size: Int) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: size * 4, bitsPerPixel: 32)!
    let graphics = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = graphics
    let scale = CGFloat(size) / 1024
    graphics.cgContext.scaleBy(x: scale, y: scale)
    let frame = NSRect(x: 64, y: 64, width: 896, height: 896)
    let base = NSBezierPath(roundedRect: frame, xRadius: 205, yRadius: 205)
    let shadow = NSShadow(); shadow.shadowColor = .black.withAlphaComponent(0.16); shadow.shadowBlurRadius = 30; shadow.shadowOffset = NSSize(width: 0, height: -12)
    NSGraphicsContext.saveGraphicsState(); shadow.set()
    NSColor(srgbRed: 0.98, green: 0.48, blue: 0.68, alpha: 1).setFill(); base.fill(); NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [NSColor(srgbRed: 1, green: 0.79, blue: 0.87, alpha: 1), NSColor(srgbRed: 0.96, green: 0.3, blue: 0.56, alpha: 1), NSColor(srgbRed: 0.83, green: 0.16, blue: 0.43, alpha: 1)])!.draw(in: base, angle: -65)
    NSColor.white.withAlphaComponent(0.6).setStroke(); base.lineWidth = 3; base.stroke()
    // A small rose-quartz prism, drawn as vector facets at every icon resolution.
    let points = [NSPoint(x: 510, y: 814), NSPoint(x: 738, y: 664), NSPoint(x: 715, y: 377), NSPoint(x: 510, y: 211), NSPoint(x: 291, y: 377), NSPoint(x: 273, y: 664)]
    let center = NSPoint(x: 505, y: 520)
    let opacities: [CGFloat] = [0.75, 0.34, 0.2, 0.5, 0.32, 0.91]
    for i in 0..<6 {
        let path = NSBezierPath(); path.move(to: points[i]); path.line(to: points[(i+1)%6]); path.line(to: center); path.close()
        NSColor.white.withAlphaComponent(opacities[i]).setFill(); path.fill()
        NSColor.white.withAlphaComponent(0.32).setStroke(); path.lineWidth = 2; path.stroke()
    }
    let outline = NSBezierPath(); outline.move(to: points[0]); points.dropFirst().forEach { outline.line(to: $0) }; outline.close()
    NSColor.white.withAlphaComponent(0.9).setStroke(); outline.lineWidth = 5; outline.lineJoinStyle = .round; outline.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    try drawIcon(size: points).write(to: output.appendingPathComponent("icon_\(points)x\(points).png"))
    try drawIcon(size: points * 2).write(to: output.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}

// Modern ICNS elements contain PNGs. Writing the container directly also works
// on Command Line Tools installations without a functioning iconutil service.
func integer(_ value: Int) -> Data {
    var number = UInt32(value).bigEndian
    return withUnsafeBytes(of: &number) { Data($0) }
}
var elements = Data()
for (type, pixels) in [("icp4", 16), ("icp5", 32), ("icp6", 64), ("ic07", 128), ("ic08", 256), ("ic09", 512), ("ic10", 1024), ("ic11", 32), ("ic12", 64), ("ic13", 256), ("ic14", 512)] {
    let png = drawIcon(size: pixels)
    elements.append(Data(type.utf8)); elements.append(integer(8 + png.count)); elements.append(png)
}
var container = Data("icns".utf8)
container.append(integer(elements.count + 8)); container.append(elements)
try container.write(to: output.deletingLastPathComponent().appendingPathComponent("Rose.icns"))
