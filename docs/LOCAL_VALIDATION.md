# Local runtime replay

These helpers start isolated fixtures only. They must not run on an existing server. All 33 packages are intentionally installed in this disposable coverage fixture, this is not the package selection recommended for a production system. The public release omits old 47.2 packages and historical transaction logs, so it does not include the earlier candidate-to-candidate replay.

The full source suites run through [BUILD.md](BUILD.md). The following recipe uses the delivered signed packages, a fresh local CentOS 6 i386 container, authenticated archive dependencies, and the host public CA bundle. It was adapted to the cleaned directory layout, the package tests themselves are unchanged from the recorded local checks.

Run from the repository root on the Docker host:

```bash
set -euo pipefail
release_root=$(pwd -P)
results=$(mktemp -d /tmp/php56-runtime-results.XXXXXXXX)
chmod 755 "$results"
fixture=php56-release-test-$$
image=${PHP56_BUILD_IMAGE:-i386/centos:6}
docker_local() {
  env -u DOCKER_HOST -u DOCKER_CONTEXT -u DOCKER_TLS -u DOCKER_TLS_VERIFY \
    -u DOCKER_CERT_PATH docker --host=unix:///var/run/docker.sock "$@"
}
docker_local image inspect "$image"
docker_local run -d --name "$fixture" --platform linux/386 --network bridge \
  --mount "type=bind,src=$release_root,dst=/artifact,readonly" \
  --mount "type=bind,src=$results,dst=/evidence" \
  --mount type=bind,src=/etc/ssl/certs/ca-certificates.crt,dst=/run/php56-host-ca.pem,readonly \
  -e PHP56_ISOLATED_VALIDATION=1 --entrypoint /bin/bash "$image" \
  -c 'exec tail -f /dev/null'
trap 'docker_local rm -f "$fixture" >/dev/null' EXIT
docker_local exec "$fixture" bash /artifact/scripts/prepare_mysql_runtime_dependencies.sh \
  /artifact/dist /evidence/dependencies "$(id -u)" "$(id -g)"
docker_local exec "$fixture" bash /artifact/scripts/setup_runtime_fixture.sh --install \
  /artifact/dist /artifact/dist/RPMS/i686 47.3.el6.local \
  /artifact/dist/keys/RPM-GPG-KEY-artem-loboda-php56 \
  B07748530C39253A9E8520F56100DD2FE34B4B53 /evidence/install
docker_local network disconnect bridge "$fixture"
docker_local exec "$fixture" bash /artifact/scripts/validation/run_isolated_runtime.sh \
  /evidence/runtime-smoke mysqlnd
docker_local exec "$fixture" bash /artifact/scripts/validation/mysql_fixture.sh \
  /evidence/mysql
docker_local exec "$fixture" python /artifact/scripts/validation/targeted/run_mime_cgi.py \
  /usr/bin/php-cgi /evidence/multipart
docker_local exec "$fixture" bash /artifact/scripts/validation/targeted/run_apache_lifecycle.sh \
  /evidence/apache 47.3.el6.local
docker_local exec "$fixture" bash /artifact/scripts/prepare_runtime_test_user.sh
docker_local exec --user 1000:1000 "$fixture" \
  bash /artifact/scripts/validation/targeted/run_packaged_fpm_lifecycle.sh \
  /artifact/scripts/validation/targeted/fcgi.inc /evidence/unprivileged/fpm 47.3.el6.local
docker_local exec "$fixture" chown -R "$(id -u):$(id -g)" /evidence
docker_local rm -f "$fixture"
trap - EXIT
printf 'Results retained locally: %s\n' "$results"
```

Keep nonzero statuses and their output. Missing archives, expired/untrusted signing keys or test failures are reasons to investigate, not to disable checks. The maintainer key expires on 2029-10-28, a later key renewal or rotation needs the verified updated public key and, if RPMs are re-signed, updated checksums.

Only the container's loopback services are used after installation. MySQL uses a private socket, and Apache/FPM fixtures own and clean up their children. FPM runs under the dedicated nonroot test account. The host kernel is shared with the container, so this does not reproduce every EL6 kernel or SELinux behavior.

