import AppKit

let destination = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let unit = CGFloat(pixels) / 1024
        let transform = NSAffineTransform()
        transform.scale(by: unit)
        transform.concat()
        let background = NSBezierPath(roundedRect: NSRect(x: 40, y: 40, width: 944, height: 944), xRadius: 220, yRadius: 220)
        NSColor(calibratedRed: 0.12, green: 0.46, blue: 0.39, alpha: 1).setFill()
        background.fill()
        NSColor.white.setStroke()
        let body = NSBezierPath()
        body.lineWidth = 48
        body.lineCapStyle = .round
        body.lineJoinStyle = .round
        body.move(to: NSPoint(x: 630, y: 645))
        body.line(to: NSPoint(x: 630, y: 455))
        body.line(to: NSPoint(x: 560, y: 260))
        body.move(to: NSPoint(x: 630, y: 455))
        body.line(to: NSPoint(x: 715, y: 260))
        body.move(to: NSPoint(x: 630, y: 610))
        body.line(to: NSPoint(x: 540, y: 495))
        body.move(to: NSPoint(x: 630, y: 610))
        body.line(to: NSPoint(x: 735, y: 515))
        body.stroke()
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: 586, y: 700, width: 88, height: 88)).fill()
        let chair = NSBezierPath()
        chair.lineWidth = 45
        chair.lineCapStyle = .round
        chair.lineJoinStyle = .round
        chair.move(to: NSPoint(x: 285, y: 590))
        chair.line(to: NSPoint(x: 285, y: 420))
        chair.line(to: NSPoint(x: 440, y: 420))
        chair.move(to: NSPoint(x: 305, y: 420))
        chair.line(to: NSPoint(x: 305, y: 260))
        chair.move(to: NSPoint(x: 425, y: 420))
        chair.line(to: NSPoint(x: 425, y: 260))
        chair.stroke()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: destination).appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
