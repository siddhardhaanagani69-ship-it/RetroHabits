import AppKit
// Renders the 1024 px app icon: a check at the center of ripple rings.
// usage: swift scripts/app-icon.swift <out.png> light|dark   (writes a 1024 px AppIcon)
let out = CommandLine.arguments[1], dark = CommandLine.arguments[2] == "dark"
let size = 1024
// App Store icons can't have an alpha channel: draw into an RGB context that skips it.
let cg = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                   space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: false)
let rect = NSRect(x: 0, y: 0, width: size, height: size)
let rgb = { (r: CGFloat, g: CGFloat, b: CGFloat) in NSColor(deviceRed: r / 255, green: g / 255, blue: b / 255, alpha: 1) }

// Background
let bg = dark ? NSGradient(starting: rgb(44, 44, 48), ending: rgb(10, 10, 12))!
              : NSGradient(starting: rgb(90, 150, 255), ending: rgb(30, 90, 230))!
bg.draw(in: rect, angle: -90)

// Ripple rings
let center = NSPoint(x: 512, y: 512)
let ringColor = dark ? rgb(64, 140, 255) : NSColor.white
for (radius, alpha) in [(430.0, 0.14), (345.0, 0.24), (262.0, 0.36)] as [(CGFloat, CGFloat)] {
    let ring = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    ring.lineWidth = 34
    ringColor.withAlphaComponent(alpha).setStroke()
    ring.stroke()
}

// Center disc + check
let disc: CGFloat = 190
(dark ? rgb(64, 140, 255) : NSColor.white).setFill()
NSBezierPath(ovalIn: NSRect(x: center.x - disc, y: center.y - disc, width: disc * 2, height: disc * 2)).fill()
let check = NSBezierPath()
check.move(to: NSPoint(x: 425, y: 515))
check.line(to: NSPoint(x: 490, y: 448))
check.line(to: NSPoint(x: 610, y: 585))
check.lineWidth = 58
check.lineCapStyle = .round
check.lineJoinStyle = .round
(dark ? NSColor.white : rgb(30, 90, 230)).setStroke()
check.stroke()

NSGraphicsContext.restoreGraphicsState()
let rep = NSBitmapImageRep(cgImage: cg.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
