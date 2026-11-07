import CoreGraphics
import CoreText
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: mk-text-pdf.swift <output.pdf>\n", stderr)
    exit(2)
}

let output = URL(fileURLWithPath: CommandLine.arguments[1])
var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
guard let consumer = CGDataConsumer(url: output as CFURL),
      let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
    fputs("Unable to create PDF context\n", stderr)
    exit(1)
}

context.beginPage(mediaBox: &mediaBox)
let font = CTFontCreateWithName("Helvetica" as CFString, 24, nil)
let attributes = [kCTFontAttributeName: font] as CFDictionary
for (text, y) in [("Selectable PDF text layer", 720.0), ("Revenue: $1,240.50", 670.0)] {
    guard let attributed = CFAttributedStringCreate(kCFAllocatorDefault, text as CFString, attributes) else { continue }
    let line = CTLineCreateWithAttributedString(attributed)
    context.textPosition = CGPoint(x: 48, y: y)
    CTLineDraw(line, context)
}
context.endPage()
context.closePDF()
