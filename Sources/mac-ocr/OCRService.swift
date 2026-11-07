import Foundation
import Vision
import CoreGraphics
import ImageIO
import Darwin

struct OCRLock {
    let descriptor: Int32
    func release() { flock(descriptor, LOCK_UN); close(descriptor) }
}

func acquireOCRLock(timeout: TimeInterval) throws -> OCRLock {
    let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/mac-ocr/locks")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    chmod(root.path, 0o700)
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        for slot in 0..<4 {
            let fd = open(root.appendingPathComponent("slot-\(slot).lock").path, O_CREAT | O_RDWR, 0o600)
            guard fd >= 0 else { continue }
            if flock(fd, LOCK_EX | LOCK_NB) == 0 { return OCRLock(descriptor: fd) }
            close(fd)
        }
        Thread.sleep(forTimeInterval: 0.05)
    }
    throw CLIError.invalid("Timed out waiting for an OCR slot")
}

func recognize(_ perform: (VNRecognizeTextRequest) throws -> Void, level: VNRequestTextRecognitionLevel, correction: Bool, languages: [String]?, pixels: CGSize? = nil) throws -> [OCRLine] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = level
    request.usesLanguageCorrection = correction
    if let languages {
        guard !languages.isEmpty else { throw CLIError.invalid("At least one language is required") }
        let supported = try request.supportedRecognitionLanguages()
        let normalizedLanguages = languages.map { $0 == "vi-VN" && supported.contains("vi-VT") ? "vi-VT" : $0 }
        let unsupported = normalizedLanguages.filter { !supported.contains($0) }
        guard unsupported.isEmpty else { throw CLIError.invalid("Unsupported recognition language(s): \(unsupported.joined(separator: ", "))") }
        request.recognitionLanguages = normalizedLanguages
    }
    try perform(request)
    return (request.results ?? []).compactMap { observation -> OCRLine? in
        guard let candidate = observation.topCandidates(1).first else { return nil }
        let rect = observation.boundingBox
        let box: Box
        if let pixels {
            box = Box(x: rect.minX * pixels.width, y: (1 - rect.maxY) * pixels.height,
                      width: rect.width * pixels.width, height: rect.height * pixels.height)
        } else {
            box = Box(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: rect.height)
        }
        return OCRLine(text: candidate.string, confidence: candidate.confidence, box: box)
    }
}

func recognize(_ image: CGImage, level: VNRequestTextRecognitionLevel, correction: Bool, languages: [String]?, pixels: Bool = false) throws -> [OCRLine] {
    try recognize({ try VNImageRequestHandler(cgImage: image).perform([$0]) }, level: level, correction: correction, languages: languages, pixels: pixels ? CGSize(width: image.width, height: image.height) : nil)
}

func recognize(_ url: URL, level: VNRequestTextRecognitionLevel, correction: Bool, languages: [String]?, pixels: Bool = false) throws -> [OCRLine] {
    let source = CGImageSourceCreateWithURL(url as CFURL, nil)
    let properties = source.flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] }
    let size = properties.flatMap { props -> CGSize? in
        guard let width = props[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = props[kCGImagePropertyPixelHeight] as? CGFloat else { return nil }
        return CGSize(width: width, height: height)
    }
    return try recognize({ try VNImageRequestHandler(url: url).perform([$0]) }, level: level, correction: correction, languages: languages, pixels: pixels ? size : nil)
}
