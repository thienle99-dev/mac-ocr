# mac-ocr

Local OCR for AI agents on macOS. The Swift command line program uses Apple Vision; the MCP server exposes it as an `ocr_image` tool. No OCR model or network service is used at runtime.

## Requirements

- macOS 12 or later
- Swift 6 toolchain
- Node.js 18 or later and pnpm

## Build

From this directory:

```sh
make build
```

This runs the manual build steps below, using the frozen MCP lockfile:

```sh
swift build -c release
pnpm --dir mcp install --frozen-lockfile
pnpm --dir mcp build
```

The executable is `.build/release/mac-ocr`.

## Test

Run the smoke checks and MCP typecheck with:

```sh
make test
```

The manual smoke test command, after `swift build -c release`, is:

```sh
bash tests/smoke.sh
```

## CLI

```sh
.build/release/mac-ocr ./image.png
.build/release/mac-ocr ./image.png --lang vi-VN,en-US --level accurate
.build/release/mac-ocr ./image.png --format text --no-correction
.build/release/mac-ocr ./document.pdf --pages 1-3
.build/release/mac-ocr --screen --format text
```

Options:

- `--lang`: comma-separated Vision recognition language identifiers. The CLI accepts `vi-VN` as an alias for Vision's `vi-VT` identifier when the latter is available. Supported languages vary by macOS version and recognition level.
- `--level`: `accurate` (default) or `fast`.
- `--format`: `json` (default) or `text`.
- `--pages`: 1-based inclusive PDF page range, such as `1-3`; defaults to all pages.
- `--screen`: capture the main display and recognize it. Do not provide an image path with this flag. The host app must have Screen Recording permission in System Settings > Privacy & Security > Screen Recording.
- `--no-correction`: disable Vision language correction.

**Tips:** Use `--level accurate` (the default), especially for Vietnamese or other text with diacritics; `fast` may drop them (for example, "Xin chao Vièt Nam, hoc may"). For Vietnamese and English, pass `--lang vi-VN,en-US`.

Image and screenshot JSON output has `text` and `lines`. PDF JSON output has `text` and `pages`, with each page containing its 1-based `page`, `text`, and `lines`. Each line contains recognized `text`, a confidence score, and a normalized `box` (`x`, `y`, `width`, `height`). Coordinates range from 0 to 1, with the origin at the bottom left, matching Vision's coordinate system. Errors are JSON on stderr and return a nonzero exit status.

## MCP server

```sh
cd mcp
pnpm install
pnpm build
pnpm start
```

The `ocr_image` tool accepts `path`, optional `languages` (string array), and optional `level` (`accurate` or `fast`). The `ocr_pdf` tool accepts the same options plus optional `pages` (for example, `"1-3"`). The `ocr_screen` tool accepts `languages` and `level`; grant the host app Screen Recording permission in System Settings > Privacy & Security > Screen Recording. Configure the server with these environment variables:

- `MAC_OCR_BIN`: path to the release binary; defaults to `.build/release/mac-ocr` in the project root.
- `MAC_OCR_TIMEOUT_MS`: maximum OCR process time in milliseconds; defaults to `60000`. Values must be positive integers.
- `MAC_OCR_LANGS`: default comma-separated recognition languages (for example, `vi-VN,en-US`); an explicit `languages` tool argument takes precedence.

Register it with Claude Code:

```sh
make register
```

This prints the Claude Code and Codex registration commands for this checkout. The manual Claude Code command is:

```sh
claude mcp add mac-ocr -- node /absolute/path/to/mac-ocr/mcp/dist/index.js
```

Register it with Codex:

```sh
codex mcp add mac-ocr -- node /absolute/path/to/mac-ocr/mcp/dist/index.js
```

This writes the following entry to `~/.codex/config.toml`, which you can also add by hand:

```toml
[mcp_servers.mac-ocr]
command = "node"
args = ["/absolute/path/to/mac-ocr/mcp/dist/index.js"]
```

Build the Swift executable before starting the server.
