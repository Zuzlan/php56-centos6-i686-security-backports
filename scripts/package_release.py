#!/usr/bin/env python3
"""Create public source/full release archives from verified manifests only."""
import argparse
import gzip
import hashlib
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile

sys.dont_write_bytecode = True
from verify_release import manifest_entries

VERSION = '5.6.40-47.3'
ARCHIVE_ROOT = 'php56-el6-' + VERSION
RELEASE_EPOCH = 1793318400  # 2026-10-30 00:00:00 UTC


def archive(root, destination, names):
    with destination.open('xb') as raw:
        with gzip.GzipFile(filename='', mode='wb', fileobj=raw, mtime=RELEASE_EPOCH) as compressed:
            with tarfile.open(fileobj=compressed, mode='w') as output:
                for name in sorted(set(names)):
                    source = root / name
                    if source.is_symlink() or not source.is_file():
                        raise ValueError('Only regular manifested files may be published: ' + name)
                    info = output.gettarinfo(str(source), arcname=ARCHIVE_ROOT + '/' + name)
                    info.uid = info.gid = 0
                    info.uname = info.gname = 'root'
                    info.mtime = RELEASE_EPOCH
                    info.mode = 0o755 if source.suffix == '.sh' else 0o644
                    info.pax_headers = {}
                    with source.open('rb') as stream:
                        output.addfile(info, stream)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output_directory', help='new directory outside the repository')
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    output = Path(args.output_directory).resolve()
    if output == root or root in output.parents:
        raise ValueError('Output must be outside the repository')
    subprocess.run([sys.executable, str(root / 'scripts/verify_release.py'), '--with-dist'], check=True)
    source_names = manifest_entries(root) + ['SHA256SUMS']
    dist_names = ['dist/' + name for name in manifest_entries(root / 'dist')] + ['dist/SHA256SUMS']
    output.mkdir(parents=True, exist_ok=False)
    archive(root, output / (ARCHIVE_ROOT + '-source.tar.gz'), source_names)
    archive(root, output / (ARCHIVE_ROOT + '-full.tar.gz'), source_names + dist_names)
    shutil.copyfile(root / 'docs/RELEASE_NOTES.md', output / 'RELEASE_NOTES.md')
    shutil.copyfile(root / 'keys/RPM-GPG-KEY-artem-loboda-php56',
                    output / 'RPM-GPG-KEY-artem-loboda-php56')
    sums = []
    for path in sorted(output.iterdir()):
        result = hashlib.sha256()
        with path.open('rb') as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b''):
                result.update(block)
        sums.append(result.hexdigest() + '  ' + path.name + '\n')
    (output / 'SHA256SUMS').write_text(''.join(sums))
    print('Created source/full release archives and SHA256SUMS in', output)
    print('Sign the asset SHA256SUMS before publishing; see docs/SIGNATURES.md.')


if __name__ == '__main__':
    main()

