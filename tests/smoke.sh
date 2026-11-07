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

set +e
"$binary" "$tmpdir/sample.png" --lang vi-VN,en-US >"$tmpdir/json.out" 2>"$tmpdir/json.err"
status=$?
set -e
if [[ $status -eq 0 ]] && python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); text=d["text"]; lines=d["lines"]; assert "Hello World 2026" in text and "Việt Nam" in text; assert lines and all(all(k in line["box"] for k in ("x", "y", "width", "height")) for line in lines)' "$tmpdir/json.out"; then
  report 0 "JSON OCR with Vietnamese and English"
else
  report 1 "JSON OCR with Vietnamese and English"
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
