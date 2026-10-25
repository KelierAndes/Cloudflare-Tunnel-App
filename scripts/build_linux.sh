#!/usr/bin/env bash
# Build the Linux desktop bundle. Must run on Linux (native or WSL2).
#
# One-time host setup (Debian / Ubuntu):
#   sudo apt install -y clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-12-dev
#
# Usage: ./scripts/build_linux.sh [linux|none]
#   linux -> bundle cloudflared inside the app
#   none  -> ship a placeholder, the app downloads cloudflared on first run
set -euo pipefail

project="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project"

./scripts/stage_runtime.sh "${1:-linux}"
flutter pub get
flutter build linux --release

echo
echo "bundle: $project/build/linux/x64/release/bundle/cf_tunnel_manager"
