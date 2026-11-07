# mac-ocr

Local OCR for AI agents on macOS. The Swift command line program uses Apple Vision; the MCP server exposes it as an `ocr_image` tool. No OCR model or network service is used at runtime.

## Requirements

- macOS 12 or later
- Swift 6 toolchain
- Node.js 18 or later and pnpm
- Claude Code, Codex CLI, and OpenCode CLI for the one-command agent setup
- `curl`, `tar`, and `make` for the `curl | sh` installer

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

The examples below use the installed command. Run `make install` or the `curl | sh` installer first, and ensure `~/.local/bin` is on `PATH`. Before installation, replace `mac-ocr` with `.build/release/mac-ocr`.

```sh
mac-ocr ./image.png
mac-ocr ./image.png --lang vi-VN,en-US --level accurate
mac-ocr ./image.png --format text --no-correction
mac-ocr ./document.pdf --pages 1-3
mac-ocr --screen --format text
mac-ocr --screen --region -1200,100,800,600 --pixels
printf '{"paths":["./one.png","./two.png"],"languages":["vi-VN","en-US"],"pixels":true}' | mac-ocr --batch
mac-ocr --list-displays
```

From a checkout, configure MCP agents with the built CLI:

```sh
.build/release/mac-ocr configure
.build/release/mac-ocr configure codex
```

After installation, run the same command as `mac-ocr configure`; it uses the installed MCP bundle. You can select one agent with `mac-ocr configure claude`, `mac-ocr configure codex`, or `mac-ocr configure opencode`.

Options:

- `--lang`: comma-separated Vision recognition language identifiers. The CLI accepts `vi-VN` as an alias for Vision's `vi-VT` identifier when the latter is available. Supported languages vary by macOS version and recognition level.
- `--level`: `accurate` (default) or `fast`.
- `--format`: `json` (default) or `text`.
- `--pages`: 1-based inclusive PDF page range, such as `1-3`; defaults to all pages.
- `--screen`: capture the main display and recognize it. Do not provide an image path with this flag. The host app must have Screen Recording permission in System Settings > Privacy & Security > Screen Recording.
- `--region`: with `--screen`, capture only the `x,y,width,height` rectangle in desktop points; `x` and `y` may be negative.
- `--display`: with `--screen`, capture a 1-based display index; cannot be combined with `--region`.
- `--pixels`: return bounding boxes in image pixels with a top-left origin. JSON also includes image `width` and `height` (and per-page dimensions for PDFs).
- `--no-correction`: disable Vision language correction.

**Tips:** Vietnamese automatically uses `accurate`, even when `--level fast` is requested, because fast may drop diacritics. For Vietnamese and English, pass `--lang vi-VN,en-US`.

Image and screenshot JSON output has `text` and `lines`. PDF JSON output has `text` and `pages`, with each page containing its 1-based `page`, `text`, and `lines`. Each line contains recognized `text`, a confidence score, and a normalized `box` (`x`, `y`, `width`, `height`). Coordinates range from 0 to 1, with the origin at the bottom left, matching Vision's coordinate system. Errors are JSON on stderr and return a nonzero exit status.

## MCP server

```sh
cd mcp
pnpm install
pnpm build
pnpm start
```

The `ocr_image`, `ocr_images`, `ocr_pdf`, and `ocr_screen` tools accept optional `pixels: true` to return pixel boxes with a top-left origin. Screen results include a `capture` object with display ID, desktop origin, and pixel-to-point scale for mapping boxes to desktop positions. `ocr_images` accepts up to 50 paths and processes them in one CLI process, returning per-image results in input order. `list_displays` reports display IDs, desktop bounds, pixel dimensions, and scale. Screen `region` uses desktop points, may have negative origins, and must fit within one display. Vietnamese always uses accurate recognition. All OCR processes for this user share four system lock slots; waiting for a slot times out after 60 seconds by default. Configure the server with these environment variables:

- `MAC_OCR_BIN`: path to the binary. The server checks `.build/release/mac-ocr` in the project root first, then searches `PATH` for `mac-ocr`.
- `MAC_OCR_TIMEOUT_MS`: maximum OCR process time in milliseconds; defaults to `60000`. Values must be positive integers.
- `MAC_OCR_LANGS`: default comma-separated recognition languages (for example, `vi-VN,en-US`); an explicit `languages` tool argument takes precedence.
- `MAC_OCR_QUEUE_TIMEOUT_MS`: maximum time to wait for one of the four shared OCR slots; defaults to `60000`.

Install once for Claude Code, Codex, and OpenCode:

```sh
curl -fsSL https://raw.githubusercontent.com/thienle99-dev/mac-ocr/main/install.sh | sh
```

The installer requires the GitHub repository to be public. It downloads the `main` branch to a temporary directory, builds the CLI and MCP server, then installs them with runtime dependencies to `~/.local/share/mac-ocr`. It creates `~/.local/bin/mac-ocr` and registers the installed MCP server with all three agents. The installed copy is independent of the temporary download. Ensure `~/.local/bin` is on `PATH` to call `mac-ocr` directly. You can also run `make install` from a checkout.

The installer updates the `mac-ocr` registration for each agent so it points to the same installed copy, and preserves other MCP entries. Run the `curl | sh` command again to update from `main`, or run `make install` after changing a local checkout.

Check the registrations with:

```sh
claude mcp get mac-ocr
codex mcp get mac-ocr
opencode mcp list
```

To register only the current checkout manually with Claude Code:

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

For a checkout based manual launch, build the Swift executable and MCP bundle first. The one-time installation above includes both.
