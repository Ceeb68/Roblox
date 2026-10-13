#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "$0")/.." && pwd)"
repo_dir="$(cd -- "$project_dir/.." && pwd)"
bash "$project_dir/tools/check.sh"
bash "$project_dir/tools/export.sh" windows
python3 - "$project_dir" "$repo_dir/downloads" <<'PY'
import hashlib
import pathlib
import sys
import zipfile

project, downloads = map(pathlib.Path, sys.argv[1:])
downloads.mkdir(exist_ok=True)
files = {
    'DirtlineMX.exe': project / 'build/windows/DirtlineMX.exe',
    'DirtlineMX.pck': project / 'build/windows/DirtlineMX.pck',
    'READ_ME_FIRST.txt': project / 'PLAYER_GUIDE.txt',
    'THIRD_PARTY_NOTICES.txt': project / 'THIRD_PARTY_NOTICES.txt',
}
archive = downloads / 'DirtlineMX-Windows.zip'
with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as package:
    for name, source in files.items():
        if not source.is_file() or source.stat().st_size == 0:
            raise SystemExit(f'Missing release file: {source}')
        package.write(source, 'DirtlineMX-Windows/' + name)
with zipfile.ZipFile(archive) as package:
    if package.testzip() is not None:
        raise SystemExit('Windows ZIP integrity failed')
    for name, source in files.items():
        if package.read('DirtlineMX-Windows/' + name) != source.read_bytes():
            raise SystemExit(f'Packaged file differs from export: {name}')
if archive.stat().st_size >= 100 * 1024 * 1024:
    raise SystemExit('Release exceeds normal GitHub file size; use release assets')
digest = hashlib.sha256(archive.read_bytes()).hexdigest()
(downloads / 'SHA256SUMS').write_text(f'{digest}  DirtlineMX-Windows.zip\n')
print(f'Windows package verified: {archive.stat().st_size:,} bytes; SHA-256 {digest}')
PY
