#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
swift "$root/tests/mk-sample.swift" "$tmpdir/sample.png"
sips -s format pdf "$tmpdir/sample.png" --out "$tmpdir/sample.pdf" >/dev/null
swift "$root/tests/mk-text-pdf.swift" "$tmpdir/text-layer.pdf"
node "$root/tests/mcp-smoke.mjs" "$root/mcp/dist/index.js" "$tmpdir/sample.png" "$tmpdir/sample.pdf" "$tmpdir/text-layer.pdf"
