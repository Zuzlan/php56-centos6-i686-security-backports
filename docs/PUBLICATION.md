# Public release contents

Author: **Artem Loboda - [www.zuzlan.name](https://www.zuzlan.name)**.

This public tree contains final source/spec/patches, build controls, selected reusable validation helpers, final RPMs, public verification keys, licenses and concise documentation. Historical build attempts, generated test results, failed-run logs, scratch programs, old candidate RPMs, backup copies, local ACL state and generated test CA private keys are excluded.

The aggregate validation results and relevant compatibility limits remain in [VALIDATION.md](VALIDATION.md). Removing old test output does not change those outcomes. The maintainer's report of successful production use on 2026-10-30 is recorded separately from the local test results.

## Public source fixtures

The unchanged upstream PHP source contains TLS private-key **test fixtures** under its test directories. Two retained certificate patches also contain existing fixture-key context. These deliberately distributed test inputs are public source data, not deployment credentials. They are retained to preserve the exact source and regression tests. They must never be used as real service identities. The generated CA private keys used during local certificate renewal and the RPM signing private key are not included.

## Publish

Use the repository root for Git source control. `.gitignore` excludes `dist/`, generated build/test output and common private-key files. Publish the prepared archives, public key, asset checksums and detached `SHA256SUMS.asc` signature as release downloads, that archive includes `dist/`, corresponding PHP source, licenses and documentation. The separate source archive contains the Git-ready tree without binary RPMs.

GitHub tag: `v5.6.40-47.3-el6-i686`. Suggested release title: `PHP 5.6.40-47.3 for CentOS 6 i686`. [RELEASE_NOTES.md](RELEASE_NOTES.md) is ready to use as the release description. No repository, remote commit, tag or GitHub release was created by this preparation.


To regenerate download archives from a verified full tree, choose a new output directory:

```bash
python3 scripts/verify_release.py --with-dist
python3 scripts/package_release.py ../php56-release-assets-new
```

The packager creates unsigned asset checksums. Sign them with the maintainer key before publishing, following [SIGNATURES.md](SIGNATURES.md). Keep the private key and revocation certificate outside the repository and release assets.

The packager includes only files listed in the verified source and distribution manifests. It normalizes archive ownership and timestamps, and refuses to overwrite an existing output directory.

## Repository and signed snapshot

The signed source and full archives preserve the original build snapshot. The Git repository adds a presentation README, BUILD_REPORT.md, explicit upstream credits and the maintainer MIT permission. LICENSE and LICENSE-MIT supplement the older license notice for the maintainer original contributions in the snapshots. RPMs and all 115 source/spec inputs remain unchanged.

Individual RPMs are also provided as Release assets, with RPM-SHA256SUMS. This extra manifest is unsigned, so verify package signatures as well. The original signed SHA256SUMS covers only the four assets listed in that file.
