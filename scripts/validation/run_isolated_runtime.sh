#!/bin/bash
# Run only inside a disposable, prepared EL6 i686 container, with RPMs installed.
# No package installation, production connections, or existing service restarts.
set -euo pipefail
export LC_ALL=C
usage() {
    echo "Usage: PHP56_ISOLATED_VALIDATION=1 $0 OUTPUT_DIR mysqlnd|mysql [BASELINE_EXTENSIONS_TXT]" >&2
    exit 2
}
[[ $# -ge 2 && $# -le 3 ]] || usage
[[ ${PHP56_ISOLATED_VALIDATION:-} == 1 && -f /.dockerenv ]] || {
    echo 'Refusing: requires explicit validation flag and a disposable Docker container.' >&2
    exit 2
}
[[ $(id -u) == 0 ]] || { echo 'Container root is needed to launch isolated Apache workers.' >&2; exit 2; }
case "$2" in mysqlnd|mysql) mysql_driver=$2 ;; *) usage ;; esac
[[ -f /etc/redhat-release ]] && grep -Eq 'release 6\.' /etc/redhat-release || {
    echo 'Refusing: runtime is not EL6.' >&2; exit 2;
}
[[ $(getconf LONG_BIT) == 32 ]] || { echo 'Refusing: runtime userland is not 32-bit.' >&2; exit 2; }
for command in php php-fpm httpd curl rpm readelf ldd timeout; do
    command -v "$command" >/dev/null || { echo "Missing $command" >&2; exit 2; }
