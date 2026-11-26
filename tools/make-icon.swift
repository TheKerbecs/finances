// swift tools/make-icon.swift out.png — draws the 1024 px app icon.
import AppKit

let size = 1024.0
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
let inset = 100.0, r = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let bg = NSBezierPath(roundedRect: r, xRadius: 185, yRadius: 185)
NSGradient(starting: NSColor(red: 0.07, green: 0.20, blue: 0.17, alpha: 1),
           ending: NSColor(red: 0.04, green: 0.11, blue: 0.10, alpha: 1))!.draw(in: bg, angle: -90)
// three bars
let bars: [(Double, Double)] = [(0.30, 0.28), (0.47, 0.42), (0.64, 0.58)]
NSColor(red: 0.36, green: 0.85, blue: 0.62, alpha: 0.35).setFill()
for (x, h) in bars {
    NSBezierPath(roundedRect: NSRect(x: size * x - 50, y: 250, width: 100, height: size * h), xRadius: 24, yRadius: 24).fill()
}
// rising line
let line = NSBezierPath()
line.move(to: NSPoint(x: 230, y: 360)); line.line(to: NSPoint(x: 420, y: 520))
line.line(to: NSPoint(x: 560, y: 470)); line.line(to: NSPoint(x: 790, y: 760))
line.lineWidth = 46; line.lineCapStyle = .round; line.lineJoinStyle = .round
NSColor(red: 0.45, green: 0.95, blue: 0.70, alpha: 1).setStroke()
line.stroke()
img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
