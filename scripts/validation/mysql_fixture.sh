#!/bin/bash
# Runs only in a disposable EL6 i686 Docker fixture. Install signed mysql-server
# through setup_runtime_fixture.sh's verified repositories before invoking this.
# No package installation, TCP connection, or existing service operation occurs.
set -euo pipefail
export LC_ALL=C
unset MYSQL_PWD MYSQL_TCP_PORT MYSQL_UNIX_PORT MYSQL_HOME
usage() {
    echo "Usage: PHP56_ISOLATED_VALIDATION=1 $0 NEW_OUTPUT_DIR" >&2
    exit 2
}
[[ $# == 1 ]] || usage
[[ ${PHP56_ISOLATED_VALIDATION:-} == 1 && -f /.dockerenv ]] || {
    echo 'Refusing: explicit validation flag and disposable Docker container required.' >&2
    exit 2
}
[[ $(id -u) == 0 ]] || { echo 'Run as root inside the disposable container.' >&2; exit 2; }
[[ -f /etc/redhat-release ]] && grep -Eq 'release 6\.' /etc/redhat-release || {
    echo 'Refusing: runtime is not EL6.' >&2; exit 2;
}
[[ $(getconf LONG_BIT) == 32 ]] || { echo 'Refusing: userland is not 32-bit.' >&2; exit 2; }
for command in php mysql_install_db mysqladmin rpm timeout sha256sum; do
    command -v "$command" >/dev/null || { echo "Missing $command; prepare signed fixture dependencies first." >&2; exit 2; }
done
mysqld=/usr/libexec/mysqld
[[ -x $mysqld ]] || { echo 'Missing CentOS 6 mysql-server /usr/libexec/mysqld.' >&2; exit 2; }
rpm -q mysql-server mysql php-cli php-common >/dev/null
script_dir=$(cd "$(dirname "$0")" && pwd)
[[ -f $script_dir/mysql_fixture.php ]] || { echo 'Missing PHP fixture helper.' >&2; exit 2; }
# Require a new results directory, avoiding overwriting previous test evidence.
[[ ! -e $1 ]] || { echo 'Output directory already exists; select a new path.' >&2; exit 2; }
mkdir -p "$1"
output_dir=$(cd "$1" && pwd)
work_dir=$(mktemp -d /tmp/php56-mysql.XXXXXX)
chmod 700 "$work_dir"
mkdir "$work_dir/data" "$work_dir/tmp"
socket=$work_dir/mysql.sock
mysqld_pid=''
cleanup() {
    status=$?
    trap - EXIT
    if [[ -n $mysqld_pid ]]; then
        if kill -0 "$mysqld_pid" 2>/dev/null; then
            # Both the socket and PID belong to the child started below.
            timeout 10 mysqladmin --no-defaults --protocol=socket --socket="$socket" \
                --user=root --connect-timeout=1 shutdown > "$output_dir/mysql-shutdown.log" 2>&1 || true
            for attempt in $(seq 1 50); do
                kill -0 "$mysqld_pid" 2>/dev/null || break
                sleep 0.1
            done
            if kill -0 "$mysqld_pid" 2>/dev/null; then
                echo 'Graceful fixture shutdown timed out; terminating owned child.' >> "$output_dir/mysql-shutdown.log"
                kill -TERM "$mysqld_pid" 2>/dev/null || true
                for attempt in $(seq 1 50); do
                    kill -0 "$mysqld_pid" 2>/dev/null || break
                    sleep 0.1
                done
                if kill -0 "$mysqld_pid" 2>/dev/null; then
                    kill -KILL "$mysqld_pid" 2>/dev/null || true
                    status=1
                fi
            fi
        fi
        wait "$mysqld_pid" || status=1
    fi
    for artifact in mysqld.log mysqld-console.log mysql-install-db.log; do
        [[ ! -f $work_dir/$artifact ]] || cp "$work_dir/$artifact" "$output_dir/$artifact" || status=1
    done
    # Only the mktemp directory created by this invocation is removed.
    rm -rf -- "$work_dir"
    if [[ $status == 0 ]]; then
        echo PASS_LOCAL_MYSQL_FIXTURE > "$output_dir/STATUS"
    else
        echo "FAIL_LOCAL_MYSQL_FIXTURE exit=$status" > "$output_dir/STATUS"
    fi
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
echo RUNNING > "$output_dir/STATUS"
rpm -q --qf '%{NAME}\t%{VERSION}\t%{RELEASE}\t%{ARCH}\n' \
    mysql-server mysql php-cli php-common > "$output_dir/package-versions.tsv"
php -v > "$output_dir/php-version.txt" 2>&1
"$mysqld" --no-defaults --version > "$output_dir/mysql-version.txt" 2>&1
sha256sum /usr/bin/php "$mysqld" "$script_dir/mysql_fixture.sh" \
    "$script_dir/mysql_fixture.php" > "$output_dir/fixture-input-sha256.txt"
timeout 60 mysql_install_db --no-defaults --user=root --datadir="$work_dir/data" \
    > "$work_dir/mysql-install-db.log" 2>&1
"$mysqld" --no-defaults --user=root --datadir="$work_dir/data" \
    --socket="$socket" --pid-file="$work_dir/mysqld.pid" \
    --log-error="$work_dir/mysqld.log" --tmpdir="$work_dir/tmp" \
    --skip-networking --skip-name-resolve --innodb-buffer-pool-size=16M \
    --key-buffer-size=8M > "$work_dir/mysqld-console.log" 2>&1 &
mysqld_pid=$!
ready=0
for attempt in $(seq 1 100); do
    if mysqladmin --no-defaults --protocol=socket --socket="$socket" \
        --user=root --connect-timeout=1 ping > "$output_dir/mysql-ready.log" 2>&1; then
        ready=1
        break
    fi
    kill -0 "$mysqld_pid" 2>/dev/null || break
    sleep 0.1
done
[[ $ready == 1 && -S $socket && -f $work_dir/mysqld.pid ]]
[[ $(cat "$work_dir/mysqld.pid") == "$mysqld_pid" ]]
database=php56_fixture_$$
printf 'transport=unix_socket\nskip_networking=1\nowned_mysqld_pid=%s\ndatabase=%s\n' \
    "$mysqld_pid" "$database" > "$output_dir/fixture-isolation.txt"
timeout 60 php "$script_dir/mysql_fixture.php" "$socket" "$database" \
    > "$output_dir/mysql-api-results.txt" 2>&1
grep -qx 'RESULT=PASS' "$output_dir/mysql-api-results.txt"
echo 'Local MySQL fixture passed; this does not validate production schemas or applications.'
