#!/bin/bash
# Candidate installation fixture only. Read-only mode is --plan.
# Never use on a host or production. Installation success is not a test pass.
set -Eeuo pipefail
export LC_ALL=C
usage() {
  echo "Usage: $0 --plan|--install ARTIFACT_ROOT SIGNED_CORE_DIR RELEASE RELEASE_PUBLIC_KEY EXPECTED_RELEASE_FINGERPRINT OUTPUT_DIR" >&2
  exit 2
}
[[ $# == 7 ]] || usage
mode=$1; bundle=$2; core_dir=$3; release=$4; release_key=$5; release_fpr=$6; output_dir=$7
[[ $mode == --plan || $mode == --install ]] || usage
[[ $release_fpr =~ ^[A-Fa-f0-9]{40}$ ]] || { echo 'Expected full 40-hex release-key fingerprint.' >&2; exit 2; }
release_fpr=${release_fpr^^}
core_names=(php php-bcmath php-cli php-common php-dba php-dbg php-devel php-embedded
  php-enchant php-fpm php-gd php-gmp php-imap php-interbase php-intl php-ldap
  php-litespeed php-mbstring php-mcrypt php-mssql php-mysqlnd php-odbc php-opcache
  php-pdo php-pgsql php-process php-pspell php-recode php-snmp php-soap php-tidy
  php-xml php-xmlrpc)
dependency_names=(libzip5-1.7.3-1.el6.remi.i686.rpm
  php-pecl-jsonc-1.3.10-2.el6.remi.5.6.i686.rpm
  php-pecl-jsonc-devel-1.3.10-2.el6.remi.5.6.i686.rpm
  php-pecl-zip-1.19.2-1.el6.remi.5.6.i686.rpm)
if [[ $mode == --plan ]]; then
  cat <<EOF
PLAN ONLY: no files, keys, packages, repositories or services changed.
Target: fresh disposable EL6 i686 Docker container; root inside container only.
Core input: $core_dir (33 signed PHP 5.6.40-$release i686 RPMs and SHA256SUMS).
Dependencies: $bundle/dependency-rpms (four pinned, signed archive RPMs).
Release public key: $release_key
Expected release fingerprint: $release_fpr
Evidence output: $output_dir
Required read-only CA mount: /run/php56-host-ca.pem
Installation verifies fingerprints, hashes and every RPM signature, using only
CentOS6 Vault/EPEL6 HTTPS repositories with TLS/GPG checks enabled. No service
is started. Run runtime/security tests separately with container network disabled.
Verify the release-key fingerprint independently before trusting its signatures.
EOF
  exit 0
fi
[[ ${PHP56_ISOLATED_VALIDATION:-} == 1 && -f /.dockerenv && $(id -u) == 0 ]] || {
  echo 'Refusing: explicit isolated Docker validation flag and container root required.' >&2; exit 2;
}
[[ -f /etc/redhat-release ]] && grep -Eq 'release 6\.' /etc/redhat-release || {
  echo 'Refusing: not EL6.' >&2; exit 2;
}
[[ $(getconf LONG_BIT) == 32 ]] || { echo 'Refusing: not 32-bit userspace.' >&2; exit 2; }
[[ $(rpm --version) == 'RPM version 4.8.'* ]] || { echo 'Refusing: requires EL6 RPM 4.8.' >&2; exit 2; }
if rpm -q php-common >/dev/null 2>&1; then
  echo 'Refusing: fixture already contains PHP; upgrade testing uses a separate clone.' >&2; exit 2
fi
for path in "$bundle" "$core_dir"; do [[ -d $path ]] || exit 2; done
for path in "$release_key" "$core_dir/SHA256SUMS" /run/php56-host-ca.pem; do [[ -r $path ]] || exit 2; done
bundle=$(readlink -f "$bundle"); core_dir=$(readlink -f "$core_dir"); release_key=$(readlink -f "$release_key")
mkdir -p "$output_dir"
output_dir=$(readlink -f "$output_dir")
work=$(mktemp -d /tmp/php56-runtime-install.XXXXXXXX)
trap 'rc=$?; printf "%s\n" "$rc" > "$output_dir/install.exit-status"; date -u +%Y-%m-%dT%H:%M:%SZ > "$output_dir/install.finished-utc"; rm -rf "$work"' EXIT
date -u +%Y-%m-%dT%H:%M:%SZ > "$output_dir/install.started-utc"
epel_key=$bundle/keys/RPM-GPG-KEY-EPEL-6
remi_key=$bundle/keys/RPM-GPG-KEY-remi
printf '%s  %s\n' \
  626e18ffb3565e29ab94c02e11b593b7aded7ca910e03abc167efae38accfacf "$epel_key" \
  b0d1d4ca043e2bd60ff71899b5c0145af64f9c0ec6f2073357dfb64deada59e4 "$remi_key" \
  | sha256sum --check > "$output_dir/repository-key-hashes.txt"
mkdir "$work/repos"
cat > "$work/yum.conf" <<EOF
[main]
cachedir=/var/cache/yum/php56-fixture
keepcache=1
debuglevel=2
logfile=$output_dir/yum.log
exactarch=1
obsoletes=1
plugins=0
gpgcheck=1
localpkg_gpgcheck=1
sslverify=1
sslcacert=/run/php56-host-ca.pem
reposdir=$work/repos
EOF
for repo in base updates extras epel; do
  case $repo in
    base) url=https://vault.centos.org/6.10/os/i386/; key=/etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-6 ;;
    updates|extras) url=https://vault.centos.org/6.10/$repo/i386/; key=/etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-6 ;;
    epel) url=https://archives.fedoraproject.org/pub/archive/epel/6/i386/; key=$epel_key ;;
  esac
  [[ -r $key ]] || exit 2
  cat >> "$work/repos/fixture.repo" <<EOF
