import Foundation
import Vision
import PDFKit
import CoreGraphics
import Darwin

func render(_ page: PDFPage) throws -> CGImage {
    let bounds = page.bounds(for: .mediaBox)
    let width = Int(ceil(bounds.width * 2))
    let height = Int(ceil(bounds.height * 2))
    guard width > 0, height > 0,
          let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw CLIError.invalid("Unable to render PDF page")
    }
    context.setFillColor(gray: 1, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.scaleBy(x: 2, y: 2)
    page.draw(with: .mediaBox, to: context)
    guard let image = context.makeImage() else { throw CLIError.invalid("Unable to render PDF page") }
    return image
}

func embeddedPDFText(_ page: PDFPage, pixels: Bool) -> (text: String, lines: [OCRLine])? {
    guard let text = page.string,
          text.unicodeScalars.contains(where: CharacterSet.alphanumerics.contains),
          let selection = page.selection(for: page.bounds(for: .mediaBox)) else { return nil }

    let bounds = page.bounds(for: .mediaBox)
    guard bounds.width > 0, bounds.height > 0 else { return nil }
    let width = Int(ceil(bounds.width * 2))
    let height = Int(ceil(bounds.height * 2))
    let lines = selection.selectionsByLine().compactMap { item -> OCRLine? in
        guard let value = item.string?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        let rect = item.bounds(for: page)
        guard rect.width > 0, rect.height > 0 else { return nil }
        let x = (rect.minX - bounds.minX) / bounds.width
        let y = (rect.minY - bounds.minY) / bounds.height
        let w = rect.width / bounds.width
        let h = rect.height / bounds.height
        let box = pixels
            ? Box(x: x * CGFloat(width), y: (1 - y - h) * CGFloat(height), width: w * CGFloat(width), height: h * CGFloat(height))
            : Box(x: x, y: y, width: w, height: h)
        return OCRLine(text: value, confidence: nil, box: box)
    }
    guard !lines.isEmpty else { return nil }
    return (text, lines)
}

func pdfReadingOrder(_ lines: [OCRLine], pixels: Bool, width: Int, height: Int) -> [OCRLine] {
    guard lines.count >= 7 else { return lines }

    func geometry(_ line: OCRLine) -> (top: CGFloat, center: CGFloat, height: CGFloat, x: CGFloat) {
        let box = line.box
        let normalizedHeight = pixels ? box.height / CGFloat(max(height, 1)) : box.height
        let top = pixels ? box.y / CGFloat(max(height, 1)) : 1 - box.y - box.height
        let x = pixels ? box.x / CGFloat(max(width, 1)) : box.x
        return (top, top + normalizedHeight / 2, normalizedHeight, x)
    }

    let ordered = lines.sorted { geometry($0).center < geometry($1).center }
    var rows: [[OCRLine]] = []
    for line in ordered {
        let current = geometry(line)
        if let last = rows.indices.last {
            let previous = rows[last].map(geometry)
            let center = previous.map(\.center).reduce(0, +) / CGFloat(previous.count)
            let height = max(current.height, previous.map(\.height).max() ?? current.height)
            if abs(current.center - center) <= max(0.004, height * 0.55) {
                rows[last].append(line)
                continue
            }
        }
        rows.append([line])
    }

    let multiLineRows = rows.filter { $0.count >= 2 }.count
    let xPositions = lines.map { geometry($0).x }.sorted()
    var xClusters: [CGFloat] = []
    for x in xPositions {
        if let previous = xClusters.last, abs(x - previous) < 0.035 { continue }
        xClusters.append(x)
    }
    let horizontalSpan = (xPositions.last ?? 0) - (xPositions.first ?? 0)
    // Row-wise order helps compact tables; keep Vision's order on wide pages to avoid interleaving columns.
    guard multiLineRows >= 3, xClusters.count >= 3, horizontalSpan <= 0.65 else { return lines }

    return rows.flatMap { row in row.sorted { geometry($0).x < geometry($1).x } }
}

func recognizePDF(_ url: URL, pageRange: ClosedRange<Int>?, forceOCR: Bool, level: VNRequestTextRecognitionLevel, correction: Bool, languages: [String]?, pixels: Bool) throws -> OCRDocumentResult {
    guard let document = PDFDocument(url: url) else { throw CLIError.invalid("Unable to open PDF: \(url.path)") }
    let total = document.pageCount
    if let pageRange, pageRange.lowerBound < 1 || pageRange.upperBound > total {
        throw CLIError.invalid("PDF page range is out of range (document has \(total) pages)")
    }
    let selected = pageRange.map { Array($0) } ?? (total > 0 ? Array(1...total) : [])
    var pages: [OCRPage] = []
    for number in selected {
        // Release each page's rendered bitmap before the next one to keep memory flat on long PDFs.
        let ocrPage = try autoreleasepool { () throws -> OCRPage in
            guard let page = document.page(at: number - 1) else { throw CLIError.invalid("Unable to read PDF page \(number)") }
            let bounds = page.bounds(for: .mediaBox)
            let width = Int(ceil(bounds.width * 2))
            let height = Int(ceil(bounds.height * 2))
            if !forceOCR, let embedded = embeddedPDFText(page, pixels: pixels) {
                return OCRPage(page: number, width: width, height: height, text: embedded.text, source: "pdf-text", lines: embedded.lines)
            }

            let lock = try acquireOCRLock(timeout: TimeInterval(ProcessInfo.processInfo.environment["MAC_OCR_QUEUE_TIMEOUT_MS"].flatMap(Int.init) ?? 60_000) / 1000)
            defer { lock.release() }
            let cgImage = try render(page)
            let recognized = try recognize(cgImage, level: level, correction: correction, languages: languages, pixels: pixels)
            let lines = pdfReadingOrder(recognized, pixels: pixels, width: cgImage.width, height: cgImage.height)
            return OCRPage(page: number, width: cgImage.width, height: cgImage.height, text: lines.map(\.text).joined(separator: "\n"), source: "vision", lines: lines)
        }
        pages.append(ocrPage)
    }
    return OCRDocumentResult(text: pages.map(\.text).joined(separator: "\n\n"), pages: pages)
}
