# Validation scope

Release: **PHP 5.6.40-47.3.el6.local.i686**. The maintainer reported successful production use on **2026-10-30**. The results below describe separate, isolated local validation, they do not claim an independent production audit.

The public packages were subsequently signed with the maintainer release key without changing their main headers or compressed payloads. Signature verification and before/after package hashes are recorded in [SIGNING_VERIFICATION.json](SIGNING_VERIFICATION.json). The runtime checks below were performed before this signature-only change, they were not repeated for signing.

## Completed checks

| Check | Result and scope |
|---|---|
| RPM metadata | All 33 conventional PHP packages have the expected release, i686 architecture and package layout. |
| Installed payloads | Package payload/signature checks passed, only six intentionally modified configuration files differed. |
| ELF and dynamic linking | 130 paths checked: 128 regular files and two aliases, all ELF32 Intel 80386, highest required GLIBC symbol version 2.11, no unresolved libraries. |
| CLI, Apache 2.2 and extensions | Functional smoke checks passed, including JSON/ZIP, OPcache and the tested extensions. |
| FPM and Apache lifecycle | Each passed 200 requests in one worker, authentication/handler/exception isolation, forced allocation-failure exit and healthy replacement-worker checks. |
| MySQL APIs | Socket-only MySQL 5.1 fixture passed through `mysql`, `mysqli` and PDO native/emulated prepares, including transactions, UTF-8, binary data, decimals and NULL. |
| CGI multipart handling | Seven packaged-binary cases passed. |
| Package transactions | All 33 packages passed 47.2 → 47.3 → 47.2 → 47.3, six marked configuration files were preserved. |
| Focused regressions | 20 executor/error/shutdown PHPTs, 15 affected TLS tests and three supplemental packaged SOAP tests passed. LDAP no-argument checks and 10,000 handle cycles passed for NTS and ZTS. |

The package transaction test used locally built candidate versions. It did not validate an exact upgrade from or rollback to `5.6.40-9.el6.remi`. The maintainer's later production report does not establish that rollback was rehearsed.

## Full regression results

These are the original aggregate outcomes. Explanatory reruns and supplemental tests do not convert failures or skips into passes.

| Suite | Total | PASS | SKIP | FAIL | WARN | XFAIL |
|---|---:|---:|---:|---:|---:|---:|
| Spec FPM `%check` | 13,860 | 7,949 | 5,863 | 11 | 4 | 33 |
| Full NTS/CGI | 14,195 | 11,710 | 2,385 | 55 | 8 | 37 |
| Full ZTS | 14,195 | 11,484 | 2,619 | 48 | 8 | 36 |
| Full FPM | 13,860 | 7,950 | 5,862 | 11 | 4 | 33 |

All three supplemental suites completed. The build wrapper returned **6** because validation was not clean, after producing the RPMs. `WARN` includes expected-failure tests that unexpectedly passed, a non-debug build cannot establish the absence of memory leaks from those outcomes.

Reviewed failure categories include the eight intentionally disabled session upload-progress tests, historical date/ICU/timezone expectations, DBA behavior and obsolete directives, missing Firebird/ODBC fixtures, offline network assumptions, container privilege and 32-bit socket behavior, diagnostic wording/order and expired FTPS test certificates. Three SOAP tests passed separately with the installed module and a fixture-only launcher, their original broad-suite failures remain in the table.

Raw failed-run logs and generated test artifacts are excluded from the public release. The build and regression scripts remain available so results can be reproduced and reviewed.

## Security and environment limits

Full suites ran unprivileged with external networking and explicitly slow tests disabled. NTS and ZTS loaded every configured shared module and OPcache. The separate FPM build's CLI has no shared modules, installed FPM lifecycle checks supplement its narrower PHPT coverage. A local SNMP fixture supplied loopback-only service coverage.

Some security regressions remain skipped or unsupported: large LDAP overflow inputs require about 1.4 GB plus copies, the PDO SQLite overflow PHPT requires about 2.1 GB, a PostgreSQL regression requires a database fixture, EL6 OpenSSL lacks usable AES-WRAP-PAD, one Phar test is unconditionally skipped upstream, and SQLite defensive mode requires a newer library. A bounded exact-source PDO SQLite supplement passed its four boundary/normal cases, but it is not a pass of the original large-input PHPT.

The October source-function fault/reset checks passed seven cases, including six that distinguished the uncorrected control. Together with packaged CGI/FPM/Apache tests, these support the specific behaviors exercised. They do not prove universal exploit resistance across every SAPI, extension, configuration or application.

Tests used EL6 userland in containers on a newer host kernel. Actual EL6 kernel/SELinux behavior, independently packaged extensions, application/database integrity, exact historical package rollback and the rest of the EOL operating system are outside the independently tested scope. Archived dependency signatures establish origin and integrity, not freedom from vulnerabilities.

Session upload-progress callbacks are disabled. Hardened allocation failure exits bypass normal shutdown callbacks and cleanup. Both are observable compatibility changes that applications need to account for.
