import Foundation
import Vision
import PDFKit
import CoreGraphics

struct Box: Encodable {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
}

struct OCRLine: Encodable {
    let text: String
    let confidence: Float
    let box: Box
}

struct OCRResult: Encodable {
    let text: String
    let lines: [OCRLine]
}

struct OCRPage: Encodable {
    let page: Int
    let text: String
    let lines: [OCRLine]
}

struct OCRDocumentResult: Encodable {
    let text: String
    let pages: [OCRPage]
}

struct ErrorResult: Encodable {
    let error: String
}

enum CLIError: LocalizedError {
    case usage(String)
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .usage(let message), .invalid(let message): message
        }
    }
}

func recognize(_ perform: (VNRecognizeTextRequest) throws -> Void, level: VNRequestTextRecognitionLevel, correction: Bool, languages: [String]?) throws -> [OCRLine] {
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
        return OCRLine(text: candidate.string, confidence: candidate.confidence,
                       box: Box(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: rect.height))
    }
}

func recognize(_ image: CGImage, level: VNRequestTextRecognitionLevel, correction: Bool, languages: [String]?) throws -> [OCRLine] {
    try recognize({ try VNImageRequestHandler(cgImage: image).perform([$0]) }, level: level, correction: correction, languages: languages)
}

func recognize(_ url: URL, level: VNRequestTextRecognitionLevel, correction: Bool, languages: [String]?) throws -> [OCRLine] {
    try recognize({ try VNImageRequestHandler(url: url).perform([$0]) }, level: level, correction: correction, languages: languages)
}

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

func fail(_ message: String, code: Int32) -> Never {
    let data = (try? JSONEncoder().encode(ErrorResult(error: message))) ?? Data("{\"error\":\"OCR failed\"}".utf8)
    FileHandle.standardError.write(data)
    FileHandle.standardError.write(Data("\n".utf8))
    exit(code)
}

do {
    var positional: String?
    var languages: [String]?
    var level = VNRequestTextRecognitionLevel.accurate
    var format = "json"
    var correction = true
    var screen = false
    var pageRange: ClosedRange<Int>?
    var index = 1
    let args = CommandLine.arguments

    while index < args.count {
        let arg = args[index]
        switch arg {
        case "--lang", "--level", "--format", "--pages":
            guard index + 1 < args.count else { throw CLIError.usage("Missing value for \(arg)") }
            let value = args[index + 1]
            switch arg {
            case "--lang": languages = value.split(separator: ",").map(String.init)
            case "--level":
                switch value {
                case "accurate": level = .accurate
                case "fast": level = .fast
                default: throw CLIError.usage("--level must be accurate or fast")
                }
            default:
                if arg == "--format" {
                    guard value == "json" || value == "text" else { throw CLIError.usage("--format must be json or text") }
                    format = value
                } else {
                    let parts = value.split(separator: "-", omittingEmptySubsequences: false)
                    let bounds = parts.count == 1 ? [parts[0], parts[0]] : parts
                    guard bounds.count == 2, let first = Int(bounds[0]), let last = Int(bounds[1]), first > 0, last >= first else {
                        throw CLIError.usage("--pages must be a page number or 1-based inclusive range such as 2 or 1-3")
                    }
                    pageRange = first...last
                }
            }
            index += 2
        case "--no-correction":
            correction = false
            index += 1
        case "--screen":
            screen = true
            index += 1
        default:
            guard !arg.hasPrefix("--"), positional == nil else { throw CLIError.usage("Usage: mac-ocr <image> [--lang vi-VN,en-US] [--level accurate|fast] [--format json|text] [--pages 1-3] [--screen] [--no-correction]") }
            positional = arg
            index += 1
        }
    }

    let usage = "Usage: mac-ocr <image> [--lang vi-VN,en-US] [--level accurate|fast] [--format json|text] [--pages 1-3] [--screen] [--no-correction]"
    if screen && positional != nil { throw CLIError.usage("--screen cannot be used with an image path") }
    if screen && pageRange != nil { throw CLIError.usage("--pages can only be used with a PDF") }
    if !screen && positional == nil { throw CLIError.usage(usage) }
    var capturedURL: URL?
    defer { if let capturedURL { try? FileManager.default.removeItem(at: capturedURL) } }
    if screen {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
        capturedURL = tempURL
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-t", "png", tempURL.path]
        do { try process.run(); process.waitUntilExit() } catch { throw CLIError.invalid("Screen capture failed. Grant Screen Recording permission to the host app (System Settings > Privacy & Security > Screen Recording).") }
        let size = (try? FileManager.default.attributesOfItem(atPath: tempURL.path))?[.size] as? NSNumber
        guard process.terminationStatus == 0, (size?.intValue ?? 0) > 0 else {
            throw CLIError.invalid("Screen capture failed. Grant Screen Recording permission to the host app (System Settings > Privacy & Security > Screen Recording).")
        }
    }
    let imageURL: URL
    if let capturedURL { imageURL = capturedURL } else {
        guard let path = positional else { throw CLIError.usage(usage) }
        imageURL = URL(fileURLWithPath: path).standardizedFileURL
    }
    var isDirectory: ObjCBool = false
    let isPDF = !screen && imageURL.pathExtension.lowercased() == "pdf"
    if isPDF {
        guard let document = PDFDocument(url: imageURL) else { throw CLIError.invalid("Unable to open PDF: \(imageURL.path)") }
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
                let cgImage = try render(page)
                let lines = try recognize(cgImage, level: level, correction: correction, languages: languages)
                return OCRPage(page: number, text: lines.map(\.text).joined(separator: "\n"), lines: lines)
            }
            pages.append(ocrPage)
        }
        let result = OCRDocumentResult(text: pages.map(\.text).joined(separator: "\n\n"), pages: pages)
        if format == "text" { print(result.text) } else {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(result); FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data("\n".utf8))
        }
    } else {
        if pageRange != nil { throw CLIError.invalid("--pages can only be used with a PDF") }
        let imagePath = positional ?? imageURL.path
        guard FileManager.default.fileExists(atPath: imageURL.path, isDirectory: &isDirectory) else { throw CLIError.invalid("Image file does not exist: \(imagePath)") }
        guard !isDirectory.boolValue else { throw CLIError.invalid("Image path is not a file: \(imagePath)") }
        let lines: [OCRLine]
        do { lines = try recognize(imageURL, level: level, correction: correction, languages: languages) }
        catch let cliError as CLIError { throw cliError }
        catch { throw CLIError.invalid("Unable to read or recognize image: \(error.localizedDescription)") }
        let result = OCRResult(text: lines.map(\.text).joined(separator: "\n"), lines: lines)
        if format == "text" { print(result.text) } else {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(result); FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data("\n".utf8))
        }
    }
} catch {
    let cliError = error as? CLIError
    fail(error.localizedDescription, code: cliError == nil ? 1 : 2)
}
