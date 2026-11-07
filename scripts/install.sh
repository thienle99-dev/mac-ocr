#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
install_root="$HOME/.local/share/mac-ocr"
bin_root="$HOME/.local/bin"

mkdir -p "$install_root/.build" "$install_root/mcp" "$bin_root"
if [[ -L "$install_root/.build/release" ]]; then
  rm -f "$install_root/.build/release"
fi
mkdir -p "$install_root/.build/release"
install -m 755 "$root/.build/release/mac-ocr" "$install_root/.build/release/mac-ocr"
rm -rf "$install_root/mcp/dist"
cp -R "$root/mcp/dist" "$root/mcp/package.json" "$root/mcp/pnpm-lock.yaml" "$install_root/mcp/"
pnpm --dir "$install_root/mcp" install --prod --frozen-lockfile
ln -sf "$install_root/.build/release/mac-ocr" "$bin_root/mac-ocr"

claude mcp remove mac-ocr --scope local >/dev/null 2>&1 || true
claude mcp remove mac-ocr --scope user >/dev/null 2>&1 || true
claude mcp add --scope user mac-ocr -- node "$install_root/mcp/dist/index.js"
codex mcp remove mac-ocr >/dev/null 2>&1 || true
codex mcp add mac-ocr -- node "$install_root/mcp/dist/index.js"
node "$root/scripts/register-opencode.mjs" "$install_root/mcp/dist/index.js"

printf 'Installed mac-ocr to %s\n' "$install_root"
