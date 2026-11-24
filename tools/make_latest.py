"""Writes latest.json next to a release's APK: what the app's own update reads (version, build number, the APK's name, size
and SHA-256, what is new). Usage: python make_latest.py <pubspec.yaml> <release folder> [notes.md]

The release folder holds AVET-<version>-arm64.apk; the release must also carry the written latest.json among its files
(GitHub serves it at https://github.com/<repo>/releases/latest/download/latest.json)."""
import hashlib
import json
import re
import sys
from pathlib import Path


def main(pubspec, release, notes_file=None):
    release = Path(release)
    text = Path(pubspec).read_text(encoding='utf-8')
    m = re.search(r'^version:\s*([0-9.]+)\+([0-9]+)', text, re.M)
    version, build = m.group(1), int(m.group(2))
    apk = next(release.glob('AVET-*-arm64.apk'))
    notes = Path(notes_file).read_text(encoding='utf-8').strip() if notes_file else ''
    data = {
        'version': version,
        'build': build,
        'apk': apk.name,
        'size': apk.stat().st_size,
        'sha256': hashlib.sha256(apk.read_bytes()).hexdigest(),
        'notes': notes,
    }
    (release / 'latest.json').write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')
    print('latest.json:', version, build, apk.name, apk.stat().st_size)


if __name__ == '__main__':
    main(*sys.argv[1:])
