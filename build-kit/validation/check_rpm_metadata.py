#!/usr/bin/env python
"""Read-only checks; compatible with EL6 Python 2.6 and Python 3.

Usage: python check_rpm_metadata.py CORE_RPM_DIR RELEASE OUTPUT_JSON
CORE_RPM_DIR contains only the newly built PHP source-package outputs.
External php-pecl-jsonc and php-pecl-zip RPMs belong in a separate directory.
"""
from __future__ import print_function
import json
import os
import re
import subprocess
import sys


def run(args):
    proc = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    out, err = proc.communicate()
    if not isinstance(out, str):
        out = out.decode('utf-8', 'replace')
        err = err.decode('utf-8', 'replace')
    if proc.returncode:
        raise RuntimeError('%r failed: %s' % (args, err.strip()))
    return out


def main():
    if len(sys.argv) != 4:
        print(__doc__, file=sys.stderr)
        return 2
    rpm_dir, release, output = sys.argv[1:]
    errors, records = [], []
    paths = []
    for base, dirs, files in os.walk(rpm_dir):
        for filename in files:
            if filename.endswith('.rpm'):
                paths.append(os.path.join(base, filename))
    if not paths:
        errors.append('No RPMs found: metadata validation did not run.')
    packages = {}
    for path in sorted(paths):
        try:
            header = run(['rpm', '-qp', '--qf',
                          '%{NAME}\t%{VERSION}\t%{RELEASE}\t%{ARCH}\t%{SOURCERPM}\n', path]).strip().split('\t')
            if len(header) != 5:
                raise RuntimeError('Unexpected RPM header output')
            name, version, rpm_release, arch, source = header
            provides = run(['rpm', '-qp', '--provides', path]).splitlines()
            requires = run(['rpm', '-qp', '--requires', path]).splitlines()
            rows = run(['rpm', '-qp', '--qf', '[%{FILENAMES}\t%{FILEFLAGS}\t%{FILEMODES}\n]', path]).splitlines()
            files = {}
            for row in rows:
                filename, flags, mode = row.split('\t')
                files[filename] = {'flags': int(flags), 'mode': int(mode)}
            record = dict(path=path, name=name, version=version, release=rpm_release,
                          arch=arch, source_rpm=source, provides=provides, requires=requires,
                          files=files,
                          obsoletes=run(['rpm', '-qp', '--obsoletes', path]).splitlines(),
                          conflicts=run(['rpm', '-qp', '--conflicts', path]).splitlines(),
                          scriptlets=run(['rpm', '-qp', '--scripts', path]))
            records.append(record)
            if name in packages:
                errors.append('%s: duplicate package name' % name)
            packages[name] = record
            if name != 'php' and not name.startswith('php-'):
                errors.append('%s: package is not conventional php-*' % name)
            if arch != 'i686':
                errors.append('%s: architecture %s, required i686' % (name, arch))
            if version != '5.6.40' or rpm_release != release:
                errors.append('%s: unexpected version-release %s-%s' % (name, version, rpm_release))
            if source != 'php-5.6.40-%s.src.rpm' % release:
                errors.append('%s: unexpected source RPM %s' % (name, source))
            for dependency in requires:
                if '(64bit)' in dependency or 'x86-64' in dependency:
                    errors.append('%s: 64-bit dependency %s' % (name, dependency))
                for symbol in re.findall(r'GLIBC_([0-9]+(?:\.[0-9]+)+)', dependency):
                    if tuple(int(part) for part in symbol.split('.')) > (2, 12):
                        errors.append('%s: glibc newer than 2.12: %s' % (name, dependency))
                if re.search(r'(^|\s)(php56-php|rh-php|/opt/remi|/opt/rh)', dependency):
                    errors.append('%s: Software Collections dependency %s' % (name, dependency))
                if re.match(r'^php-(?:common|pdo|xml|cli)(?:\([^)]*\))?\s', dependency):
                    if not dependency.endswith(' = 5.6.40-' + release):
                        errors.append('%s: internal dependency is not pinned to this build: %s' % (name, dependency))
            if name != 'php-common' and not any(
                    re.match(r'^php-(?:common|pdo|xml|cli)(?:\([^)]*\))? = 5\.6\.40-' + re.escape(release) + r'$', item)
                    for item in requires):
                errors.append('%s: no exact-version dependency on the core PHP package family' % name)
            for filename, metadata in files.items():
                if filename.startswith(('/opt/remi/', '/opt/rh/', '/usr/lib64/')):
                    errors.append('%s: incompatible path %s' % (name, filename))
                if (metadata['mode'] & 61440) == 16384:
                    continue
                if filename.startswith('/etc/') and (filename.endswith(('.ini', '.conf')) or 'opcache-default.blacklist' in filename):
                    if metadata['flags'] & 17 != 17:
                        errors.append('%s: missing config(noreplace) on %s' % (name, filename))
        except (OSError, RuntimeError, ValueError) as exc:
            errors.append('%s: %s' % (path, exc))
    required = ('php php-cli php-common php-fpm php-opcache php-pdo php-gd '
                'php-intl php-mbstring php-mcrypt php-xml php-ldap php-gmp').split()
    for name in required:
        if name not in packages:
            errors.append('Missing required package %s' % name)
    if not any(name in packages for name in ('php-mysql', 'php-mysqlnd')):
        errors.append('Missing MySQL backend package (php-mysql or php-mysqlnd)')
    needed_files = {
        'php': ['/usr/lib/httpd/modules/libphp5.so', '/etc/httpd/conf.d/php.conf'],
        'php-cli': ['/usr/bin/php', '/usr/bin/php-cgi'],
        'php-common': ['/etc/php.ini', '/usr/lib/php/modules'],
        'php-fpm': ['/usr/sbin/php-fpm', '/etc/rc.d/init.d/php-fpm', '/etc/php-fpm.conf', '/etc/php-fpm.d/www.conf'],
        'php-opcache': ['/usr/lib/php/modules/opcache.so', '/etc/php.d/10-opcache.ini']}
    for name, filenames in needed_files.items():
        for filename in filenames:
            if name in packages and filename not in packages[name]['files']:
                errors.append('%s: missing required path %s' % (name, filename))
    for name, abi in [('php-common', 'php(api) = 20131106-32'),
                      ('php-common', 'php(zend-abi) = 20131226-32'),
                      ('php-pdo', 'php(pdo-abi) = 20080721-32')]:
        if name in packages and abi not in packages[name]['provides']:
            errors.append('%s: missing ABI %s' % (name, abi))
    if 'php' in packages:
        dependencies = packages['php']['requires']
        if not any(item.startswith('httpd-mmn = 20051115') for item in dependencies):
            errors.append('php: Apache 2.2 httpd-mmn dependency missing/wrong')
    if 'php-mysqlnd' in packages:
        if 'php-mysql = 5.6.40-' + release not in packages['php-mysqlnd']['provides']:
            errors.append('php-mysqlnd: expected php-mysql compatibility Provide missing')
    if 'php-common' in packages:
        for dependency in ('php-pecl-jsonc', 'php-pecl-zip'):
            if not any(re.match(re.escape(dependency) + r'(?:\(|\s|$)', item)
                       for item in packages['php-common']['requires']):
                errors.append('php-common: missing external %s dependency; inspect bootstrap setting' % dependency)
    report = {'status': 'FAIL' if errors else 'PASS_METADATA_ONLY', 'errors': errors,
              'release': release, 'packages': records,
              'limitations': [
                  'Does not install RPMs or establish signatures, complete dependencies, or runtime safety.',
                  'Both mysql alternatives may be archived; install exactly the baseline-selected backend.',
                  'Compare ABI/EVR/configs and all third-party extensions against the exact offline production baseline.',
                  'External JSONC/zip and dependency RPMs require independent signature, security, ABI and runtime validation.']}
    with open(output, 'w') as handle:
        json.dump(report, handle, indent=2, sort_keys=True)
        handle.write('\n')
    print('%s: %d RPM(s), %d issue(s); %s' % (report['status'], len(records), len(errors), output))
    for error in errors:
        print('FAIL: ' + error, file=sys.stderr)
    return 1 if errors else 0


if __name__ == '__main__':
    sys.exit(main())
