#!/bin/sh
set -eu

repo="https://github.com/thienle99-dev/mac-ocr"
archive_url="$repo/archive/refs/heads/main.tar.gz"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/mac-ocr-install.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

for command in curl tar swift pnpm make node; do
  if ! command -v "$command" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "$command" >&2
    exit 1
  fi
done

if [ "$(uname -s)" != "Darwin" ]; then
  echo 'mac-ocr requires macOS.' >&2
  exit 1
fi

mkdir -p "$tmp/source"
curl -fsSL "$archive_url" -o "$tmp/source.tar.gz"
tar -xzf "$tmp/source.tar.gz" --strip-components=1 -C "$tmp/source"
make -C "$tmp/source" install
