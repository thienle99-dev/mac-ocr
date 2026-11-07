import Foundation
import Vision
import CoreGraphics

struct ScreenCapture {
    let url: URL
    let info: CaptureInfo
}

func captureScreen(region: [Int]?, display: Int?) throws -> ScreenCapture {
    let displayIDs = activeDisplayIDs()
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
    let info = CaptureInfo(displayID: selectedID, x: region.map { CGFloat($0[0]) } ?? bounds.minX,
        y: region.map { CGFloat($0[1]) } ?? bounds.minY,
        scaleX: mode.map { CGFloat($0.pixelWidth) / max(bounds.width, 1) } ?? 1,
        scaleY: mode.map { CGFloat($0.pixelHeight) / max(bounds.height, 1) } ?? 1)
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    var arguments = ["-x", "-t", "png"]
    if let region { arguments += ["-R", region.map(String.init).joined(separator: ",")] }
    if let region { arguments.append("-R\(region.map(String.init).joined(separator: ","))") }
    else { arguments.append("-D\(display ?? 1)") }
    arguments.append(url.path)
    process.arguments = arguments
    do { try process.run(); process.waitUntilExit() }
    catch { throw CLIError.invalid("Screen capture failed. Grant Screen Recording permission to the host app (System Settings > Privacy & Security > Screen Recording).") }
    let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber
    guard process.terminationStatus == 0, (size?.intValue ?? 0) > 0 else {
        throw CLIError.invalid("Screen capture failed. Grant Screen Recording permission to the host app (System Settings > Privacy & Security > Screen Recording).")
    }
    return ScreenCapture(url: url, info: info)
}

func recognizeScreen(region: [Int]?, display: Int?, level: VNRequestTextRecognitionLevel, languages: [String]?, correction: Bool, pixels: Bool) throws -> OCRResult {
    let capture = try captureScreen(region: region, display: display)
    defer { try? FileManager.default.removeItem(at: capture.url) }
    do {
        return try recognizeImageResult(capture.url, level: level, languages: languages, correction: correction, pixels: pixels, capture: capture.info)
    } catch let cliError as CLIError {
        throw cliError
    } catch {
        throw CLIError.invalid("Unable to read or recognize image: \(error.localizedDescription)")
    }
}
