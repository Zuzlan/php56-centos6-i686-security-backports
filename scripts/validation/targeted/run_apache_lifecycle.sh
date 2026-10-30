#!/bin/bash
# Installed-package validation only; starts its own single-worker Apache fixture.
set -euo pipefail
export LC_ALL=C
[[ $# == 2 ]] || { echo "Usage: PHP56_ISOLATED_VALIDATION=1 $0 NEW_RESULTS_DIR EXPECTED_PHP_RELEASE" >&2; exit 2; }
[[ ${PHP56_ISOLATED_VALIDATION:-} == 1 && -f /.dockerenv && $(id -u) == 0 ]] || exit 2
[[ -f /etc/redhat-release ]] && grep -Eq 'release 6\.' /etc/redhat-release || exit 2
[[ $(getconf LONG_BIT) == 32 && $2 =~ ^[0-9]+\.[0-9]+\.el6\.local$ && ! -e $1 ]] || exit 2
for package in php php-cli php-common; do
    [[ $(rpm -q --qf '%{VERSION} %{RELEASE} %{ARCH}' "$package") == "5.6.40 $2 i686" ]] || {
        echo "Refusing: $package does not match requested final release $2." >&2; exit 2;
    }
done
httpd -v | grep -Eq 'Apache/2\.2\.'
httpd -l | grep -q 'prefork\.c'
script_dir=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$1"
results=$(cd "$1" && pwd)
work=$(mktemp -d /tmp/php56-apache-lifecycle.XXXXXX)
chmod 755 "$work"
mkdir "$work/htdocs" "$work/state"
chmod 755 "$work/htdocs"
chown apache:apache "$work/state"
chmod 700 "$work/state"
pid=''
cleanup() {
    status=$?
    trap - EXIT
    if [[ -n $pid ]]; then
        kill -TERM "$pid" 2>/dev/null || true
        for attempt in $(seq 1 100); do
            kill -0 "$pid" 2>/dev/null || break
            sleep 0.1
        done
        if kill -0 "$pid" 2>/dev/null; then kill -KILL "$pid" 2>/dev/null || true; status=1; fi
        wait "$pid" 2>/dev/null || true
    fi
    cp -a "$work/." "$results/artifacts/" || status=1
    rm -rf -- "$work"
    chmod -R a+rX "$results"
    if [[ $status == 0 ]]; then echo PASS_APACHE_LIFECYCLE_AND_OOM > "$results/STATUS"
    else echo "FAIL_APACHE_LIFECYCLE_AND_OOM exit=$status" > "$results/STATUS"; fi
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
echo RUNNING > "$results/STATUS"
rpm -q php php-cli php-common httpd > "$results/packages.txt"
sha256sum /usr/bin/php /usr/sbin/httpd /usr/lib/httpd/modules/libphp5.so \
    "$script_dir/apache-lifecycle-handler.php" "$script_dir/apache-lifecycle-client.php" \
    "$script_dir/run_apache_lifecycle.sh" > "$results/binary-and-fixture-sha256.txt"
cp "$script_dir/apache-lifecycle-handler.php" "$work/htdocs/check.php"
chmod 644 "$work/htdocs/check.php"
cat > "$work/httpd.conf" <<EOF
ServerRoot "$work"
PidFile "$work/httpd.pid"
Listen 127.0.0.1:19057
ServerName localhost
User apache
Group apache
ServerTokens Prod
ServerSignature Off
ServerLimit 1
StartServers 1
MinSpareServers 1
MaxSpareServers 1
MaxClients 1
MaxRequestsPerChild 0
KeepAlive Off
LoadModule authz_host_module /usr/lib/httpd/modules/mod_authz_host.so
LoadModule php5_module /usr/lib/httpd/modules/libphp5.so
PHPIniDir /etc
php_admin_flag display_errors Off
php_admin_flag log_errors On
php_admin_value error_log "$work/state/php-error.log"
php_admin_value memory_limit 16M
php_admin_flag opcache.enable Off
DocumentRoot "$work/htdocs"
ErrorLog "$work/apache-error.log"
LogLevel warn
<Directory "$work/htdocs">
    Options None
    AllowOverride None
    Order allow,deny
    Allow from all
    <Files check.php>
        SetHandler application/x-httpd-php
    </Files>
</Directory>
EOF
httpd -f "$work/httpd.conf" -t > "$results/config-test.txt" 2>&1
httpd -f "$work/httpd.conf" -DFOREGROUND > "$work/apache-stdout.log" 2>&1 &
pid=$!
ready=0
for attempt in $(seq 1 50); do
    if curl --noproxy '*' --silent --fail --max-time 2 http://127.0.0.1:19057/check.php \
        > "$results/readiness-response.txt" 2> "$results/readiness-error.txt"; then ready=1; break; fi
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.1
done
[[ $ready == 1 ]]
timeout 120 php -n "$script_dir/apache-lifecycle-client.php" "$work/state" > "$results/client.log" 2>&1
grep -qx 'RESULT=PASS' "$results/client.log"
grep -q 'LOCAL_APACHE_LIFECYCLE_FIXTURE' "$work/state/php-error.log"
grep -Eiq 'Allowed memory size|Out of memory' "$work/state/php-error.log" "$work/apache-error.log" "$work/apache-stdout.log"
[[ ! -e $work/state/unexpected-oom-shutdown ]]
if grep -Eiq 'Segmentation fault|SIGSEGV|signal 11|SIGABRT|signal 6|core dumped' \
    "$work/apache-error.log" "$work/apache-stdout.log"; then exit 1; fi
cat "$results/client.log"
