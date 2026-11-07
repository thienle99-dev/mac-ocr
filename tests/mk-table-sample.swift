import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: mk-table-sample.swift <output.png>\n", stderr)
    exit(2)
}

let size = NSSize(width: 900, height: 500)
let image = NSImage(size: size)
image.lockFocus()
NSColor.white.setFill()
NSRect(origin: .zero, size: size).fill()
let rows: [(CGFloat, [(CGFloat, String)])] = [
    (405, [(24, "Item"), (200, "Qty"), (310, "Unit price"), (540, "Total")]),
    (345, [(24, "USB-C Dock"), (200, "2"), (310, "89.95"), (540, "179.90")]),
    (285, [(24, "VAT (10%)"), (540, "17.99")]),
    (225, [(24, "TOTAL"), (540, "197.89")]),
]
for (y, items) in rows {
    for (x, text) in items {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 28), .foregroundColor: NSColor.black]
        (text as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: attrs)
    }
}
image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Unable to encode sample table image\n", stderr)
    exit(1)
}
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
