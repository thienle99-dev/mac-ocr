import Foundation
import Vision

func recognizeImages(_ input: BatchInput) throws -> BatchResult {
    guard !input.paths.isEmpty, input.paths.count <= 50 else { throw CLIError.usage("Batch accepts 1 to 50 image paths") }
    let level: VNRequestTextRecognitionLevel = input.level == "fast" && !(input.languages ?? []).contains(where: { $0.lowercased().hasPrefix("vi") }) ? .fast : .accurate
    let results = input.paths.map { path -> BatchResultItem in
        do {
            return BatchResultItem(path: path, result: try recognizeImageResult(URL(fileURLWithPath: path).standardizedFileURL, level: level, languages: input.languages, correction: true, pixels: input.pixels ?? false), error: nil)
        } catch {
            return BatchResultItem(path: path, result: nil, error: error.localizedDescription)
        }
    }
    return BatchResult(results: results)
}
