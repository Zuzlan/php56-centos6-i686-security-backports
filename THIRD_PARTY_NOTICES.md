# Authors and third-party notices

Release author and maintainer: **Artem Loboda - [www.zuzlan.name](https://www.zuzlan.name)**.

PHP was developed by the PHP Group and its contributors, the full upstream [CREDITS](licenses/php/CREDITS) and [PHP license](licenses/php/LICENSE) are retained. Remi Collet and the original RPM maintainers retain their packaging and backport attribution in the spec and patches. Zend, TSRM, FPM and bundled libraries retain their notices under [licenses/php](licenses/php).

The PHP source RPM reports the license expression `PHP and Zend and BSD and MIT and ASL 1.0`. This is package metadata, not a replacement for the individual terms. The complete PHP source and patches accompany the binary release. See [binary redistribution notices](licenses/php/README.REDIST.BINS).

This product includes software developed by the Apache Group for use in the Apache HTTP server project (http://www.apache.org/).

| External package | RPM license tag | Copied notices |
|---|---|---|
| libzip5 | BSD | [libzip license](licenses/dependencies/libzip5/usr/share/doc/libzip5-1.7.3/LICENSE) |
| php-pecl-jsonc, php-pecl-jsonc-devel | PHP and MIT and Public Domain | [JSON license](licenses/dependencies/php-pecl-jsonc/usr/share/doc/pecl/json/LICENSE), [json-c license](licenses/dependencies/php-pecl-jsonc/usr/share/doc/pecl/json/json-c/COPYING), corresponding credits/authors |
| php-pecl-zip | PHP | [ZIP license](licenses/dependencies/php-pecl-zip/usr/share/doc/pecl/zip/LICENSE), corresponding credits |

The JSONC development package shares the JSONC source and has no separate documentation payload. Exact versions, source-RPM names and upstream project URLs are recorded in [dependency-packages.json](docs/dependency-packages.json). The external RPMs are unchanged archive packages, their original notices also remain installed in their RPM payloads.


## PHP2Shell and upstream security work

The minimal Remi patch in `build-kit/SOURCES/php-5.6-minimal-remicollet.patch` comes from [Anton Barinov and contributors](https://github.com/Anton-Barinov/php2shell-patches/blob/5eeffd651f236da9bdc2356a3f2c5d660ea0fabd/patches/php-5.6-minimal-remicollet.patch). The project identifies php-src-derived patches as PHP License 3.01. This release uses the minimal patch with additional local corrections, not the project's enhanced upload-progress implementation.

The local lifecycle correction was reviewed against the [official minimal EOL backport](https://github.com/php/php-src/commit/712e60f9edfd03f0960fc4fc3c2c375f42b90aa2). Remi Collet, Arnaud Le Blanc, David Carlier and other upstream contributors retain their attribution in commits, spec and patch headers. The release does not imply endorsement by the PHP Group or upstream patch maintainers.
