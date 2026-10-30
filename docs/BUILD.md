# Rebuild

Use a Linux Docker host with 32-bit x86 container support, Bash, `realpath`, `flock` and SHA-256 tools. The host public CA bundle must be available at `/etc/ssl/certs/ca-certificates.crt`. Build inside a disposable container, using an existing reviewed CentOS 6 `linux/386` image. The wrapper explicitly uses the local Docker socket and does not pull an image automatically.

The original base image ID was `sha256:498c1320b2574fc5bbf897768ffd2c510edf0af3bc4c561aa1836f64845c1c27`. Images and installed dependency caches are not bundled. A different image needs its own provenance and dependency review.

From the repository root:

```bash
sha256sum --check SHA256SUMS
PHP56_BUILD_IMAGE=i386/centos:6 \
  bash build-kit/build_in_docker.sh "$PWD/build-kit"
```

The script installs signed dependencies through the configured CentOS Vault/EPEL HTTPS archives, builds for i686, checks package metadata, and runs the full NTS/ZTS/FPM PHPT discovery. Archive availability may vary, TLS and GPG verification remain enabled. The optional `PHP56_USE_INSTALLED_BUILD_DEPS=1` mode is only for an already authenticated, prepared dependency image, it disables networking and retains RPM BuildRequires checks.

Each invocation creates `build-kit/logs/run-*`. Its `RPMS/i686/` and `SRPMS/` hold the newly built packages. `driver.exit-status` and `container.exit-status` preserve the actual result. Exit **6** means validation failed even if all RPMs were produced, the recorded release had this status. Review [VALIDATION.md](VALIDATION.md). Tests and failures are not suppressed to obtain a zero exit.

The source archive, all 114 declared source/patch files and the spec match the delivered SRPM. The build omits only the optional debuginfo subpackage to avoid the EL6 RPM 4.8 debugedit path failure. It keeps PHP security functionality and the conventional package layout.

Build/test helpers use a temporary `phpbuild` account inside the container. They do not grant host Docker permissions or modify host services. Build outputs are ignored by Git. The source tree retains upstream regression tests, including public TLS test fixtures, generated failed-run logs are not part of this repository.

Rebuilding is supported, but bit-for-bit identical RPMs are not promised: timestamps, build metadata and signing affect bytes. The public RPMs were re-signed with the maintainer release key without rebuilding or changing their main headers or payloads. Sign new builds using your private key as described in [SIGNATURES.md](SIGNATURES.md), then regenerate checksums and archive signatures.

