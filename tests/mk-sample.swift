import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: mk-sample.swift <output.png>\n", stderr)
    exit(2)
}

let size = NSSize(width: 900, height: 180)
let image = NSImage(size: size)
image.lockFocus()
NSColor.white.setFill()
NSRect(origin: .zero, size: size).fill()

let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 48),
    .foregroundColor: NSColor.black,
]
("Hello World 2026" as NSString).draw(at: NSPoint(x: 24, y: 100), withAttributes: attributes)
("Xin chào Việt Nam, học máy" as NSString).draw(at: NSPoint(x: 24, y: 35), withAttributes: attributes)
image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Unable to render sample image\n", stderr)
    exit(1)
}

do {
    try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
} catch {
    fputs("Unable to write sample image: \(error.localizedDescription)\n", stderr)
    exit(1)
}