[$repo]
name=PHP56 fixture $repo
baseurl=$url
enabled=1
gpgcheck=1
sslverify=1
sslcacert=/run/php56-host-ca.pem
gpgkey=file://$key
# Every PHP package is supplied explicitly below. CentOS 5.3 packages have
# broad Obsoletes that otherwise replace php-dbg/php-pecl-zip during solving.
exclude=php*
EOF
done
cp "$work/yum.conf" "$work/repos/fixture.repo" "$output_dir/"
# Signed archive bootstrap only; local candidate packages are not yet installed.
yum -c "$work/yum.conf" -y install gnupg2 binutils curl 2>&1 | tee "$output_dir/bootstrap.log"
gpg_command=$(command -v gpg2 || command -v gpg)
mkdir -m 700 "$work/keyring"
check_key() {
  local keyfile=$1 expected=$2 found
  "$gpg_command" --batch --homedir "$work/keyring" --import "$keyfile" >> "$output_dir/key-import.txt" 2>&1
  found=$("$gpg_command" --batch --homedir "$work/keyring" --with-colons --fingerprint "$expected" | awk -F: '$1=="fpr" {print $10; exit}')
  [[ $found == "$expected" ]] || { echo "Fingerprint mismatch for $keyfile" >&2; exit 3; }
  printf '%s %s\n' "$found" "$keyfile" >> "$output_dir/key-fingerprints.txt"
}
check_key "$remi_key" 1EE04CCE88A4AE4AA29A5DF5004E6F4700F97F56
check_key "$epel_key" 8C3BE96AF2309184DA5C0DAE3B49DF2A0608B895
check_key "$release_key" "$release_fpr"
rpm --import "$remi_key" "$release_key"
# Core manifest is regenerated AFTER signing and contains only flat RPM names.
while read -r digest filename extra; do
  [[ $digest =~ ^[a-f0-9]{64}$ && -z ${extra:-} && $filename == *.rpm && $filename != */* ]] || exit 3
done < "$core_dir/SHA256SUMS"
[[ $(wc -l < "$core_dir/SHA256SUMS") == 33 ]] || exit 3
(cd "$core_dir" && sha256sum --check SHA256SUMS) > "$output_dir/core-checksums.txt"
shopt -s nullglob
core=("$core_dir"/*.rpm)
[[ ${#core[@]} == 33 ]] || { echo 'Expected exactly 33 core RPMs.' >&2; exit 3; }
printf '%s\n' "${core[@]##*/}" | sort > "$work/actual-files"
awk '{print $2}' "$core_dir/SHA256SUMS" | sort > "$work/manifest-files"
cmp "$work/actual-files" "$work/manifest-files"
: > "$work/actual-names"
for package in "${core[@]}"; do
  read -r name version actual_release arch < <(rpm -qp --qf '%{NAME} %{VERSION} %{RELEASE} %{ARCH}\n' "$package")
  [[ $version == 5.6.40 && $actual_release == "$release" && $arch == i686 ]] || exit 3
  printf '%s\n' "$name" >> "$work/actual-names"
done
printf '%s\n' "${core_names[@]}" | sort > "$work/expected-names"
sort -o "$work/actual-names" "$work/actual-names"
cmp "$work/expected-names" "$work/actual-names"
cp "$work/actual-names" "$output_dir/installed-core-names.txt"
(cd "$bundle/dependency-rpms" && sha256sum --check <<'HASHES'
cf30475b09413f4b6a5b7b3b0e257d479fdd594d917c43aa081b089e2e6ecfb2  libzip5-1.7.3-1.el6.remi.i686.rpm
d5ac3cb78c17cf56ba7aaa9f41e1879ed219d995e29c8597e220225eefcd1a93  php-pecl-jsonc-1.3.10-2.el6.remi.5.6.i686.rpm
e0c926bc714cb089a571c1487be5e48521642c584e92bd09afcf7f7084816f88  php-pecl-jsonc-devel-1.3.10-2.el6.remi.5.6.i686.rpm
1481c1db4e530dcecae8f70d6fac7cb5efb8d78309236c7aeefc4026320de06d  php-pecl-zip-1.19.2-1.el6.remi.5.6.i686.rpm
HASHES
) > "$output_dir/dependency-checksums.txt"
dependencies=()
for name in "${dependency_names[@]}"; do dependencies+=("$bundle/dependency-rpms/$name"); done
verify_rpm() {
  local package=$1 keyid=$2 algorithm=$3 result
  result=$(rpm -Kv "$package" 2>&1) || { printf '%s\n' "$result"; exit 4; }
  printf '%s\n' "$result" >> "$output_dir/rpm-signatures.txt"
  printf '%s\n' "$result" | grep -Eiq "$algorithm Signature, key ID $keyid: OK" || exit 4
  if printf '%s\n' "$result" | grep -Eiq '(^|[^[:alnum:]_])(NOKEY|NOT[[:space:]]+OK|NOTTRUSTED|BAD)([^[:alnum:]_]|$)'; then exit 4; fi
}
for package in "${core[@]}"; do verify_rpm "$package" "${release_fpr: -8}" 'RSA/SHA256'; done
for package in "${dependencies[@]}"; do verify_rpm "$package" 00f97f56 'DSA/SHA1'; done
# GPG is also enforced by Yum for every local RPM and repository dependency.
yum -c "$work/yum.conf" -y install "${core[@]}" "${dependencies[@]}" 2>&1 | tee "$output_dir/install.log"
rpm -qa --qf '%{NAME}\t%{EPOCH}\t%{VERSION}\t%{RELEASE}\t%{ARCH}\n' | sort > "$output_dir/installed-packages.tsv"
for name in "${core_names[@]}"; do
  [[ $(rpm -q --qf '%{VERSION} %{RELEASE} %{ARCH}' "$name") == "5.6.40 $release i686" ]] || exit 5
done
echo 'PASS_INSTALL_ONLY: 33 core and four explicit dependencies; runtime/security tests still required.' | tee "$output_dir/STATUS"

