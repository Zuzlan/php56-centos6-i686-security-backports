#!/bin/bash
# Verify only; uses a disposable offline container and read-only public inputs.
set -Eeuo pipefail
export LC_ALL=C
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
fingerprint=B07748530C39253A9E8520F56100DD2FE34B4B53
image=${PHP56_VERIFIER_IMAGE:-sha256:8ddb05da0277bba8d58b03e8d145e6a610ea1e9464e04da12577e07e614e4fc7}
env -u DOCKER_HOST -u DOCKER_CONTEXT -u DOCKER_TLS -u DOCKER_TLS_VERIFY -u DOCKER_CERT_PATH \
  docker --host=unix:///var/run/docker.sock run --rm -i --pull never \
  --platform linux/386 --network none --read-only --cap-drop ALL \
  --security-opt no-new-privileges --user 1000:1000 \
  --tmpfs /tmp:rw,nosuid,noexec,size=32m,mode=1777 \
  --mount "type=bind,src=$root/dist,dst=/distribution,readonly" \
  -e "EXPECTED_FINGERPRINT=$fingerprint" "$image" /bin/bash -s <<'VERIFY'
set -Eeuo pipefail
export LC_ALL=C
[[ $(getconf LONG_BIT) == 32 ]]
[[ $(rpm --version) == 'RPM version 4.8.'* ]]
rpm --version
mkdir -m 700 /tmp/verification-keys /tmp/verification-rpmdb
gpg --homedir /tmp/verification-keys --batch --import \
  /distribution/keys/RPM-GPG-KEY-artem-loboda-php56 >/dev/null 2>&1
actual=$(gpg --homedir /tmp/verification-keys --batch --with-colons --fingerprint 2>/dev/null | awk -F: '$1=="fpr" {print $10}')
[[ $actual == "$EXPECTED_FINGERPRINT" ]]
rpm --dbpath /tmp/verification-rpmdb --initdb
rpm --dbpath /tmp/verification-rpmdb --import /distribution/keys/RPM-GPG-KEY-artem-loboda-php56
packages=(/distribution/RPMS/i686/*.rpm /distribution/SRPMS/*.rpm)
[[ ${#packages[@]} == 34 ]]
for package in "${packages[@]}"; do
  result=$(rpm --dbpath /tmp/verification-rpmdb -Kv "$package" 2>&1)
  printf '%s\n' "$result"
  [[ $(printf '%s\n' "$result" | grep -Eic "RSA/SHA256 Signature, key ID ${EXPECTED_FINGERPRINT: -8}: OK") == 2 ]]
  if printf '%s\n' "$result" | grep -Eiq '(^|[^[:alnum:]_])(NOKEY|NOT[[:space:]]+OK|NOTTRUSTED|BAD)([^[:alnum:]_]|$)'; then exit 1; fi
done
echo 'PASS_EL6_RPM48: 34 packages, header and payload RSA/SHA256 signatures verified.'
VERIFY
