#!/bin/bash
# Dependencies only, inside the fresh disposable Docker runtime fixture.
set -Eeuo pipefail
export LC_ALL=C
[[ $# == 4 ]] || { echo "Usage: $0 ARTIFACT_ROOT NEW_OUTPUT_DIR OWNER_UID OWNER_GID" >&2; exit 2; }
bundle=$1; output_dir=$2; owner_uid=$3; owner_gid=$4
[[ ${PHP56_ISOLATED_VALIDATION:-} == 1 && -f /.dockerenv && $(id -u) == 0 ]] || exit 2
[[ -f /etc/redhat-release ]] && grep -Eq 'release 6\.' /etc/redhat-release || exit 2
[[ $(getconf LONG_BIT) == 32 && $owner_uid =~ ^[0-9]+$ && $owner_gid =~ ^[0-9]+$ ]] || exit 2
[[ -r /run/php56-host-ca.pem && ! -e $output_dir ]] || exit 2
if rpm -q php-common >/dev/null 2>&1; then echo 'Refusing: expected fixture without PHP.' >&2; exit 2; fi
mkdir -p "$output_dir"
output_dir=$(readlink -f "$output_dir")
work=$(mktemp -d /tmp/php56-runtime-deps.XXXXXXXX)
cleanup() {
    rc=$?
    trap - EXIT
    printf '%s\n' "$rc" > "$output_dir/install.exit-status"
    date -u +%Y-%m-%dT%H:%M:%SZ > "$output_dir/install.finished-utc"
    rm -rf "$work"
    chown -R "$owner_uid:$owner_gid" "$output_dir"
    exit "$rc"
}
trap cleanup EXIT
date -u +%Y-%m-%dT%H:%M:%SZ > "$output_dir/install.started-utc"
epel_key=$bundle/keys/RPM-GPG-KEY-EPEL-6
printf '%s  %s\n' 626e18ffb3565e29ab94c02e11b593b7aded7ca910e03abc167efae38accfacf "$epel_key" \
    | sha256sum --check > "$output_dir/repository-key-hashes.txt"
sha256sum /etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-6 /run/php56-host-ca.pem \
    >> "$output_dir/repository-key-hashes.txt"
rpm -qa --qf '%{NAME}\t%{EPOCH}\t%{VERSION}\t%{RELEASE}\t%{ARCH}\n' \
    | sort > "$output_dir/packages-before.tsv"
pgrep -x udevd > "$output_dir/udevd-before.pids" || [[ $? == 1 ]]
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
    cat >> "$work/repos/fixture.repo" <<EOF
[$repo]
name=PHP56 dependency fixture $repo
baseurl=$url
enabled=1
gpgcheck=1
sslverify=1
sslcacert=/run/php56-host-ca.pem
gpgkey=file://$key
exclude=php*
EOF
done
cp "$work/yum.conf" "$work/repos/fixture.repo" "$output_dir/"
yum -c "$work/yum.conf" -y install mysql-server mysql binutils curl util-linux-ng 2>&1 | tee "$output_dir/install.log"
# Some EL6 dependency RPM scriptlets launch udevd even without an init system.
# Stop only a newly created fixture process; preserve any pre-existing PID.
pgrep -x udevd > "$output_dir/udevd-after.pids" || [[ $? == 1 ]]
while read -r daemon_pid; do
    if ! grep -qx "$daemon_pid" "$output_dir/udevd-before.pids"; then
        [[ $(readlink "/proc/$daemon_pid/exe") == /sbin/udevd ]] || exit 1
        printf 'Stopping newly spawned dependency scriptlet udevd pid=%s\n' "$daemon_pid" \
            >> "$output_dir/scriptlet-daemon-cleanup.log"
        kill -TERM "$daemon_pid"
    fi
done < "$output_dir/udevd-after.pids"
rpm -qa --qf '%{NAME}\t%{EPOCH}\t%{VERSION}\t%{RELEASE}\t%{ARCH}\n' \
    | sort > "$output_dir/packages-after.tsv"
rpm -q mysql-server mysql binutils curl util-linux-ng > "$output_dir/requested-packages.txt"
rpm -q --qf '%{NAME}\t%{ARCH}\n' mysql-server mysql binutils curl util-linux-ng > "$output_dir/requested-arches.tsv"
if rpm -q php-common >/dev/null 2>&1; then echo 'Unexpected PHP package installed.' >&2; exit 1; fi
if pgrep -x mysqld >/dev/null; then echo 'Unexpected mysqld process after package installation.' >&2; exit 1; fi
find /var/cache/yum/php56-fixture -type f -name '*.rpm' -print0 \
    | xargs -0 -r rpm -Kv > "$output_dir/cached-rpm-signatures.txt" 2>&1
if grep -Eiq '(^|[^[:alnum:]_])(NOKEY|NOT[[:space:]]+OK|NOTTRUSTED|BAD)([^[:alnum:]_]|$)' "$output_dir/cached-rpm-signatures.txt"; then exit 1; fi
echo PASS_DEPENDENCIES_ONLY_NO_PHP_NO_APPLICATION_SERVICES > "$output_dir/STATUS"
