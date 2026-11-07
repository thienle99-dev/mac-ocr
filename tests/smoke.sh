#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
binary="$root/.build/release/mac-ocr"
if [[ ! -x "$binary" ]]; then
  echo "FAIL: release binary exists (build with swift build -c release first)" >&2
  exit 1
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
swift "$root/tests/mk-sample.swift" "$tmpdir/sample.png"
printf 'not an image\n' > "$tmpdir/not-image.txt"

failures=0
report() {
  if [[ "$1" == 0 ]]; then
    echo "PASS: $2"
  else
    echo "FAIL: $2" >&2
    failures=$((failures + 1))
  fi
}

if "$binary" --help >"$tmpdir/help.out" && grep -q 'USAGE' "$tmpdir/help.out" && grep -q -- '--batch' "$tmpdir/help.out" && grep -q -- '--force-ocr' "$tmpdir/help.out"; then
  report 0 "CLI help"
else
  report 1 "CLI help"
fi

if "$binary" configure --help >"$tmpdir/configure-help.out" && grep -q 'claude|codex|opencode' "$tmpdir/configure-help.out"; then
  report 0 "configure help"
else
  report 1 "configure help"
fi

set +e
"$binary" "$tmpdir/sample.png" --lang vi-VN,en-US >"$tmpdir/json.out" 2>"$tmpdir/json.err"
status=$?
set -e
if [[ $status -eq 0 ]] && python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); text=d["text"]; lines=d["lines"]; assert "Hello World 2026" in text and "Việt Nam" in text; assert lines and all(all(k in line["box"] for k in ("x", "y", "width", "height")) for line in lines)' "$tmpdir/json.out"; then
  report 0 "JSON OCR with Vietnamese and English"
else
  report 1 "JSON OCR with Vietnamese and English"
fi

"$binary" "$tmpdir/sample.png" --lang vi-VN,en-US --level fast --pixels >"$tmpdir/pixels.out"
if python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["width"] > 0 and d["height"] > 0; assert d["lines"] and all(0 <= line["box"]["x"] <= d["width"] and 0 <= line["box"]["y"] <= d["height"] for line in d["lines"]); assert "Việt Nam" in d["text"]' "$tmpdir/pixels.out"; then
  report 0 "pixel coordinates and Vietnamese fast fallback"
else
  report 1 "pixel coordinates and Vietnamese fast fallback"
fi

printf '{"paths":["%s","%s"],"languages":["en-US"],"level":"accurate","pixels":true}' "$tmpdir/sample.png" "$tmpdir/sample.png" | "$binary" --batch >"$tmpdir/batch.out"
if python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert len(d["results"]) == 2 and all(x["result"]["width"] > 0 for x in d["results"])' "$tmpdir/batch.out"; then
  report 0 "single-process batch OCR"
else
  report 1 "single-process batch OCR"
fi

if "$binary" --list-displays >"$tmpdir/displays.out" && python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert isinstance(d,list) and all("pixelWidth" in x and "scaleX" in x for x in d)' "$tmpdir/displays.out"; then
  report 0 "display listing"
else
  report 1 "display listing"
fi

set +e
"$binary" "$tmpdir/sample.png" --format text >"$tmpdir/text.out" 2>"$tmpdir/text.err"
status=$?
set -e
if [[ $status -eq 0 ]] && grep -q 'Hello World 2026' "$tmpdir/text.out"; then
  report 0 "text format"
else
  report 1 "text format"
fi

expect_error() {
  local label="$1"
  shift
  set +e
  "$binary" "$@" >"$tmpdir/error.out" 2>"$tmpdir/error.err"
  local status=$?
  set -e
  if [[ $status -eq 2 ]] && python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert "error" in d' "$tmpdir/error.err"; then
    report 0 "$label"
  else
    report 1 "$label"
  fi
}

sips -s format pdf "$tmpdir/sample.png" --out "$tmpdir/sample.pdf" >/dev/null
set +e
"$binary" "$tmpdir/sample.pdf" --lang vi-VN,en-US >"$tmpdir/pdf.out" 2>"$tmpdir/pdf.err"
status=$?
set -e
if [[ $status -eq 0 ]] && python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert "Hello World 2026" in d["text"]; assert [p["page"] for p in d["pages"]] == [1]; assert d["pages"][0]["source"] == "vision"' "$tmpdir/pdf.out"; then
  report 0 "PDF OCR"
else
  report 1 "PDF OCR"
fi

swift "$root/tests/mk-text-pdf.swift" "$tmpdir/text-layer.pdf"
"$binary" "$tmpdir/text-layer.pdf" --pixels >"$tmpdir/text-layer.out"
if python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); p=d["pages"][0]; assert p["source"] == "pdf-text"; assert "Selectable PDF text layer" in p["text"] and "$1,240.50" in p["text"]; assert p["lines"] and all("confidence" not in line for line in p["lines"]); assert all(0 <= line["box"]["x"] <= p["width"] and 0 <= line["box"]["y"] <= p["height"] for line in p["lines"])' "$tmpdir/text-layer.out"; then
  report 0 "PDF embedded text and pixel boxes"
else
  report 1 "PDF embedded text and pixel boxes"
fi

"$binary" "$tmpdir/text-layer.pdf" --force-ocr --lang en-US >"$tmpdir/forced-ocr.out"
if python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); p=d["pages"][0]; assert p["source"] == "vision" and "Selectable PDF text layer" in p["text"]' "$tmpdir/forced-ocr.out"; then
  report 0 "force Vision OCR on text PDF"
else
  report 1 "force Vision OCR on text PDF"
fi

swift "$root/tests/mk-table-sample.swift" "$tmpdir/table.png"
sips -s format pdf "$tmpdir/table.png" --out "$tmpdir/table.pdf" >/dev/null
"$binary" "$tmpdir/table.pdf" --lang en-US >"$tmpdir/table.out"
if python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); p=d["pages"][0]; assert p["source"] == "vision"; t=p["text"]; labels=["Item","Qty","Unit price","Total","USB-C Dock","2","89.95","179.90","VAT (10%)","17.99","TOTAL","197.89"]; positions=[t.index(x) for x in labels]; assert positions == sorted(positions)' "$tmpdir/table.out"; then
  report 0 "scanned PDF table row reading order"
else
  report 1 "scanned PDF table row reading order"
fi

expect_error "PDF page out of range error" "$tmpdir/sample.pdf" --pages 2
expect_error "pages on image error" "$tmpdir/sample.png" --pages 1
expect_error "force OCR on image error" "$tmpdir/sample.png" --force-ocr
expect_error "missing file error" "$tmpdir/missing.png"
expect_error "unsupported language error" "$tmpdir/sample.png" --lang xx
expect_error "non-image file error" "$tmpdir/not-image.txt"

if [[ $failures -ne 0 ]]; then
  exit 1
fi
