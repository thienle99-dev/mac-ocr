# mac-ocr

Local OCR for AI agents on macOS. The CLI uses Apple Vision, and the MCP server exposes image, PDF, batch, and screen OCR tools. Recognition runs on-device.

## Install

Install the prebuilt CLI with Homebrew:

```sh
brew install thienle99-dev/mac-ocr/mac-ocr
```

This installs the universal CLI only. To also configure Claude Code, Codex, and OpenCode with the MCP server, use the one-command installer below.

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
mac-ocr ./document.pdf --pages 1-3 --force-ocr
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
- `--force-ocr`: ignore selectable text embedded in a PDF and use Apple Vision on the rendered pages.
- `--screen`: capture the main display. Grant Screen Recording permission to the host app.
- `--region`: screen capture rectangle `x,y,width,height` in desktop points. Origins may be negative; the region must fit within one display.
- `--display`: select a 1-based display index. Use `--list-displays` to inspect active displays; cannot be combined with `--region`.
- `--pixels`: return boxes in pixels with a top-left origin. JSON includes image dimensions.
- `--batch`: read a JSON object from stdin with `paths` (1 to 50 images), and optional `languages`, `level`, and `pixels`. Returns results in input order with per-image errors.
- `--no-correction`: disable Vision language correction.

Image JSON has `text`, `width`, `height`, and `lines`. PDF JSON has `text` and `pages`, with each page's dimensions, `source` (`pdf-text` or `vision`), and lines. Pages with selectable embedded text use PDFKit; other pages use Apple Vision. Vision lines include a confidence score; embedded PDF text lines do not. Boxes are normalized from 0 to 1 with a bottom-left origin unless `--pixels` is enabled. Errors are JSON on stderr and return a nonzero exit status.

## Accuracy and token use

For screenshot UI debugging, see [the UI screenshot evaluation](docs/ui-accuracy.md): 12 Chromium screenshots covering light/dark themes, 12/14/16 px text, and real 1×/2× rendering. `accurate` with Vietnamese/English recovered 179 of 180 annotated labels exactly (89/90 at 1×, 90/90 at 2×). This is a controlled fixture with repeated content, not a benchmark of real apps or UI bug detection. OCR supplies text and geometry; use DOM/accessibility to verify element state and vision to inspect layout, clipping, icons, and colors.

OCR runs locally with Apple Vision. It does not send document images to an OCR API; the OCR step itself uses no external model API tokens. The extracted text still enters the agent's context, so long documents and verbose JSON results can use tokens.

A Vision-only comparison used `--force-ocr` on 11 pages from four official IRS PDFs: [Form 1040](https://www.irs.gov/pub/irs-pdf/f1040.pdf) (2025, pages 1–2), [Form W-4](https://www.irs.gov/pub/irs-pdf/fw4.pdf) (2026, pages 1, 3–4), [Schedule C](https://www.irs.gov/pub/irs-pdf/f1040sc.pdf) (2026, pages 1–2), and [Form 1040 instructions](https://www.irs.gov/pub/irs-prior/i1040gi--2025.pdf) (2025, pages 2, 4, 51, 71). The pages cover fillable forms, prose, worksheets, and dense tables. Each page was rendered at 2× resolution. Its embedded PDF text was used as the reference; the selected pages contain 8,157 reference tokens.

| Apple Vision mode | Token precision | Token recall | Token F1 | Sequence WER |
| --- | ---: | ---: | ---: | ---: |
| `accurate` | 97.8% | 96.7% | 97.3% | 42.6% |
| `fast` | 73.9% | 68.1% | 70.9% | 54.4% |

Scores use Unicode NFKC, lowercase tokens, and join words split by line-wrap hyphenation. Token precision/recall/F1 compare token counts without considering order. Sequence WER compares token order with the PDF text layer, so it penalizes columns and tables heavily. `accurate` recovered most words and figures, while reading order remains a limitation on form and table pages. WER on a prose page was 1.4%; on dense table pages it was much higher. The compact-table ordering heuristic is intentionally conservative; this 11-page Vision-only score stayed unchanged after the change, while the compact invoice fixture now reads row-wise. The pages are clean, born-digital PDFs, not degraded scans, handwriting, or Vietnamese documents, so these numbers are not a universal accuracy claim. By default, selectable text is extracted directly and is labeled `pdf-text`; that path is text extraction, not an OCR accuracy result. Use `--force-ocr` to evaluate or prefer Vision on such a file.

A separate, qualitative comparison on a locally generated three-page PDF used an independent vision AI OCR result as a second reader:

| Content | mac-ocr (`accurate`) | Independent vision AI |
| --- | --- | --- |
| English page | Text and numbers matched | Text and numbers matched |
| Vietnamese page | Diacritics and numbers matched | Diacritics and numbers matched |
| Invoice table | Recognized the text and values, but emitted columns in an awkward reading order | Preserved the table's row order more clearly |

The vision-AI comparison is only a small spot check, not a measured model benchmark. Scans, small or faint text, skew, handwriting, and complex layouts may produce different results. Review table reading order and critical figures against the PDF.

To reduce the text sent back to an agent, OCR only the needed PDF pages (`--pages 4-6` in the CLI or `pages: "4-6"` with MCP `ocr_pdf`). For CLI workflows that need only recognized text, `--format text` omits JSON fields such as boxes, confidence, and page metadata. MCP currently returns JSON; selecting fewer pages is the main way to limit its result size. Token savings depend on the document and agent tokenizer; they have not been measured as a numeric benchmark.

## MCP server

The installed server provides `ocr_image`, `ocr_images`, `ocr_pdf`, `ocr_screen`, and `list_displays`. `ocr_pdf` reads embedded text when available and falls back to Vision; pass `forceOCR: true` to always use Vision. OCR tools accept `pixels: true` to return pixel boxes. Screen results include capture metadata for mapping boxes to desktop coordinates. Batch OCR handles up to 50 paths in one CLI process. OCR processes for the same macOS user share four system lock slots; the default wait limit is 60 seconds.

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
