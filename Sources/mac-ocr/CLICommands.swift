import Foundation
import Darwin

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
