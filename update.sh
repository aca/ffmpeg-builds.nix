#!/usr/bin/env bash
# Pin flake.nix to the newest immutable autobuild release of master.
# Finds the latest autobuild-* tag, resolves the master asset filename stem,
# re-prefetches every variant/arch hash, and rewrites flake.nix in place.
set -euo pipefail

cd "$(dirname "$0")"

api="https://api.github.com/repos/BtbN/FFmpeg-Builds/releases"

# Newest dated release tag (skip the rolling "latest").
read -r release rev < <(
  curl -fsSL "$api?per_page=20" | python3 -c '
import json, re, sys
for r in json.load(sys.stdin):
    tag = r["tag_name"]
    if not tag.startswith("autobuild-"):
        continue
    for a in r["assets"]:
        # master build for linux64 gpl: ffmpeg-N-<num>-g<hash>-linux64-gpl.tar.xz
        m = re.match(r"(ffmpeg-N-\d+-g[0-9a-f]+)-linux64-gpl\.tar\.xz$", a["name"])
        if m:
            print(tag, m.group(1))
            sys.exit(0)
    # no master asset in this release; try the next
sys.exit("no autobuild release with a master linux64-gpl asset found")
'
)

echo ">> release=$release rev=$rev" >&2
base="https://github.com/BtbN/FFmpeg-Builds/releases/download/$release"

declare -A arch=( [x86_64-linux]=linux64 [aarch64-linux]=linuxarm64 )

# Update the pinned release/rev lines.
sed -i -E "s|^( *release = \").*(\";.*)|\1$release\2|" flake.nix
sed -i -E "s|^( *rev = \").*(\";.*)|\1$rev\2|" flake.nix

for variant in gpl lgpl; do
  for system in "${!arch[@]}"; do
    url="$base/${rev}-${arch[$system]}-${variant}.tar.xz"
    echo ">> ${variant} / ${system}" >&2
    raw=$(nix-prefetch-url --type sha256 "$url" 2>/dev/null)
    sri=$(nix hash convert --hash-algo sha256 --to sri "$raw")
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
