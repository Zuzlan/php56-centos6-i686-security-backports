#!/usr/bin/env bash
# Run only on the local build host. No production connections.
set -Eeuo pipefail
umask 022
DIR=$(realpath -e -- "${1:-./php56-el6-build-kit}")
mkdir -p "$DIR/logs"
LOG_DIR=$(mktemp -d "$DIR/logs/run-$(date -u +%Y%m%dT%H%M%SZ)-XXXXXXXX")
RUN_ID=${LOG_DIR##*/}
trap 'rc=$?; printf "%s\n" "$rc" > "$LOG_DIR/driver.exit-status"; date -u +%Y-%m-%dT%H:%M:%SZ > "$LOG_DIR/driver.finished-utc"' EXIT
date -u +%Y-%m-%dT%H:%M:%SZ > "$LOG_DIR/driver.started-utc"
run_build() {
set -Eeuo pipefail
printf 'Run: %s\nKit: %s\nLogs: %s\n' "$RUN_ID" "$DIR" "$LOG_DIR"
# BUILD and BUILDROOT are shared by the existing kit: serialize all new runs.
exec 9>"$DIR/.build.lock"
flock -n 9 || { echo 'ERROR: another build holds this kit lock.' >&2; exit 4; }
[[ -x $DIR/SPECS && -r $DIR/SPECS/php.spec && -x $DIR/SOURCES ]] || {
  echo 'ERROR: active SPECS/php.spec or SOURCES is unreadable. No build was started.' >&2
  exit 2
}
[[ -r $DIR/build_inside_el6.sh && -r $DIR/keys/RPM-GPG-KEY-EPEL-6 ]] || {
  echo 'ERROR: container script or verified EPEL key missing.' >&2; exit 2;
}
command -v docker >/dev/null || { echo 'ERROR: Docker client missing.' >&2; exit 2; }
# Explicit local daemon: saved contexts must not redirect work to another host.
docker_local() {
  env -u DOCKER_HOST -u DOCKER_CONTEXT -u DOCKER_TLS -u DOCKER_TLS_VERIFY -u DOCKER_CERT_PATH \
    docker --host=unix:///var/run/docker.sock "$@"
}
docker_local info --format '{{.ServerVersion}}' > "$LOG_DIR/docker-version.txt"
# Use the existing image; record its immutable local ID and never pull implicitly.
IMAGE_ID=$(docker_local image inspect "${PHP56_BUILD_IMAGE:-i386/centos:6}" --format '{{.Id}}')
docker_local image inspect "$IMAGE_ID" --format '{{.Id}} {{json .RepoDigests}} {{.Architecture}}' > "$LOG_DIR/image.txt"
[[ $(docker_local image inspect "$IMAGE_ID" --format '{{.Architecture}}') == 386 ]] || {
  echo 'ERROR: expected the existing CentOS 6 386 image.' >&2; exit 2;
}
sha256sum "$DIR/SPECS/php.spec" "$DIR/build_inside_el6.sh" > "$LOG_DIR/build-controls.sha256"
# Mount only task files and a public certificate bundle, never credentials/home/socket.
# Legacy NSS tools use the host CA bundle while retaining TLS verification.
network_args=()
case ${PHP56_USE_INSTALLED_BUILD_DEPS:-0} in
  0) ;;
  1) network_args=(--network none) ;;
  *) echo 'Invalid offline dependency flag' >&2; exit 2 ;;
esac
docker_local run --rm --platform linux/386 "${network_args[@]}" \
  --mount "type=bind,src=$DIR,dst=/build" \
  --mount type=bind,src=/etc/ssl/certs/ca-certificates.crt,dst=/run/php56-host-ca.pem,readonly \
  -w /build -e "BUILD_LOG_DIR=/build/logs/$RUN_ID" \
  -e "PHP56_USE_INSTALLED_BUILD_DEPS=${PHP56_USE_INSTALLED_BUILD_DEPS:-0}" \
  "$IMAGE_ID" /bin/bash /build/build_inside_el6.sh
printf 'Build script completed; packages remain candidates pending full validation.\n'
}
# Wait for tee; process substitution can lose final output in managed executors.
set +e
(run_build) 2>&1 | tee "$LOG_DIR/driver.log"
pipeline_status=("${PIPESTATUS[@]}")
set -e
rc=${pipeline_status[0]}
if [[ $rc == 0 && ${pipeline_status[1]} != 0 ]]; then rc=${pipeline_status[1]}; fi
exit "$rc"
