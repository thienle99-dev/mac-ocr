import Foundation
import CoreGraphics

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