done
script_dir=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$1"
output_dir=$(cd "$1" && pwd)
work_dir=$(mktemp -d /tmp/php56-runtime.XXXXXX)
chmod 755 "$work_dir"
httpd_pid=''
cleanup() {
    status=$?
    trap - EXIT
    if [[ -n "$httpd_pid" ]]; then
        kill -TERM "$httpd_pid" 2>/dev/null || true
        wait "$httpd_pid" 2>/dev/null || true
    fi
    cp -a "$work_dir/." "$output_dir/apache-artifacts/" || status=1
    rm -rf "$work_dir"
    if [[ $status -eq 0 ]]; then
        echo PASS_RUNTIME_SMOKE_ONLY > "$output_dir/STATUS"
    else
        echo "FAIL_RUNTIME_SMOKE exit=$status" > "$output_dir/STATUS"
    fi
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
echo RUNNING > "$output_dir/STATUS"
rpm -qa --qf '%{NAME}\t%{EPOCH}\t%{VERSION}\t%{RELEASE}\t%{ARCH}\n' | sort > "$output_dir/installed-rpms.tsv"
rpm -q --qf '%{ARCH}\n' php php-cli php-common php-fpm php-opcache > "$output_dir/php-arches.txt"
if grep -qv '^i686$' "$output_dir/php-arches.txt"; then
    echo 'Installed PHP packages do not all have i686 architecture.' >&2; exit 1
fi
for binary in /usr/bin/php /usr/bin/php-cgi /usr/sbin/php-fpm /usr/lib/httpd/modules/libphp5.so; do
    readelf -h "$binary" > "$output_dir/elf-$(basename "$binary").txt"
    grep -Eq 'Class:[[:space:]]+ELF32' "$output_dir/elf-$(basename "$binary").txt"
    grep -Eq 'Machine:[[:space:]]+Intel 80386' "$output_dir/elf-$(basename "$binary").txt"
    ldd "$binary" > "$output_dir/ldd-$(basename "$binary").txt"
    if grep -q 'not found' "$output_dir/ldd-$(basename "$binary").txt"; then exit 1; fi
done
php --ini > "$output_dir/php-ini.txt" 2>&1
php -v > "$output_dir/php-version.txt" 2>&1
php -m > "$output_dir/php-modules.txt" 2>&1
# phpinfo also renders date data; use an explicit fixture timezone.
php -d date.timezone=UTC -i > "$output_dir/php-info.txt" 2>&1
php "$script_dir/runtime_smoke.php" > "$output_dir/cli-smoke.txt" 2>&1
grep -qx 'RESULT=PASS' "$output_dir/cli-smoke.txt"
grep -qx 'PASS SAPI=cli' "$output_dir/cli-smoke.txt"
php -d opcache.enable_cli=1 -r '$s=opcache_get_status(false); if (!$s || empty($s["opcache_enabled"])) { fwrite(STDERR,"OPcache inactive\n"); exit(1); } echo "PASS OPcache enabled in CLI\n";' > "$output_dir/opcache.txt" 2>&1
php -r '$m=get_loaded_extensions(); sort($m); echo implode("\n", $m), "\n";' > "$output_dir/extensions.txt" 2>&1
php -r 'echo "mysql=",mysql_get_client_info(),"\nmysqli=",mysqli_get_client_info(),"\nmysqlnd=",(extension_loaded("mysqlnd") ? "yes" : "no"),"\n";' > "$output_dir/mysql-driver.txt" 2>&1
if [[ $mysql_driver == mysqlnd ]]; then
    rpm -q php-mysqlnd > "$output_dir/mysql-package.txt"
    grep -qx 'mysqlnd=yes' "$output_dir/mysql-driver.txt"
    if rpm -q php-mysql >/dev/null 2>&1; then echo 'Both MySQL backend packages installed.' >&2; exit 1; fi
else
    rpm -q php-mysql > "$output_dir/mysql-package.txt"
    grep -qx 'mysqlnd=no' "$output_dir/mysql-driver.txt"
    if rpm -q php-mysqlnd >/dev/null 2>&1; then echo 'Both MySQL backend packages installed.' >&2; exit 1; fi
fi
if [[ $# == 3 ]]; then
    # The optional file is one extension name per line from an offline baseline.
    php -r '$want=file($argv[1], FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES); if ($want===false) exit(2); $have=array_map("strtolower",get_loaded_extensions()); $missing=array_diff(array_map("strtolower",$want),$have); foreach($missing as $m) echo "MISSING ",$m,"\n"; exit(count($missing) ? 1 : 0);' "$3" > "$output_dir/baseline-extension-check.txt" 2>&1
else
    echo 'NOT RUN: exact offline production extension inventory unavailable.' > "$output_dir/baseline-extension-check.txt"
fi
timeout 30 php-fpm -t -y /etc/php-fpm.conf > "$output_dir/fpm-config-test.txt" 2>&1
timeout 30 php-fpm -d date.timezone=UTC -i > "$output_dir/fpm-info.txt" 2>&1
httpd -v > "$output_dir/apache-version.txt" 2>&1
grep -Eq 'Apache/2\.2\.' "$output_dir/apache-version.txt"
httpd -l > "$output_dir/apache-builtins.txt" 2>&1
grep -Eq 'prefork\.c' "$output_dir/apache-builtins.txt"
mkdir "$work_dir/htdocs"
chmod 755 "$work_dir/htdocs"
cp "$script_dir/runtime_smoke.php" "$work_dir/htdocs/check.php"
chmod 644 "$work_dir/htdocs/check.php"
cat > "$work_dir/httpd.conf" <<EOF
ServerRoot "$work_dir"
PidFile "$work_dir/httpd.pid"
Listen 127.0.0.1:18080
ServerName 127.0.0.1
User apache
Group apache
ServerTokens Prod
ServerSignature Off
LoadModule authz_host_module /usr/lib/httpd/modules/mod_authz_host.so
LoadModule php5_module /usr/lib/httpd/modules/libphp5.so
PHPIniDir /etc
DocumentRoot "$work_dir/htdocs"
ErrorLog "$work_dir/error.log"
LogLevel warn
<Directory "$work_dir/htdocs">
    Options None
    AllowOverride None
    Order allow,deny
    Allow from all
    <Files check.php>
        SetHandler application/x-httpd-php
    </Files>
</Directory>
EOF
httpd -f "$work_dir/httpd.conf" -t > "$output_dir/apache-config-test.txt" 2>&1
httpd -f "$work_dir/httpd.conf" -M > "$output_dir/apache-modules.txt" 2>&1
grep -q 'php5_module' "$output_dir/apache-modules.txt"
httpd -f "$work_dir/httpd.conf" -DFOREGROUND > "$work_dir/stdout.log" 2>&1 &
httpd_pid=$!
request_ok=0
for attempt in $(seq 1 20); do
    if curl --noproxy '*' --fail --silent --show-error --max-time 5 \
        http://127.0.0.1:18080/check.php > "$output_dir/apache-smoke.txt" 2> "$work_dir/curl-error.txt"; then
        request_ok=1; break
    fi
    kill -0 "$httpd_pid" 2>/dev/null || break
    sleep 0.2
done
[[ $request_ok == 1 ]]
grep -qx 'RESULT=PASS' "$output_dir/apache-smoke.txt"
grep -qx 'PASS SAPI=apache2handler' "$output_dir/apache-smoke.txt"
if grep -Ei 'PHP (Warning|Startup|Fatal|Parse)|Unable to load|already loaded|undefined symbol|Segmentation fault' \
    "$output_dir"/*.txt "$work_dir"/*.log > "$output_dir/startup-errors.txt"; then
    echo 'PHP startup/runtime diagnostic detected; inspect startup-errors.txt.' >&2; exit 1
fi
echo 'Runtime smoke checks passed; security, upgrade, rollback and application validation remain separate.'
