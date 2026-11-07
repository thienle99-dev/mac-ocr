import Foundation
import Vision
import ImageIO

func recognizeImageResult(_ url: URL, level: VNRequestTextRecognitionLevel, languages: [String]?, correction: Bool, pixels: Bool, capture: CaptureInfo? = nil) throws -> OCRResult {
    let lock = try acquireOCRLock(timeout: TimeInterval(ProcessInfo.processInfo.environment["MAC_OCR_QUEUE_TIMEOUT_MS"].flatMap(Int.init) ?? 60_000) / 1000)
    defer { lock.release() }
    let lines = try recognize(url, level: level, correction: correction, languages: languages, pixels: pixels)
    let properties = CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] }
    return OCRResult(text: lines.map(\.text).joined(separator: "\n"),
        width: (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0,
        height: (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0, capture: capture, lines: lines)
}
