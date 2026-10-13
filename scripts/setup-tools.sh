#!/usr/bin/env bash
set -euo pipefail

# Official release archives, pinned and checked against GitHub's release digests.
tools_dir="${ROBLOX_TOOLS_DIR:-/workspace/.roblox-tools}"
if [[ "$(uname -s)" != Linux || "$(uname -m)" != x86_64 ]]; then
  echo "This cloud setup supports Linux x86_64. Install Rojo 7.7.1 and Luau 0.742 for your platform." >&2
  exit 1
fi
mkdir -p "$tools_dir/bin" "$tools_dir/downloads"

fetch_archive() {
  local name="$1" url="$2" expected="$3" archive="$tools_dir/downloads/$1"
  if [[ -f "$archive" ]] && ! printf '%s  %s\n' "$expected" "$archive" | sha256sum --check --status; then
    rm -- "$archive"
  fi
  if [[ ! -f "$archive" ]]; then
    curl --fail --location --retry 2 --connect-timeout 15 --max-time 180 "$url" --output "$archive.tmp"
    printf '%s  %s\n' "$expected" "$archive.tmp" | sha256sum --check --status
    mv -- "$archive.tmp" "$archive"
  fi
  printf '%s  %s\n' "$expected" "$archive" | sha256sum --check
  unzip -oq "$archive" -d "$tools_dir/bin"
}

fetch_archive rojo-7.7.1-linux-x86_64.zip \
  https://github.com/rojo-rbx/rojo/releases/download/v7.7.1/rojo-7.7.1-linux-x86_64.zip \
  00feb4fa0829a1dd72b49df2639da519a352bfe13cadcd83969e2ba2bb5693c4
fetch_archive luau-0.742-ubuntu.zip \
  https://github.com/luau-lang/luau/releases/download/0.742/luau-ubuntu.zip \
  152058b98c60ff1f5b5ec9bca0b8eb37793cae161dd3a05608cc3d8738ba1a4d
chmod +x "$tools_dir/bin/rojo" "$tools_dir/bin/luau" "$tools_dir/bin/luau-compile" "$tools_dir/bin/luau-analyze"
"$tools_dir/bin/rojo" --version
echo "Luau 0.742 installed. Tools: $tools_dir/bin"
