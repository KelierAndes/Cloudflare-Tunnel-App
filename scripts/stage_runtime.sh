#!/usr/bin/env bash
# Place the cloudflared runtime that should be bundled into assets/bin before a build.
#   ./scripts/stage_runtime.sh windows|linux|none [source-file]
set -euo pipefail

platform="${1:-linux}"
source_file="${2:-}"
project="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dir="$project/assets/bin"
mkdir -p "$dir"
find "$dir" -maxdepth 1 -name 'cloudflared*' -delete

releases="https://github.com/cloudflare/cloudflared/releases/latest/download"

case "$platform" in
  windows)
    target="$dir/cloudflared.exe"
    url="$releases/cloudflared-windows-amd64.exe"
    ;;
  linux)
    target="$dir/cloudflared"
    url="$releases/cloudflared-linux-amd64"
    ;;
  none)
    # The asset directory must not be empty; a <1 MB file means "not bundled".
    printf 'placeholder' > "$dir/cloudflared"
    ls -l "$dir"
    exit 0
    ;;
  *)
    echo "unknown platform: $platform" >&2
    exit 1
    ;;
esac

if [[ -n "$source_file" ]]; then
  cp "$source_file" "$target"
else
  echo "downloading $url"
  curl -fL --retry 3 -o "$target" "$url"
fi
chmod 755 "$target"
ls -l "$dir"
