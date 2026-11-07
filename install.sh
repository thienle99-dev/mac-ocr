#!/bin/sh
set -eu

repo="https://github.com/thienle99-dev/mac-ocr"
release_api="https://api.github.com/repos/thienle99-dev/mac-ocr/releases/latest"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/mac-ocr-install.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

for command in curl tar shasum pnpm node; do
  if ! command -v "$command" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "$command" >&2
    exit 1
  fi
done

if [ "$(uname -s)" != "Darwin" ]; then
  echo 'mac-ocr requires macOS.' >&2
  exit 1
fi

mkdir -p "$tmp/source" "$tmp/binary"
curl -fsSL "$release_api" -o "$tmp/release.json"
tag="$(sed -n 's/^[[:space:]]*"tag_name": "\([^"]*\)".*/\1/p' "$tmp/release.json" | head -n 1)"
if [ -z "$tag" ]; then
  echo 'Could not determine the latest mac-ocr release tag.' >&2
  exit 1
fi

curl -fsSL "$repo/archive/refs/tags/$tag.tar.gz" -o "$tmp/source.tar.gz"
tar -xzf "$tmp/source.tar.gz" --strip-components=1 -C "$tmp/source"
curl -fsSL "$repo/releases/download/$tag/mac-ocr-macos-universal.tar.gz" -o "$tmp/binary.tar.gz"
tar -xzf "$tmp/binary.tar.gz" -C "$tmp/binary"
(cd "$tmp/binary" && shasum -a 256 -c SHA256SUMS)

mkdir -p "$tmp/source/.build/release"
install -m 755 "$tmp/binary/mac-ocr" "$tmp/source/.build/release/mac-ocr"
pnpm --dir "$tmp/source/mcp" install --frozen-lockfile
pnpm --dir "$tmp/source/mcp" build
bash "$tmp/source/scripts/install.sh"
