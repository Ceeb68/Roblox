#!/usr/bin/env bash
set -euo pipefail

# Linux cloud build tools stay in writable workspace directories, never $HOME.
project_dir="$(cd -- "$(dirname -- "$0")/.." && pwd)"
tools_dir="${DIRTLINE_TOOLS_DIR:-/workspace/.dirtline-tools}"
runtime_dir="${DIRTLINE_RUNTIME_DIR:-/workspace/.dirtline-runtime}"
version="4.6.3"
release="${version}-stable"
engine_digest="d0bc2113065e481c9c2c2b2c37daa4e8be3fe9e27f0ab9ab0b6096e9a37907f3"
templates_digest="3fbe2c0e2dec9d537ab9ec97bcf8da91dcf23357fc51f67092dd068d839290a8"
base_url="https://github.com/godotengine/godot-builds/releases/download/$release"
mkdir -p "$tools_dir/downloads" "$runtime_dir/data" "$runtime_dir/config" "$runtime_dir/cache"
export XDG_DATA_HOME="$runtime_dir/data"
export XDG_CONFIG_HOME="$runtime_dir/config"
export XDG_CACHE_HOME="$runtime_dir/cache"

for dependency in curl python3 sha256sum; do
  command -v "$dependency" >/dev/null || { printf 'Required tool unavailable: %s\n' "$dependency" >&2; exit 1; }
done

download_verified() {
  local filename="$1" expected="$2" destination="$tools_dir/downloads/$1"
  if test -f "$destination" && printf '%s  %s\n' "$expected" "$destination" | sha256sum --check --status; then
    printf 'Using verified cache: %s\n' "$filename"
    return
  fi
  curl --fail --location --proto '=https' --tlsv1.2 --retry 3 \
    --output "$destination.part" "$base_url/$filename"
  printf '%s  %s\n' "$expected" "$destination.part" | sha256sum --check --status || {
    printf 'SHA-256 verification failed: %s\n' "$filename" >&2
    rm -f "$destination.part"
    exit 1
  }
  mv "$destination.part" "$destination"
}

engine="${DIRTLINE_GODOT:-}"
if test -z "$engine"; then
  engine="$(command -v godot || command -v godot4 || true)"
fi
installed_version=""
if test -n "$engine"; then
  installed_version="$("$engine" --headless --version 2>/dev/null || true)"
fi
if [[ "$installed_version" != 4.6.3.stable.* ]]; then
  if test "$(uname -s)" != Linux || test "$(uname -m)" != x86_64; then
    printf 'Install Godot %s for this platform and set DIRTLINE_GODOT to its executable.\n' "$version" >&2
    exit 1
  fi
  engine_archive="Godot_v${release}_linux.x86_64.zip"
  download_verified "$engine_archive" "$engine_digest"
  engine="$tools_dir/godot/Godot_v${release}_linux.x86_64"
  python3 - "$tools_dir/downloads/$engine_archive" "$engine" <<'PY'
import os, sys, zipfile
archive, destination = sys.argv[1:]
os.makedirs(os.path.dirname(destination), exist_ok=True)
with zipfile.ZipFile(archive) as source:
    filename = os.path.basename(destination)
    with source.open(filename) as input_file, open(destination, 'wb') as output_file:
        import shutil
        shutil.copyfileobj(input_file, output_file)
os.chmod(destination, 0o755)
PY
fi
printf '%s\n' "$engine" > "$runtime_dir/godot-executable"

templates_archive="Godot_v${release}_export_templates.tpz"
download_verified "$templates_archive" "$templates_digest"
templates_dir="$runtime_dir/data/godot/export_templates/${version}.stable"
python3 - "$tools_dir/downloads/$templates_archive" "$templates_dir" <<'PY'
import hashlib, os, shutil, sys, zipfile
archive, destination = sys.argv[1:]
os.makedirs(destination, exist_ok=True)
required = ('version.txt', 'windows_release_x86_64.exe', 'linux_release.x86_64')
def digest(stream):
    result = hashlib.sha256()
    for block in iter(lambda: stream.read(1024 * 1024), b''):
        result.update(block)
    return result.hexdigest()
with zipfile.ZipFile(archive) as source:
    for filename in required:
        entry = 'templates/' + filename
        target = os.path.join(destination, filename)
        with source.open(entry) as packaged:
            expected = digest(packaged)
        if os.path.isfile(target):
            with open(target, 'rb') as installed:
                if digest(installed) == expected:
                    print('Verified installed template:', filename)
                    continue
        with source.open(entry) as input_file, open(target, 'wb') as output_file:
            shutil.copyfileobj(input_file, output_file)
        if filename.startswith('linux_'):
            os.chmod(target, 0o755)
        print('Installed template:', filename)
PY
printf 'Godot ready: %s\n' "$engine"
printf 'Templates ready: %s\n' "$templates_dir"
