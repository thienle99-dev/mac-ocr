import Foundation
import Vision
import PDFKit
import CoreGraphics
import ImageIO
import Darwin
import AppKit

struct Box: Encodable {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
}

struct OCRLine: Encodable {
    let text: String
    let confidence: Float?
    let box: Box
}

struct OCRResult: Encodable {
    let text: String
    let width: Int
    let height: Int
    var capture: CaptureInfo? = nil
    let lines: [OCRLine]
}
struct CaptureInfo: Encodable {
    let displayID: UInt32
    let x: CGFloat
    let y: CGFloat
    let scaleX: CGFloat
    let scaleY: CGFloat
}

struct BatchItem: Decodable { let path: String }
struct BatchResultItem: Encodable { let path: String; let result: OCRResult?; let error: String? }
struct BatchResult: Encodable { let results: [BatchResultItem] }
struct BatchInput: Decodable { let paths: [String]; let languages: [String]?; let level: String?; let pixels: Bool? }
struct DisplayInfo: Encodable {
    let index: Int
    let displayID: UInt32
    let main: Bool
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
    let pixelWidth: Int
    let pixelHeight: Int
    let scaleX: CGFloat
    let scaleY: CGFloat
}

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

struct OCRPage: Encodable {
    let page: Int
    let width: Int
    let height: Int
    let text: String
    let source: String
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

func recognizeImageResult(_ url: URL, level: VNRequestTextRecognitionLevel, languages: [String]?, correction: Bool, pixels: Bool, capture: CaptureInfo? = nil) throws -> OCRResult {
    let lock = try acquireOCRLock(timeout: TimeInterval(ProcessInfo.processInfo.environment["MAC_OCR_QUEUE_TIMEOUT_MS"].flatMap(Int.init) ?? 60_000) / 1000)
    defer { lock.release() }
    let lines = try recognize(url, level: level, correction: correction, languages: languages, pixels: pixels)
    let properties = CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] }
    return OCRResult(text: lines.map(\.text).joined(separator: "\n"),
        width: (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0,
        height: (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0, capture: capture, lines: lines)
}

func fail(_ message: String, code: Int32) -> Never {
    let data = (try? JSONEncoder().encode(ErrorResult(error: message))) ?? Data("{\"error\":\"OCR failed\"}".utf8)
    FileHandle.standardError.write(data)
    FileHandle.standardError.write(Data("\n".utf8))
    exit(code)
}

func printHelp() {
    print("""
    mac-ocr — local macOS OCR using Apple Vision

    USAGE
      mac-ocr <image-or-pdf> [options]
      mac-ocr --screen [options]
      mac-ocr --batch < input.json
      mac-ocr --list-displays
      mac-ocr configure [claude|codex|opencode]

    OPTIONS
      --lang <codes>       Comma-separated languages, e.g. vi-VN,en-US
      --level <level>      accurate (default) or fast; Vietnamese uses accurate
      --format <format>    json (default) or text
      --pages <range>      PDF pages, e.g. 2 or 1-3
      --force-ocr          Ignore selectable PDF text and run Vision OCR
      --screen             Capture the main display
      --region <rect>      Screen rectangle x,y,width,height in desktop points
      --display <index>    Capture a display index from --list-displays
      --pixels             Return pixel boxes with top-left origin
      --no-correction      Disable Vision language correction
      -h, --help           Show this help

    BATCH INPUT
      JSON object on stdin with paths (1–50 image paths), and optional
      languages, level, and pixels fields.

    MORE
      mac-ocr configure --help
      https://github.com/thienle99-dev/mac-ocr
    """)
}

func printConfigureHelp() {
    print("""
    Configure mac-ocr MCP for coding agents.

    USAGE
      mac-ocr configure [claude|codex|opencode]

    With no agent specified, configures all three. Requires an installed MCP
    bundle from make install or the curl installer, or a built checkout bundle.
    """)
}

func runAgentCommand(_ name: String, _ arguments: [String], allowFailure: Bool = false) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [name] + arguments
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = FileHandle.standardOutput
    process.standardError = FileHandle.standardError
    FileHandle.standardError.write(Data("  Running: \(([name] + arguments).joined(separator: " "))\n".utf8))
    try process.run()
    let timeout = TimeInterval(ProcessInfo.processInfo.environment["MAC_OCR_CONFIG_TIMEOUT_MS"].flatMap(Int.init) ?? 30_000) / 1000
    let deadline = Date().addingTimeInterval(timeout)
    while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
    if process.isRunning {
        kill(process.processIdentifier, SIGTERM)
        Thread.sleep(forTimeInterval: 0.5)
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        process.waitUntilExit()
        throw CLIError.invalid("\(name) command timed out after \(Int(timeout)) seconds")
    }
    process.waitUntilExit()
    if process.terminationStatus != 0 && !allowFailure {
        throw CLIError.invalid("\(name) command failed with status \(process.terminationStatus)")
    }
}

