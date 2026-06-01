import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("output/DecisionReview.iconset", isDirectory: true)
let resources = root.appendingPathComponent("output/DecisionReview.app/Contents/Resources", isDirectory: true)
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)

let icons: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

func drawIcon(size: Int) -> Data {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.imageInterpolation = .high

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor.clear.setFill()
    rect.fill()

    let inset = CGFloat(size) * 0.08
    let baseRect = rect.insetBy(dx: inset, dy: inset)
    let radius = CGFloat(size) * 0.22
    let basePath = NSBezierPath(roundedRect: baseRect, xRadius: radius, yRadius: radius)

    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 1.00, green: 0.78, blue: 0.28, alpha: 1),
        NSColor(calibratedRed: 0.96, green: 0.56, blue: 0.16, alpha: 1)
    ])!
    gradient.draw(in: basePath, angle: -38)

    let shadow = NSShadow()
    shadow.shadowColor = NSColor(calibratedRed: 0.48, green: 0.26, blue: 0.05, alpha: 0.24)
    shadow.shadowBlurRadius = CGFloat(size) * 0.035
    shadow.shadowOffset = NSSize(width: 0, height: -CGFloat(size) * 0.018)
    shadow.set()

    let warm = NSColor(calibratedWhite: 1.0, alpha: 0.92)
    let mint = NSColor(calibratedRed: 0.53, green: 0.88, blue: 0.78, alpha: 1)
    let pink = NSColor(calibratedRed: 1.0, green: 0.48, blue: 0.58, alpha: 1)

    func circle(center: CGPoint, diameter: CGFloat, color: NSColor) {
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)).fill()
    }

    let leftCenter = CGPoint(x: CGFloat(size) * 0.34, y: CGFloat(size) * 0.40)
    let topCenter = CGPoint(x: CGFloat(size) * 0.65, y: CGFloat(size) * 0.38)
    let bottomCenter = CGPoint(x: CGFloat(size) * 0.60, y: CGFloat(size) * 0.68)

    circle(center: leftCenter, diameter: CGFloat(size) * 0.30, color: warm)
    circle(center: topCenter, diameter: CGFloat(size) * 0.23, color: pink)
    circle(center: bottomCenter, diameter: CGFloat(size) * 0.27, color: mint)

    let line = NSBezierPath()
    line.move(to: leftCenter)
    line.line(to: topCenter)
    line.line(to: bottomCenter)
    NSColor(calibratedRed: 0.22, green: 0.14, blue: 0.06, alpha: 1).setStroke()
    line.lineWidth = CGFloat(size) * 0.045
    line.lineCapStyle = .round
    line.lineJoinStyle = .round
    line.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

for (name, size) in icons {
    let png = drawIcon(size: size)
    try png.write(to: iconset.appendingPathComponent(name))
}

let iconTypes: [(String, String)] = [
    ("icp4", "icon_16x16.png"),
    ("ic11", "icon_16x16@2x.png"),
    ("icp5", "icon_32x32.png"),
    ("ic12", "icon_32x32@2x.png"),
    ("ic07", "icon_128x128.png"),
    ("ic13", "icon_128x128@2x.png"),
    ("ic08", "icon_256x256.png"),
    ("ic14", "icon_256x256@2x.png"),
    ("ic09", "icon_512x512.png"),
    ("ic10", "icon_512x512@2x.png")
]

var entries = Data()
for (type, name) in iconTypes {
    let png = try Data(contentsOf: iconset.appendingPathComponent(name))
    entries.append(type.data(using: .ascii)!)
    var length = UInt32(png.count + 8).bigEndian
    entries.append(Data(bytes: &length, count: 4))
    entries.append(png)
}

var icns = Data()
icns.append("icns".data(using: .ascii)!)
var totalLength = UInt32(entries.count + 8).bigEndian
icns.append(Data(bytes: &totalLength, count: 4))
icns.append(entries)
try icns.write(to: resources.appendingPathComponent("AppIcon.icns"))
