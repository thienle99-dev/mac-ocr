# mac-ocr

Local OCR for AI agents on macOS. The CLI uses Apple Vision, and the MCP server exposes image, PDF, batch, and screen OCR tools. Recognition runs on-device.

## Install

Install the CLI and register the MCP server for Claude Code, Codex, and OpenCode with one command:

```sh
curl -fsSL https://raw.githubusercontent.com/thienle99-dev/mac-ocr/main/install.sh | sh
```

The installer finds the latest GitHub Release, downloads its matching source and prebuilt universal Swift binary, verifies the binary checksum, builds the MCP server, and installs everything under `~/.local/share/mac-ocr`. It creates `~/.local/bin/mac-ocr` and configures all three agents to use the installed server. The install works independently of the temporary download.

To update, run the same command again. From a local checkout, use `make install` to build and refresh the installed copy. Both methods update the `mac-ocr` entry while preserving other MCP server entries.

To install only the prebuilt CLI, download the universal macOS binary from [GitHub Releases](https://github.com/thienle99-dev/mac-ocr/releases/latest), then:

```sh
tar -xzf mac-ocr-macos-universal.tar.gz
install -m 755 mac-ocr "$HOME/.local/bin/mac-ocr"
```

The installer downloads a prebuilt universal binary from GitHub Releases and verifies its SHA-256 checksum. It does not require a local Swift toolchain. Requirements are macOS 12 or later, Node.js 18 or later, pnpm, `curl`, `tar`, `shasum`, and the Claude Code, Codex, and OpenCode CLIs. Ensure `~/.local/bin` is on `PATH` to run `mac-ocr` directly. Building from a checkout with `make install` still requires Swift 6.

Check the agent registrations with:

```sh
claude mcp get mac-ocr
codex mcp get mac-ocr
opencode mcp list
```

The CLI can reconfigure all agents, or one agent at a time:

```sh
mac-ocr configure
mac-ocr configure claude
mac-ocr configure codex
mac-ocr configure opencode
```

Configuration runs agent commands without interactive input, shows each command before it starts, and stops a command after 30 seconds by default. Set `MAC_OCR_CONFIG_TIMEOUT_MS` to change the per-command limit.

## CLI

```sh
mac-ocr --help
mac-ocr configure --help
mac-ocr ./image.png
mac-ocr ./image.png --lang vi-VN,en-US --level accurate
mac-ocr ./image.png --format text --no-correction
mac-ocr ./document.pdf --pages 1-3
mac-ocr --screen --format text
mac-ocr --screen --region -1200,100,800,600 --pixels
printf '{"paths":["./one.png","./two.png"],"languages":["vi-VN","en-US"],"pixels":true}' | mac-ocr --batch
mac-ocr --list-displays
```

Options:

- `--lang`: comma-separated Vision language identifiers. `vi-VN` aliases Vision's `vi-VT` where available.
- `--level`: `accurate` (default) or `fast`. Vietnamese always uses accurate to preserve diacritics.
- `--format`: `json` (default) or `text`.
- `--pages`: 1-based inclusive PDF range, such as `1-3`; defaults to all pages.
- `--screen`: capture the main display. Grant Screen Recording permission to the host app.
- `--region`: screen capture rectangle `x,y,width,height` in desktop points. Origins may be negative; the region must fit within one display.
- `--display`: select a 1-based display index. Use `--list-displays` to inspect active displays; cannot be combined with `--region`.
- `--pixels`: return boxes in pixels with a top-left origin. JSON includes image dimensions.
- `--batch`: read a JSON object from stdin with `paths` (1 to 50 images), and optional `languages`, `level`, and `pixels`. Returns results in input order with per-image errors.
- `--no-correction`: disable Vision language correction.

Image JSON has `text`, `width`, `height`, and `lines`. PDF JSON has `text` and `pages`, with each page's dimensions and lines. Boxes are normalized from 0 to 1 with a bottom-left origin unless `--pixels` is enabled. Errors are JSON on stderr and return a nonzero exit status.

## MCP server

The installed server provides `ocr_image`, `ocr_images`, `ocr_pdf`, `ocr_screen`, and `list_displays`. OCR tools accept `pixels: true` to return pixel boxes. Screen results include capture metadata for mapping boxes to desktop coordinates. Batch OCR handles up to 50 paths in one CLI process. OCR processes for the same macOS user share four system lock slots; the default wait limit is 60 seconds.

For a manual server launch from a checkout:

```sh
cd mcp
pnpm install
pnpm build
pnpm start
```

Configure the server with these optional environment variables:

- `MAC_OCR_BIN`: CLI path. The server checks the project release binary first, then searches `PATH`.
- `MAC_OCR_TIMEOUT_MS`: maximum process time in milliseconds; defaults to `60000`.
- `MAC_OCR_LANGS`: default comma-separated languages, for example `vi-VN,en-US`.
- `MAC_OCR_QUEUE_TIMEOUT_MS`: maximum wait for a shared OCR slot; defaults to `60000`.

## Build and test

For development, build from the repository root with:

```sh
make build
```

This builds the Swift CLI and MCP bundle. The local executable is `.build/release/mac-ocr`.

Run the CLI smoke checks, MCP stdio smoke test, and typecheck with:

```sh
make test
```
