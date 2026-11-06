"""Validate tag and release artifacts before publishing all macOS architectures."""
import argparse
import hashlib
import json
import os
import plistlib
import re
import shutil
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
ARCHES = {'arm64', 'x86_64', 'universal'}


def info():
    with (ROOT / 'Resources/Info.plist').open('rb') as stream:
        return plistlib.load(stream)


def version(tag=''):
    value = info()['CFBundleShortVersionString']
    if not re.fullmatch(r'\d+\.\d+\.\d+', value) or (tag and tag != 'v' + value):
        raise ValueError(f'Tag must match stable version v{value} in Resources/Info.plist')
    return value


def sha(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def collect(arch):
    value = version()
    out = ROOT / 'artifacts'
    out.mkdir(exist_ok=True)
    files = []
    for ext in ['dmg', 'app.zip']:
        name = f'LaunchpadOS_{value}_{arch}.{ext}'
        path = ROOT / 'dist' / name
        if not path.is_file() or path.stat().st_size == 0:
            raise ValueError(f'Missing or empty installer: {name}')
        shutil.copy2(path, out / name)
        files.append(dict(name=name, sha256=sha(path), bytes=path.stat().st_size))
    manifest = dict(version=value, build=info()['CFBundleVersion'], architecture=arch,
                    commit=os.getenv('GITHUB_SHA', ''), files=files)
    (out / f'manifest-{arch}.json').write_text(json.dumps(manifest, indent=2) + '\n')


def assemble():
    value = version()
    source, out = ROOT / 'artifacts', ROOT / 'release'
    manifests = [json.loads(p.read_text()) for p in sorted(source.glob('manifest-*.json'))]
    if len(manifests) != 3 or {m['architecture'] for m in manifests} != ARCHES:
        raise ValueError('Incomplete architecture matrix')
    verified = []
    for manifest in manifests:
        if manifest['version'] != value or manifest['build'] != info()['CFBundleVersion']:
            raise ValueError('Mixed installer versions')
        if os.getenv('GITHUB_SHA') and manifest['commit'] != os.environ['GITHUB_SHA']:
            raise ValueError('Mixed build commits')
        expected = {f"LaunchpadOS_{value}_{manifest['architecture']}.{ext}" for ext in ['dmg', 'app.zip']}
        if {f['name'] for f in manifest['files']} != expected:
            raise ValueError('Unexpected installer files')
        for entry in manifest['files']:
            path = source / entry['name']
            if path.stat().st_size != entry['bytes'] or sha(path) != entry['sha256']:
                raise ValueError(f'Checksum mismatch: {path.name}')
            verified.append((path, entry))
    out.mkdir(exist_ok=True)
    for path, _ in verified:
        shutil.copy2(path, out / path.name)
    (out / 'SHA256SUMS.txt').write_text(''.join(f"{e['sha256']}  {p.name}\n" for p, e in verified))
    (out / 'build-manifest.json').write_text(json.dumps(manifests, indent=2) + '\n')
    (out / 'NOTES.md').write_text(f'''LaunchpadOS {value} · Build {info()['CFBundleVersion']}

Native macOS app launcher, requires macOS 14 or newer.

- Apple Silicon: arm64 DMG / app ZIP.
- Intel: x86_64 DMG / app ZIP.
- Universal: one app containing both architectures.

Open the DMG and drag LaunchpadOS to Applications, or extract the app ZIP.
Default global shortcut: Option + Space. Search, folders, drag editing and settings are described in the README.
Packages are ad-hoc signed, without Apple Developer ID notarization. This is an independent app, not an Apple product or a system Launchpad patch.
Checksums: SHA256SUMS.txt. Build targets and commits: build-manifest.json.
''')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    sub.add_parser('version').add_argument('--tag', default='')
    sub.add_parser('collect').add_argument('--arch', choices=sorted(ARCHES), required=True)
    sub.add_parser('assemble')
    args = parser.parse_args()
    if args.command == 'version':
        print(version(args.tag))
    elif args.command == 'collect':
        collect(args.arch)
    else:
        assemble()
