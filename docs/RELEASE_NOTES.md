# Release 5.6.40-47.3.el6.local

Prepared: **2026-10-30**. Target: CentOS/RHEL 6, **i686**. Author and maintainer: [Artem Loboda](https://www.zuzlan.name).

The maintainer reported that this release works successfully on the production server on 2026-10-30. This is a maintainer report, no independent production inspection or application audit is claimed.

## Changes

- Retains conventional Remi `php-*` packaging, Apache 2.2 integration, CLI, CGI, FPM, OPcache and NTS/ZTS modules.
- Incorporates the July 2026 Remi security patch baseline and reviewed October allocation-failure and request-state backports.
- Adds the October lifecycle correction for allocation failures, string-size checks, freed SAPI pointers, linked-list state, executor state and multipart header handling, reviewed against the [official minimal upstream fix](https://github.com/php/php-src/commit/712e60f9edfd03f0960fc4fc3c2c375f42b90aa2).
- Initializes the optional LDAP host length, fixing an uninitialized value when calling `ldap_connect()` without arguments.
- Adapts an OpenSSL test option to PHP 5.6 and renews test-only TLS certificates. Runtime trust settings are unchanged.
- Repairs the EL6 build controls, enforces an i686 target, records build/test exit status and runs supplemental regression suites without root privileges.

The final source RPM contains 18 declared source inputs, 96 declared patches and the spec. The EL6 build applies 93 patches, the three remaining declarations are conditional upstream compatibility patches.

## Runtime differences

**Session upload-progress reporting is disabled**, even when its INI setting says On. Ordinary multipart uploads have separate validation coverage.

**Hardened allocation failures exit the worker immediately** with `_exit(1)`. Normal shutdown callbacks, flushing and session cleanup may not run. Test application durability and supervisor recovery.

**MySQL uses mysqlnd.** A system previously using the `php-mysql` libmysqlclient backend needs an explicit migration and rollback rehearsal. External or custom extensions must match the supplied PHP ABI.

## Validation and distribution

All 33 final packages passed metadata and installed-payload checks. Isolated Apache/FPM lifecycle, MySQL API, extension, ELF/linkage and candidate upgrade/downgrade checks passed. The full PHPT suites retain failures and skipped security cases, [VALIDATION.md](VALIDATION.md) records the aggregate results and limits.

The public release omits transient build logs, failed-run artifacts, operational permission backups and private signing material. Upstream tests and regression scripts remain available. Removing intermediate artifacts does not change the recorded validation result. Release signing changes RPM signature headers and file hashes while preserving the tested main headers and payloads.

All 33 PHP binary RPMs and the source RPM use Artem Loboda's dedicated RSA-4096/SHA-256 release key, fingerprint `B07748530C39253A9E8520F56100DD2FE34B4B53`, expiring 2029-10-28. The download manifest has a detached OpenPGP signature. The four external dependency RPMs retain their original Remi signatures. See [SIGNATURES.md](SIGNATURES.md) for verification and key trust instructions.
