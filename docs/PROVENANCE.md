# Source provenance

The 33 PHP binary RPMs and source RPM were signed with Artem Loboda's dedicated release key for publication. Their signature headers and file hashes changed, their main headers and compressed payloads remain byte-identical to the locally validated release. The four external dependency RPMs retain their original bytes and Remi signatures. Publication does not rebuild or change PHP code. [SIGNING_VERIFICATION.json](SIGNING_VERIFICATION.json) records before/after hashes and verification results.

| Input | SHA-256 / revision |
|---|---|
| Conventional Remi `php-5.6.40-41.remi.src.rpm` | `2ab9078e4b437098b507124f4c0c78cd822d1e58765262963f2be36fbb6722f1` |
| July security `php56-php-5.6.40-47.remi.src.rpm` | `7eae0e7e02389808ecb413ddd4572f26dbf3d36078f2ccd110511b6b78556b5b` |
| Pristine stripped PHP Source0 | `4ea784f18c225fd3bb9b2477b42051119b289038e16df840bd4249784f875590` |
| Remi July Git baseline | `7df1c2b14e40d1c9f84b2903e925ef4c9f6d2373` |
| Final `php-5.6.40-47.3.el6.local.src.rpm` | `2043ae9a3d23eaa8ea813ae1ca1b8747cec816309968c40bd2bc33a10d44a369` |

Both original SRPM signatures were checked against the published Remi keys: 2024 fingerprint `CF1DF0057CE85DFF5B2F2A37C2FD3B2C2A0948E4`, 2026 fingerprint `2E375FE24EDFF0F2E0D8E165ED5B58C5BEFA00E2`. See [Remi's published key information](https://blog.remirepo.net/pages/Config-en).

The final SRPM contains 18 declared sources, 96 declared patches and one spec: 115 files. Exactly 93 patches apply in this EL6 build, including all 76 audited security-related/new layers. The other three declarations are original conditionals for newer ICU, LDAP linkage and PCRE test compatibility. Active patches were checked for applicability and duplicate application. [source-provenance.json](source-provenance.json) records every delivered source/spec digest and the added local patch identities.

The original October patch is retained. Patch282 supplies additional PHP 5.6 allocation and lifecycle corrections reviewed against the [official minimal EOL backport](https://github.com/php/php-src/commit/712e60f9edfd03f0960fc4fc3c2c375f42b90aa2), with bounded local checks. Patch283 adapts one regression to PHP 5.6's available OpenSSL options. Patch284 renews test certificate validity without changing runtime trust. Patch285 initializes the optional LDAP host length to zero, fixing the tested no-argument connection path.

The October advisory references are [allocation-failure handling](https://github.com/php/php-src/security/advisories/GHSA-w8hw-w9fx-j79w) and [request-state cleanup](https://github.com/php/php-src/security/advisories/GHSA-6wmf-4rv5-p3rp). The available evidence and untested cases are summarized in [VALIDATION.md](VALIDATION.md), this release does not claim every advisory or memory-safety property is fully validated.

All 33 conventional PHP packages and their Provides/Requires/file layouts are listed in [package-metadata.json](package-metadata.json). Original external package license/source identities are listed in [dependency-packages.json](dependency-packages.json).