func locateMCPBundle() throws -> (server: URL, opencodeHelper: URL) {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let installedRoot = home.appendingPathComponent(".local/share/mac-ocr")
    let installedServer = installedRoot.appendingPathComponent("mcp/dist/index.js")
    let installedHelper = installedRoot.appendingPathComponent("scripts/register-opencode.mjs")
    var directory = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
    while directory.path != "/" {
        let server = directory.appendingPathComponent("mcp/dist/index.js")
        let helper = directory.appendingPathComponent("scripts/register-opencode.mjs")
        if FileManager.default.fileExists(atPath: server.path), FileManager.default.fileExists(atPath: helper.path) {
            return (server, helper)
        }
        directory.deleteLastPathComponent()
    }
    if FileManager.default.fileExists(atPath: installedServer.path), FileManager.default.fileExists(atPath: installedHelper.path) {
        return (installedServer, installedHelper)
    }
    throw CLIError.invalid("MCP bundle not found. Build it with `make build-mcp` or install it with `make install`.")
}

func configureAgents(_ requested: [String]) throws {
    let allowed = ["claude", "codex", "opencode"]
    guard requested.allSatisfy(allowed.contains) else { throw CLIError.usage("Usage: mac-ocr configure [claude|codex|opencode]") }
    let bundle = try locateMCPBundle()
    let server = bundle.server
    for agent in requested {
        let label = agent == "claude" ? "Claude Code" : agent == "codex" ? "Codex" : "OpenCode"
        FileHandle.standardError.write(Data("Configuring \(label) MCP...\n".utf8))
        switch agent {
        case "claude":
            try runAgentCommand("claude", ["mcp", "remove", "mac-ocr", "--scope", "user"], allowFailure: true)
            try runAgentCommand("claude", ["mcp", "add", "--scope", "user", "mac-ocr", "--", "node", server.path])
        case "codex":
            try runAgentCommand("codex", ["mcp", "remove", "mac-ocr"], allowFailure: true)
            try runAgentCommand("codex", ["mcp", "add", "mac-ocr", "--", "node", server.path])
        case "opencode":
            try runAgentCommand("node", [bundle.opencodeHelper.path, server.path])
        default: break
        }
        FileHandle.standardError.write(Data("Configured \(label) MCP.\n".utf8))
    }
}

