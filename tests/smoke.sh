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

if "$binary" --help >"$tmpdir/help.out" && grep -q 'USAGE' "$tmpdir/help.out" && grep -q -- '--batch' "$tmpdir/help.out"; then
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
if [[ $status -eq 0 ]] && python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert "Hello World 2026" in d["text"]; assert [p["page"] for p in d["pages"]] == [1]' "$tmpdir/pdf.out"; then
  report 0 "PDF OCR"
else
  report 1 "PDF OCR"
fi

expect_error "PDF page out of range error" "$tmpdir/sample.pdf" --pages 2
expect_error "pages on image error" "$tmpdir/sample.png" --pages 1
expect_error "missing file error" "$tmpdir/missing.png"
expect_error "unsupported language error" "$tmpdir/sample.png" --lang xx
expect_error "non-image file error" "$tmpdir/not-image.txt"

if [[ $failures -ne 0 ]]; then
  exit 1
fi
