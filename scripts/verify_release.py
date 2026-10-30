#!/usr/bin/env python3
"""Verify repository integrity and, optionally, the delivered binary artifacts."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath


def sha256(path):
    result = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            result.update(block)
    return result.hexdigest()


def manifest_entries(base):
    entries = []
    seen = set()
    for line in (base / 'SHA256SUMS').read_text().splitlines():
        expected, name = line.split('  ', 1)
        relative = PurePosixPath(name)
        if (len(expected) != 64 or any(c not in '0123456789abcdef' for c in expected)
                or relative.is_absolute() or '..' in relative.parts
                or str(relative) != name or name in seen or name == 'SHA256SUMS'):
            raise ValueError('Invalid manifest entry: ' + name)
        path = base / name
        if (path.is_symlink() or base.resolve() not in path.resolve().parents
                or not path.is_file() or sha256(path) != expected):
            raise ValueError('Integrity check failed: ' + name)
        seen.add(name)
        entries.append(name)
    if not entries:
        raise ValueError('Empty manifest')
    return entries


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--with-dist', action='store_true', help='also verify the release RPM distribution')
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    names = manifest_entries(root)
    provenance = json.loads((root / 'docs/source-provenance.json').read_text())
    if len(provenance['source_payload']) != 115:
        raise ValueError('Expected 115 exact source/spec payload files')
    for entry in provenance['source_payload']:
        if sha256(root / entry['path']) != entry['sha256']:
            raise ValueError('Source identity changed: ' + entry['path'])
    result = {'repository_files_verified': len(names), 'source_payload_files_verified': 115}
    if args.with_dist:
        dist = root / 'dist'
        result['distribution_files_verified'] = len(manifest_entries(dist))
        main_rpms = sorted((dist / 'RPMS/i686').glob('*.rpm'))
        dependencies = sorted((dist / 'dependency-rpms').glob('*.rpm'))
        srpms = sorted((dist / 'SRPMS').glob('*.rpm'))
        if len(main_rpms) != 33 or len(dependencies) != 4 or len(srpms) != 1:
            raise ValueError('Expected 33 PHP RPMs, four dependencies and one source RPM')
        if any(not p.name.endswith('-5.6.40-47.3.el6.local.i686.rpm') for p in main_rpms):
            raise ValueError('Unexpected PHP release or architecture')
        if srpms[0].name != provenance['source_rpm'] or sha256(srpms[0]) != provenance['source_rpm_sha256']:
            raise ValueError('Source RPM identity changed')
        manifest_entries(dist / 'RPMS/i686')
        result['rpm_artifacts_verified'] = 38
    result['status'] = 'PASS_INTEGRITY'
    result['scope'] = 'Byte integrity and source identity; not a security or production certification'
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()

