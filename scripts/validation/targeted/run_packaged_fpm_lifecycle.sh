#!/bin/bash
# Installed final RPMs only; rootless local FPM pool with no published ports.
set -euo pipefail
[[ $# == 3 ]] || { echo "Usage: $0 FCGI_INCLUDE NEW_RESULTS_DIR EXPECTED_RELEASE" >&2; exit 2; }
[[ ${PHP56_ISOLATED_VALIDATION:-} == 1 && -f /.dockerenv && $(id -u) != 0 ]] || exit 2
[[ $(getconf LONG_BIT) == 32 ]] || exit 2
for package in php-cli php-fpm; do
    [[ $(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}' "$package") == "5.6.40-$3.i686" ]] || {
        echo "Unexpected installed $package release" >&2; exit 2;
    }
done
fcgi=$1
mkdir "$2"
results=$(cd "$2" && pwd)
script_dir=$(cd "$(dirname "$0")" && pwd)
marker="$results/UNSAFE_SHUTDOWN_HANDLER_RAN"
pidfile="$results/oom-worker.pid"
cat > "$results/fpm.conf" <<EOF
[global]
error_log = $results/fpm-error.log
daemonize = no
[fixture]
listen = 127.0.0.1:19056
pm = static
pm.max_children = 1
catch_workers_output = yes
env[PHP56_OOM_MARKER] = $marker
env[PHP56_OOM_PIDFILE] = $pidfile
php_admin_value[memory_limit] = 8M
php_admin_value[display_errors] = Off
php_admin_value[log_errors] = On
php_admin_value[error_log] = $results/php-error.log
EOF
rpm -q php-cli php-fpm php-common php-opcache > "$results/installed-packages.txt"
/usr/sbin/php-fpm -F -y "$results/fpm.conf" > "$results/fpm-stdout.log" 2>&1 &
pid=$!
cleanup() { status=$?; trap - EXIT; kill -TERM "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; exit "$status"; }
trap cleanup EXIT
sleep 0.3
timeout 60 /usr/bin/php "$script_dir/fpm-lifecycle-client.php" "$fcgi" "$script_dir/packaged-fpm-handler.php" > "$results/lifecycle-client.log" 2>&1
grep -q '^PASS 200 requests' "$results/lifecycle-client.log"
timeout 30 /usr/bin/php "$script_dir/packaged-fpm-oom-client.php" "$fcgi" "$script_dir/packaged-fpm-handler.php" "$marker" "$pidfile" > "$results/oom-client.log" 2>&1
grep -q '^PASS hard-OOM worker' "$results/oom-client.log"
[[ ! -e "$marker" ]]
grep -q 'LOCAL_LIFECYCLE_FIXTURE' "$results/php-error.log"
grep -Eq 'Allowed memory size .* exhausted' "$results/fpm-error.log" "$results/fpm-stdout.log"
grep -Eq 'child [0-9]+ exited with code 1' "$results/fpm-error.log"
if grep -Eiq 'SIGSEGV|signal 11|SIGABRT|signal 6|core dumped|PHP Startup|Unable to load|undefined symbol' "$results"/*.log; then exit 1; fi
sha256sum /usr/bin/php /usr/sbin/php-fpm > "$results/binary-sha256.txt"
cat "$results/lifecycle-client.log" "$results/oom-client.log"
