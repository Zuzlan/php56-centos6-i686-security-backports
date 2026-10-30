#!/usr/bin/env bash
set -Eeuo pipefail
umask 022
# Written by the host wrapper; never overwrite logs from an earlier attempt.
BUILD_LOG_DIR=${BUILD_LOG_DIR:-/build/logs/run-$(date -u +%Y%m%dT%H%M%SZ)-$$}
mkdir -p "$BUILD_LOG_DIR" "$BUILD_LOG_DIR/RPMS" "$BUILD_LOG_DIR/SRPMS"
php56_snmp_state=''
finish_build() {
  rc=$?
  trap - EXIT
  if [[ -n $php56_snmp_state ]]; then
    if ! PHP56_ISOLATED_VALIDATION=1 bash /build/validation/snmp_fixture.sh stop "$php56_snmp_state" > "$BUILD_LOG_DIR/snmp-stop.log" 2>&1; then
      [[ $rc != 0 ]] || rc=1
    fi
  fi
  printf '%s\n' "$rc" > "$BUILD_LOG_DIR/container.exit-status"
  date -u +%Y-%m-%dT%H:%M:%SZ > "$BUILD_LOG_DIR/container.finished-utc"
  exit "$rc"
}
trap finish_build EXIT
date -u +%Y-%m-%dT%H:%M:%SZ > "$BUILD_LOG_DIR/container.started-utc"
[[ $(uname -m) == i686 || $(uname -m) == i386 ]] || {
  echo "NOTE: kernel reports $(uname -m); checking actual userspace width next." >&2
  # uname might report amd64 on some docker/kernel combinations; check actual ELF below
}
[[ $(getconf LONG_BIT) == 32 ]] || { echo 'ERROR: not a 32-bit userspace' >&2; exit 2; }
# Explicit offline mode is for an immutable image whose signed build dependencies
# were already installed. rpmbuild still enforces every BuildRequires.
case ${PHP56_USE_INSTALLED_BUILD_DEPS:-0} in 0|1) ;; *) exit 2 ;; esac
rpm -qa --qf '%{NAME}\t%{VERSION}\t%{RELEASE}\t%{ARCH}\n' | sort > "$BUILD_LOG_DIR/initial-installed-rpms.tsv"
if [[ ${PHP56_USE_INSTALLED_BUILD_DEPS:-0} == 0 ]]; then
# EOL archive repos are used ONLY inside this disposable container.
mkdir -p /etc/yum.repos.d/old
for f in /etc/yum.repos.d/*.repo; do [[ -f $f ]] && mv "$f" /etc/yum.repos.d/old/; done
cat >/etc/yum.repos.d/centos6-vault.repo <<'REPO'
[base]
name=CentOS 6.10 base
baseurl=https://vault.centos.org/6.10/os/i386/
enabled=1
gpgcheck=1
sslverify=1
sslcacert=/run/php56-host-ca.pem
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-6
[updates]
name=CentOS 6.10 updates
baseurl=https://vault.centos.org/6.10/updates/i386/
enabled=1
gpgcheck=1
sslverify=1
sslcacert=/run/php56-host-ca.pem
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-6
[extras]
name=CentOS 6.10 extras
baseurl=https://vault.centos.org/6.10/extras/i386/
enabled=1
gpgcheck=1
sslverify=1
sslcacert=/run/php56-host-ca.pem
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-6
[epel]
name=Fedora EPEL 6 archive
baseurl=https://archives.fedoraproject.org/pub/archive/epel/6/i386/
enabled=1
gpgcheck=1
sslverify=1
sslcacert=/run/php56-host-ca.pem
gpgkey=file:///build/keys/RPM-GPG-KEY-EPEL-6
REPO
# On EL6, old NSS/CA libraries may not negotiate TLS with modern HTTPS servers.
# Fail rather than disable certificate or RPM signature verification.
yum clean all
yum -y install util-linux-ng yum-utils rpm-build redhat-rpm-config gcc gcc-c++ make autoconf automake libtool patch bison re2c net-snmp || {
  echo 'ERROR: EL6 vault or EPEL archive unavailable; do not disable TLS/GPG checks as a shortcut.' >&2
  exit 3
}
else
  echo 'OFFLINE BUILD: using installed dependencies; rpmbuild dependency checks remain enabled.'
  rpm -q util-linux-ng yum-utils rpm-build redhat-rpm-config gcc gcc-c++ make autoconf automake libtool patch bison re2c net-snmp
fi
# Regression tests need an unprivileged identity (FPM fixtures omit a root pool user).
# UID 1000 also gives archived source ownership a known name inside this container.
if ! id phpbuild >/dev/null 2>&1; then
  groupadd -g 1000 phpbuild
  useradd -u 1000 -g phpbuild -M -d /tmp/phpbuild -s /bin/bash phpbuild
fi
[[ $(id -u phpbuild) == 1000 ]] || { echo 'Unexpected phpbuild UID' >&2; exit 2; }
install -d -o phpbuild -g phpbuild -m 0755 /tmp/phpbuild
# EL6 PAM's default nproc=1024 can include host tasks sharing UID 1000.
# Bound only this disposable test account; do not alter host limits.
printf '%s\n' 'phpbuild soft nproc 16384' > /etc/security/limits.d/99-php56-validation.conf
/sbin/runuser -s /bin/bash phpbuild -c 'id; ulimit -u'
# Build from a recorded spec copy. Embed the debuginfo setting in the SRPM,
# so rebuilding it directly retains the workaround. Original spec is untouched.
mkdir -p "$BUILD_LOG_DIR/SPECS"
SPEC=$BUILD_LOG_DIR/SPECS/php.spec
cp /build/SPECS/php.spec "$BUILD_LOG_DIR/php.spec.before"
{
  printf '%s\n' '# EL6 RPM 4.8: optional debuginfo omitted; security flags unchanged.' '%global debug_package %{nil}'
  awk '
    /^%(global|define)[ \t]+debug_package[ \t]/ {
      if ($0 !~ /^%(global|define)[ \t]+debug_package[ \t]+%\{nil\}[ \t]*$/) exit 2
      next
    }
    { print }
  ' /build/SPECS/php.spec
} > "$SPEC"
sha256sum "$SPEC" > "$BUILD_LOG_DIR/spec.sha256"
sha256sum /build/keys/RPM-GPG-KEY-EPEL-6 > "$BUILD_LOG_DIR/repository-key.sha256"
(cd /build && find SOURCES -type f -print0 | sort -z | xargs -0 sha256sum) > "$BUILD_LOG_DIR/sources.sha256"
# Install the BuildRequires specified by the non-SCL .spec.
if [[ ${PHP56_USE_INSTALLED_BUILD_DEPS:-0} == 0 ]]; then
yum-builddep -y "$SPEC" || {
  echo 'ERROR: missing build dependencies in EOL repositories. See yum output above.' >&2
  exit 4
}
fi
rpm -qa --qf '%{NAME}\t%{VERSION}\t%{RELEASE}\t%{ARCH}\n' | sort > "$BUILD_LOG_DIR/installed-build-dependencies.tsv"
# RPM 4.8 debugedit cannot grow /build/BUILD paths into /usr/src/debug.
# Omit only the optional debuginfo subpackage; source/security flags stay intact.
# --target i686 controls RPM metadata; setarch alone previously yielded i386 RPMs.
# First check patch compatibility. Only if it passes do we attempt the full RPM build.
set -o pipefail
setarch i686 rpmbuild -bp --target i686 --define '_topdir /build' --define "_rpmdir $BUILD_LOG_DIR/RPMS" --define "_srcrpmdir $BUILD_LOG_DIR/SRPMS" --define 'dist .el6' --define 'debug_package %{nil}' "$SPEC" \
  2>&1 | tee "$BUILD_LOG_DIR/prep.log"
setarch i686 rpmbuild -ba --target i686 --define '_topdir /build' --define "_rpmdir $BUILD_LOG_DIR/RPMS" --define "_srcrpmdir $BUILD_LOG_DIR/SRPMS" --define 'dist .el6' --define 'debug_package %{nil}' "$SPEC" \
  2>&1 | tee "$BUILD_LOG_DIR/build.log"
printf '\nBuilt RPMs:\n'
find "$BUILD_LOG_DIR/RPMS" "$BUILD_LOG_DIR/SRPMS" -type f -name '*.rpm' -print
test_failure=0
if grep -Eq 'TEST FAILURE:|Tests failed[[:space:]]*:[[:space:]]*[1-9]|^(BORK|FAIL|WARN|LEAK)[[:space:]]' "$BUILD_LOG_DIR/build.log"; then
  echo 'WARNING: the RPM spec logs PHP test failures. Do NOT install these RPMs.' >&2
  test_failure=1
fi
grep -Eq 'Tests passed[[:space:]]*:[[:space:]]*[1-9]' "$BUILD_LOG_DIR/build.log" || {
  echo 'ERROR: missing successful PHPT summary; test execution is unproven.' >&2; test_failure=1;
}
shopt -s nullglob
built=("$BUILD_LOG_DIR"/RPMS/i686/*.rpm)
[[ ${#built[@]} -gt 0 ]] || { echo 'ERROR: no i686 RPMs produced' >&2; exit 7; }
for artifact in "${built[@]}"; do
  [[ $(rpm -qp --qf '%{ARCH}' "$artifact") == i686 ]] || exit 7
done
rpm -qp --qf '%{NAME}\n' "${built[@]}" | sort > "$BUILD_LOG_DIR/binary-package-names.txt"
for package in php php-cli php-dbg php-fpm php-litespeed php-common php-devel php-opcache php-imap php-ldap php-pdo php-mysqlnd php-pgsql php-process php-odbc php-soap php-interbase php-snmp php-xml php-xmlrpc php-mbstring php-gd php-bcmath php-gmp php-dba php-mcrypt php-tidy php-mssql php-embedded php-pspell php-recode php-intl php-enchant; do
  grep -Fxq "$package" "$BUILD_LOG_DIR/binary-package-names.txt" || {
    echo "ERROR: missing expected package: $package" >&2; exit 7;
  }
done
source_rpms=("$BUILD_LOG_DIR"/SRPMS/php-*.src.rpm)
[[ ${#source_rpms[@]} == 1 ]] || { echo 'ERROR: expected exactly one source RPM.' >&2; exit 7; }
release=$(rpm -qp --qf '%{RELEASE}' "${built[0]}")
python /build/validation/check_rpm_metadata.py "$BUILD_LOG_DIR/RPMS" "$release" "$BUILD_LOG_DIR/rpm-metadata.json"
chown -R phpbuild:phpbuild /build/BUILD/php-5.6.40
php56_snmp_state=$BUILD_LOG_DIR/snmp-fixture
PHP56_ISOLATED_VALIDATION=1 bash /build/validation/snmp_fixture.sh start /build/BUILD/php-5.6.40 "$php56_snmp_state" > "$BUILD_LOG_DIR/snmp-start.log" 2>&1
export SNMP_TIMEOUT=100000 SNMP_RETRIES=1
if ! PHP56_ISOLATED_VALIDATION=1 PHP56_PHPT_OUTPUT="$BUILD_LOG_DIR/full-phpt"   /sbin/runuser -s /bin/bash phpbuild -c 'exec bash /build/validation/run_phpt_suites.sh /build/BUILD/php-5.6.40 "$PHP56_PHPT_OUTPUT"'; then
  test_failure=1
fi
[[ $test_failure == 0 ]] || { echo 'ERROR: tests failed; preserve artifacts for diagnosis only.' >&2; exit 6; }
# Compilation does not establish security efficacy or upgrade compatibility.
echo 'CANDIDATE ONLY: isolated runtime/security/upgrade validation remains required.' 
