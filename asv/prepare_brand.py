#!/usr/bin/env python3
"""Install supplied official brand resources before compiling any binaries."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct

ROOT = Path(__file__).resolve().parents[1]
BRAND = ROOT / 'asv' / 'brand'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    files = ['logo.png', 'icon.png', 'icon.ico']
    for name in files:
        p = BRAND / name
        if not p.is_file():
            raise SystemExit(f'Missing official ASV resource: {p}. No placeholder release allowed.')
        data = p.read_bytes()
        if name.endswith('.png'):
            if data[:8] != b'\x89PNG\r\n\x1a\n' or len(data) < 24:
                raise SystemExit(f'Invalid PNG: {p}')
            width, height = struct.unpack('>II', data[16:24])
            if not width or not height:
                raise SystemExit(f'Empty PNG: {p}')
            if name == 'icon.png' and (width != height or width < 256):
                raise SystemExit('icon.png must be square and at least 256x256.')
        else:
            if data[:4] != b'\0\0\1\0' or len(data) < 22:
                raise SystemExit(f'Invalid Windows ICO: {p}')
            count = struct.unpack('<H', data[4:6])[0]
            if not count or len(data) < 6 + 16 * count:
                raise SystemExit('Truncated ICO directory.')
            sizes = set()
            for i in range(count):
                entry = data[6+16*i:22+16*i]
                w, h = entry[0] or 256, entry[1] or 256
                size, offset = struct.unpack('<II', entry[8:16])
                if not size or offset < 6 + 16*count or offset + size > len(data):
                    raise SystemExit('Invalid ICO image offset.')
                if w == h:
                    sizes.add(w)
            if not {16, 32, 48, 256}.issubset(sizes):
                raise SystemExit('icon.ico must include 16, 32, 48 and 256 pixel images.')
    if args.check:
        print('Official brand files present; visual approval is still required.')
        return
    source_url = os.environ.get('ASV_SOURCE_URL')
    if not source_url:
        repo = os.environ.get('GITHUB_REPOSITORY')
        sha = os.environ.get('GITHUB_SHA')
        if not repo or not sha:
            raise SystemExit('Set ASV_SOURCE_URL to the corresponding public source commit URL.')
        source_url = f'https://github.com/{repo}/tree/{sha}'
    if not source_url.startswith('https://') or any(c in source_url for c in "'\"\r\n$\\"):
        raise SystemExit('Invalid source URL.')
    mapping = {
        'icon.ico': ['res/icon.ico', 'res/tray-icon.ico',
                     'flutter/windows/runner/resources/app_icon.ico', 'flutter/assets/icon.ico'],
        'icon.png': ['res/icon.png', 'flutter/assets/icon.png'],
        'logo.png': ['flutter/assets/logo.png', 'flutter/assets/logo_light.png',
                     'flutter/assets/logo_dark.png'],
    }
    for source, targets in mapping.items():
        for target in targets:
            shutil.copyfile(BRAND / source, ROOT / target)
    for theme in ['light', 'dark']:
        p = BRAND / f'logo_{theme}.png'
        if p.exists():
            shutil.copyfile(p, ROOT / 'flutter/assets' / p.name)
    about = ROOT / 'flutter/lib/desktop/pages/desktop_setting_page.dart'
    text = about.read_text()
    if 'ASV_SOURCE_URL' not in text:
        raise SystemExit('Source link has already been prepared. Use a clean checkout.')
    about.write_text(text.replace('ASV_SOURCE_URL', source_url))
    manifest = {
        'source_url': source_url,
        'upstream': json.loads((ROOT / 'asv/upstream.json').read_text()),
        'branding_sha256': {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                            for p in BRAND.iterdir() if p.suffix in ('.png', '.ico')},
    }
    (ROOT / 'asv/build-manifest.json').write_text(json.dumps(manifest, indent=2))
    print('ASV resources installed in the official Windows and Flutter paths.')


if __name__ == '__main__':
    main()
