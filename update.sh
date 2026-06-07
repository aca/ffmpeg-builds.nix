#!/usr/bin/env bash
# Refresh the BtbN/FFmpeg-Builds "latest" hashes in flake.nix.
# Re-prefetches every variant/arch and rewrites the sha256-... lines in place.
set -euo pipefail

cd "$(dirname "$0")"

base="https://github.com/BtbN/FFmpeg-Builds/releases/download/latest"

# system -> upstream arch token
declare -A arch=(
  [x86_64-linux]=linux64
  [aarch64-linux]=linuxarm64
)

for variant in gpl lgpl; do
  for system in "${!arch[@]}"; do
    url="${base}/ffmpeg-master-latest-${arch[$system]}-${variant}.tar.xz"
    echo ">> ${variant} / ${system}" >&2
    raw=$(nix-prefetch-url --type sha256 "$url" 2>/dev/null)
    sri=$(nix hash convert --hash-algo sha256 --to sri "$raw")
    # Replace the hash on the line matching `<system> = "sha256-...";` that
    # falls under the current variant block. We rely on unique system keys per
    # variant block by scoping with awk.
    tmp=$(mktemp)
    awk -v v="$variant" -v sys="$system" -v sri="$sri" '
      $0 ~ "^[[:space:]]*"v" = \\{" { inblk=1 }
      inblk && $0 ~ "^[[:space:]]*\\};" { inblk=0 }
      inblk && $0 ~ "^[[:space:]]*"sys" = " {
        sub(/sha256-[A-Za-z0-9+/=]+/, sri)
      }
      { print }
    ' flake.nix > "$tmp"
    mv "$tmp" flake.nix
  done
done

echo "Done. Review with: git diff flake.nix" >&2
