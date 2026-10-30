# Build and validation report

Release: `5.6.40-47.3.el6.local.i686`. GitHub tag: `v5.6.40-47.3-el6-i686`. Prepared on 2026-10-30.

## Result

The recorded build produced 33 conventional PHP binary RPMs and one source RPM. Its wrapper returned **exit 6 because regression validation was not clean**. The original test outcomes remain below. Successful focused tests do not convert broad-suite failures into passes.

The maintainer reports successful production use with Apache 2.2, VestaCP and legacy applications. No independent production audit is claimed.

## Inputs and build environment

- Conventional Remi packaging combined with the July 2026 security baseline, revision `7df1c2b14e40d1c9f84b2903e925ef4c9f6d2373`.
- PHP2Shell minimal Remi patch from `Anton-Barinov/php2shell-patches`, plus the local allocation/lifecycle correction, PHP 5.6 OpenSSL test adaptation, test certificate renewal and LDAP host-length initialization.
- 18 declared source inputs, 96 declared patches and one spec. The EL6 build applies 93 patches.
- CentOS 6 32-bit userland in Docker on a newer host kernel. The recorded base image ID is in [BUILD.md](docs/BUILD.md).
- Optional debuginfo omitted for the EL6 RPM debugedit path limitation. No claim of bit-for-bit reproducibility.

## Full regression results

| Suite | Total | PASS | SKIP | FAIL | WARN | XFAIL |
|---|---:|---:|---:|---:|---:|---:|
| Spec FPM `%check` | 13,860 | 7,949 | 5,863 | 11 | 4 | 33 |
| Full NTS/CGI | 14,195 | 11,710 | 2,385 | 55 | 8 | 37 |
| Full ZTS | 14,195 | 11,484 | 2,619 | 48 | 8 | 36 |
| Full FPM | 13,860 | 7,950 | 5,862 | 11 | 4 | 33 |

The original report records passing targeted checks for Apache/FPM worker lifecycle, seven CGI multipart cases, MySQL APIs, extensions and ELF linkage. Candidate package transactions covered 47.2 to 47.3 and back. They do not establish rollback to the historical Remi installation. See [VALIDATION.md](docs/VALIDATION.md) for failure categories, skipped security tests and environment limits.

## Publication verification

The publication check on 2026-10-30 independently verified all original source/distribution manifests, signatures on 38 RPM artifacts, and the OpenPGP signature on the existing four-entry archive manifest. It extracted the source RPM and matched all 115 source/spec files to the delivered build kit. Every member of both signed archives matched the provided release tree.

The runtime suites and full compilation were not repeated during publication preparation. Their results are retained from the supplied validation records. The prior signing report records unchanged main headers and compressed payloads for the 34 maintainer-signed packages.

## Repeating checks

Use [BUILD.md](docs/BUILD.md) for the build and [LOCAL_VALIDATION.md](docs/LOCAL_VALIDATION.md) for isolated runtime checks. Preserve nonzero exit status, failure summaries and skipped cases. Source and binary identities are recorded in [source-provenance.json](docs/source-provenance.json) and [SIGNING_VERIFICATION.json](docs/SIGNING_VERIFICATION.json).

The signed archives preserve the original build snapshot. The repository adds this report, presentation, explicit credits and the maintainer's MIT permission. These documentation changes do not alter the RPMs or source inputs.