do {
    let commandArgs = Array(CommandLine.arguments.dropFirst())
    if commandArgs.isEmpty || ["--help", "-h", "help"].contains(commandArgs[0]) {
        printHelp()
        exit(0)
    }
    if commandArgs.first == "configure" && commandArgs.dropFirst().first.map({ ["--help", "-h"].contains($0) }) == true {
        printConfigureHelp()
        exit(0)
    }
    if commandArgs.first == "configure" {
        let requested = Array(CommandLine.arguments.dropFirst(2))
        try configureAgents(requested.isEmpty ? ["claude", "codex", "opencode"] : requested)
        exit(0)
    }
    if CommandLine.arguments.contains("--batch") {
        let inputData = FileHandle.standardInput.readDataToEndOfFile()
        let input = try JSONDecoder().decode(BatchInput.self, from: inputData)
        guard !input.paths.isEmpty, input.paths.count <= 50 else { throw CLIError.usage("Batch accepts 1 to 50 image paths") }
        let level: VNRequestTextRecognitionLevel = input.level == "fast" && !(input.languages ?? []).contains(where: { $0.lowercased().hasPrefix("vi") }) ? .fast : .accurate
        let results = input.paths.map { path -> BatchResultItem in
            do { return BatchResultItem(path: path, result: try recognizeImageResult(URL(fileURLWithPath: path).standardizedFileURL, level: level, languages: input.languages, correction: true, pixels: input.pixels ?? false), error: nil) }
            catch { return BatchResultItem(path: path, result: nil, error: error.localizedDescription) }
        }
        let data = try JSONEncoder().encode(BatchResult(results: results)); FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data("\n".utf8)); exit(0)
    }
    var positional: String?
    var languages: [String]?
    var level = VNRequestTextRecognitionLevel.accurate
    var format = "json"
    var correction = true
    var screen = false
    var pixels = false
    var region: [Int]?
    var display: Int?
    var listDisplays = false
    var pageRange: ClosedRange<Int>?
    var forceOCR = false
    var index = 1
    let args = CommandLine.arguments

    while index < args.count {
        let arg = args[index]
        switch arg {
        case "--lang", "--level", "--format", "--pages", "--region", "--display":
            guard index + 1 < args.count else { throw CLIError.usage("Missing value for \(arg)") }
            let value = args[index + 1]
            switch arg {
            case "--lang": languages = value.split(separator: ",").map(String.init)
            case "--region":
                let values = value.split(separator: ",").compactMap { Int($0) }
                guard values.count == 4, values[2] > 0, values[3] > 0 else { throw CLIError.usage("--region must be x,y,width,height with positive dimensions") }
                region = values
            case "--display":
                guard let value = Int(value), value > 0 else { throw CLIError.usage("--display must be a positive display index") }
                display = value
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
        case "--force-ocr":
            forceOCR = true
            index += 1
        case "--screen":
            screen = true
            index += 1
        case "--pixels":
            pixels = true
            index += 1
        case "--list-displays":
            listDisplays = true
            index += 1
        default:
            guard !arg.hasPrefix("--"), positional == nil else { throw CLIError.usage("Usage: mac-ocr <image-or-pdf> [--lang vi-VN,en-US] [--level accurate|fast] [--format json|text] [--pages 1-3] [--force-ocr] [--screen] [--region x,y,w,h] [--display n] [--pixels] [--no-correction]") }
            positional = arg
            index += 1
        }
    }

    let usage = "Usage: mac-ocr <image-or-pdf> [--lang vi-VN,en-US] [--level accurate|fast] [--format json|text] [--pages 1-3] [--force-ocr] [--screen] [--region x,y,w,h] [--display n] [--pixels] [--no-correction]"
    if listDisplays {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = Array(repeating: CGDirectDisplayID(), count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        ids = ids.filter { CGDisplayIsInMirrorSet($0) == 0 || CGDisplayIsMain($0) != 0 }
        ids.sort { CGDisplayIsMain($0) != 0 && CGDisplayIsMain($1) == 0 }
        let displays = ids.enumerated().map { offset, id -> DisplayInfo in
            let bounds = CGDisplayBounds(id)
            let mode = CGDisplayCopyDisplayMode(id)
            return DisplayInfo(index: offset + 1, displayID: id, main: CGDisplayIsMain(id) != 0, x: bounds.origin.x, y: bounds.origin.y,
                width: bounds.width, height: bounds.height, pixelWidth: mode.map { $0.pixelWidth } ?? 0,
                pixelHeight: mode.map { $0.pixelHeight } ?? 0,
                scaleX: mode.map { CGFloat($0.pixelWidth) / max(bounds.width, 1) } ?? 1,
                scaleY: mode.map { CGFloat($0.pixelHeight) / max(bounds.height, 1) } ?? 1)
        }
        let data = try JSONEncoder().encode(displays); FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data("\n".utf8)); exit(0)
    }
    if let languages, languages.contains(where: { $0.lowercased().hasPrefix("vi") }), level == .fast { level = .accurate }
    if (region != nil || display != nil) && !screen { throw CLIError.usage("--region and --display require --screen") }
    if region != nil && display != nil { throw CLIError.usage("--region and --display cannot be combined") }
    if screen && positional != nil { throw CLIError.usage("--screen cannot be used with an image path") }
    if screen && pageRange != nil { throw CLIError.usage("--pages can only be used with a PDF") }
    if !screen && positional == nil { throw CLIError.usage(usage) }
    var capturedURL: URL?
    var captureInfo: CaptureInfo?
    defer { if let capturedURL { try? FileManager.default.removeItem(at: capturedURL) } }
    if screen {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var displayIDs = Array(repeating: CGDirectDisplayID(), count: Int(count))
        CGGetActiveDisplayList(count, &displayIDs, &count)
        displayIDs = displayIDs.filter { CGDisplayIsInMirrorSet($0) == 0 || CGDisplayIsMain($0) != 0 }
        displayIDs.sort { CGDisplayIsMain($0) != 0 && CGDisplayIsMain($1) == 0 }
        let selectedID: CGDirectDisplayID
        if let display {
            guard display <= displayIDs.count else { throw CLIError.invalid("Display index is out of range") }
            selectedID = displayIDs[display - 1]
        } else if let region {
            let rect = CGRect(x: region[0], y: region[1], width: region[2], height: region[3])
            guard let match = displayIDs.first(where: { CGDisplayBounds($0).contains(rect) }) else {
                throw CLIError.invalid("Capture region must fit entirely within one active display")
            }
            selectedID = match
        } else {
            selectedID = CGMainDisplayID()
        }
        let bounds = CGDisplayBounds(selectedID)
        let mode = CGDisplayCopyDisplayMode(selectedID)
        captureInfo = CaptureInfo(displayID: selectedID, x: region.map { CGFloat($0[0]) } ?? bounds.minX,
            y: region.map { CGFloat($0[1]) } ?? bounds.minY,
            scaleX: mode.map { CGFloat($0.pixelWidth) / max(bounds.width, 1) } ?? 1,
            scaleY: mode.map { CGFloat($0.pixelHeight) / max(bounds.height, 1) } ?? 1)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
        capturedURL = tempURL
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        var captureArguments = ["-x", "-t", "png"]
        if let region { captureArguments += ["-R", region.map(String.init).joined(separator: ",")] }
        if let region { captureArguments.append("-R\(region.map(String.init).joined(separator: ","))") }
        else { captureArguments.append("-D\(display ?? 1)") }
        captureArguments.append(tempURL.path)
        process.arguments = captureArguments
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
    if forceOCR && !isPDF { throw CLIError.usage("--force-ocr can only be used with a PDF") }
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
        let result: OCRResult
        do { result = try recognizeImageResult(imageURL, level: level, languages: languages, correction: correction, pixels: pixels, capture: captureInfo) }
        catch let cliError as CLIError { throw cliError }
        catch { throw CLIError.invalid("Unable to read or recognize image: \(error.localizedDescription)") }
        if format == "text" { print(result.text) } else {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(result); FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data("\n".utf8))
        }
    }
} catch {
    let cliError = error as? CLIError
    fail(error.localizedDescription, code: cliError == nil ? 1 : 2)
}
