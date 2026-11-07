import Foundation
import Vision
import Darwin

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
        let result = try recognizeImages(input)
        let data = try JSONEncoder().encode(result)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
        exit(0)
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
        let data = try JSONEncoder().encode(activeDisplayInfos())
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
        exit(0)
    }
    if forceOCR && (screen || URL(fileURLWithPath: positional ?? "").pathExtension.lowercased() != "pdf") {
        throw CLIError.usage("--force-ocr can only be used with a PDF")
    }
    if let languages, languages.contains(where: { $0.lowercased().hasPrefix("vi") }), level == .fast { level = .accurate }
    if (region != nil || display != nil) && !screen { throw CLIError.usage("--region and --display require --screen") }
    if region != nil && display != nil { throw CLIError.usage("--region and --display cannot be combined") }
    if screen && positional != nil { throw CLIError.usage("--screen cannot be used with an image path") }
    if screen && pageRange != nil { throw CLIError.usage("--pages can only be used with a PDF") }
    if !screen && positional == nil { throw CLIError.usage(usage) }
    if screen {
        let result = try recognizeScreen(region: region, display: display, level: level, languages: languages, correction: correction, pixels: pixels)
        if format == "text" { print(result.text) } else {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(result); FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data("\n".utf8))
        }
        exit(0)
    }
    guard let path = positional else { throw CLIError.usage(usage) }
    let imageURL = URL(fileURLWithPath: path).standardizedFileURL
    var isDirectory: ObjCBool = false
    let isPDF = imageURL.pathExtension.lowercased() == "pdf"
    if isPDF {
        let result = try recognizePDF(imageURL, pageRange: pageRange, forceOCR: forceOCR, level: level, correction: correction, languages: languages, pixels: pixels)
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
        do { result = try recognizeImageResult(imageURL, level: level, languages: languages, correction: correction, pixels: pixels) }
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
