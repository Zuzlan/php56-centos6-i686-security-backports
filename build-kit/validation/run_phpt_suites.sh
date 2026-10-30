#!/bin/bash
# Full make-test discovery for all three CLI builds; no failures are swallowed.
# Writes PHPT scratch files in the supplied isolated build tree, as run-tests.php
# normally does. Preserves each variant's fresh artifacts before the next run.
set -euo pipefail
[[ $# == 2 ]] || { echo "Usage: PHP56_ISOLATED_VALIDATION=1 $0 PHP_SOURCE_ROOT NEW_OUTPUT_DIR" >&2; exit 2; }
[[ ${PHP56_ISOLATED_VALIDATION:-} == 1 && -f /.dockerenv ]] || {
    echo 'Refusing: full suites require the explicit flag and a disposable Docker container.' >&2; exit 2;
}
[[ -f /etc/redhat-release ]] && grep -Eq 'release 6\.' /etc/redhat-release || exit 2
[[ $(getconf LONG_BIT) == 32 ]] || exit 2
source_root=$(cd "$1" && pwd)
[[ -f "$source_root/run-tests.php" ]] || { echo 'Missing PHP run-tests.php.' >&2; exit 2; }
[[ ! -e "$2" ]] || { echo 'Use a fresh output directory for each test invocation.' >&2; exit 2; }
mkdir -p "$2"
output_dir=$(cd "$2" && pwd)
case "$source_root$output_dir" in
    *[[:space:]]*) echo 'PHP Makefile TESTS paths must not contain whitespace.' >&2; exit 2 ;;
esac
online_skip=${SKIP_ONLINE_TESTS:-1}
slow_skip=${SKIP_SLOW_TESTS:-1}
case "$online_skip:$slow_skip" in 0:0|0:1|1:0|1:1) ;; *) echo 'Skip flags must be 0 or 1.' >&2; exit 2 ;; esac
export NO_INTERACTION=1 REPORT_EXIT_STATUS=1 MALLOC_CHECK_=2
export TEST_PHP_LOG_FORMAT=LEODS TEST_PHP_DETAILED=1
# Local SNMP fixture requests include intentional invalid communities/users.
# Bound each fixture request wait without removing any test or assertion.
export SNMP_TIMEOUT=${SNMP_TIMEOUT:-100000}
[[ $SNMP_TIMEOUT =~ ^[1-9][0-9]*$ ]] || { echo 'SNMP_TIMEOUT must be positive microseconds.' >&2; exit 2; }
if [[ $online_skip == 1 ]]; then export SKIP_ONLINE_TESTS=1; else unset SKIP_ONLINE_TESTS; fi
if [[ $slow_skip == 1 ]]; then export SKIP_SLOW_TESTS=1; else unset SKIP_SLOW_TESTS; fi
# Matches the spec's locale isolation. The parent should disable container egress.
unset TZ LANG LC_ALL
printf 'SKIP_ONLINE_TESTS=%s\nSKIP_SLOW_TESTS=%s\nSNMP_TIMEOUT_MICROSECONDS=%s\n' "$online_skip" "$slow_skip" "$SNMP_TIMEOUT" > "$output_dir/test-policy.txt"
printf 'SNMP_RETRIES=%s\n' "${SNMP_RETRIES:-upstream-default}" >> "$output_dir/test-policy.txt"
printf 'variant\tmake_exit\ttee_exit\tstatus\n' > "$output_dir/status.tsv"
echo RUNNING > "$output_dir/STATUS"
# rpm %patch -b .bug79082 creates two empty backups inside the directory that
# bug79082 intentionally archives in full. They are generated patch metadata,
# not fixture input; archive only these exact, verified-empty regular files.
# Preserve the raw prior-suite evidence; never delete or rewrite assertions.
if [[ ${PHP56_PHPT_PREFLIGHT_ONLY:-0} != 1 ]]; then
    backup_dir="$output_dir/phpt-generated-backups"
    mkdir "$backup_dir"
    printf 'source_path\tsha256\taction\n' > "$backup_dir/manifest.tsv"
    for relative_path in \
        ext/phar/tests/test79082/test79082-testfile.bug79082 \
        ext/phar/tests/test79082/test79082-testfile2.bug79082; do
        backup_path="$source_root/$relative_path"
        if [[ ! -e "$backup_path" && ! -L "$backup_path" ]]; then
            printf '%s\t-\tNOT_PRESENT\n' "$relative_path" >> "$backup_dir/manifest.tsv"
            continue
        fi
        if [[ ! -f "$backup_path" || -L "$backup_path" || -s "$backup_path" ]]; then
            echo "Unexpected content/type in generated backup: $relative_path" >&2
            exit 2
        fi
        backup_sha=$(sha256sum "$backup_path")
        backup_sha=${backup_sha%% *}
        [[ $backup_sha == e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 ]] || exit 2
        mv -- "$backup_path" "$backup_dir/${relative_path##*/}"
        printf '%s\t%s\tMOVED_GENERATED_EMPTY_BACKUP\n' "$relative_path" "$backup_sha" >> "$backup_dir/manifest.tsv"
    done
fi
overall=0
for variant in build-cgi build-ztscli build-fpm; do
    build_dir="$source_root/$variant"
    log_dir="$output_dir/$variant"
    mkdir "$log_dir"
    if [[ ! -f "$build_dir/Makefile" || ! -x "$build_dir/sapi/cli/php" ]]; then
        printf '%s\t127\t0\tMISSING_BUILD\n' "$variant" >> "$output_dir/status.tsv"
        overall=1
        continue
    fi
    cp "$build_dir/Makefile" "$log_dir/Makefile.used"
    # %install removes libtool .la files; their original compile order also puts
    # mysqlnd after its consumers and xml after wddx. Enumerate every configured
    # .so directly, with providers first, independently of libtool metadata.
    module_names=$(sed -n 's/^PHP_MODULES = //p' "$build_dir/Makefile" | tr ' ' '\n' | sed -n 's|.*/\([a-zA-Z0-9_]*\)\.la$|\1|p')
    zend_names=$(sed -n 's/^PHP_ZEND_EX = //p' "$build_dir/Makefile" | tr ' ' '\n' | sed -n 's|.*/\([a-zA-Z0-9_]*\)\.la$|\1|p')
    module_args=
    : > "$log_dir/shared-module-files.txt"
    for module in mysqlnd pdo xml $module_names; do
        if ! printf '%s\n' "$module_names" | grep -Fxq "$module"; then continue; fi
        if grep -Fxq "$module.so" "$log_dir/shared-module-files.txt"; then continue; fi
        [[ -f "$build_dir/modules/$module.so" ]] || { echo "Missing configured module: $module.so" >&2; exit 2; }
        printf '%s.so\n' "$module" >> "$log_dir/shared-module-files.txt"
        module_args="$module_args -d extension=$module.so"
    done
    for module in $zend_names; do
        [[ -f "$build_dir/modules/$module.so" ]] || { echo "Missing configured Zend module: $module.so" >&2; exit 2; }
        printf '%s.so\n' "$module" >> "$log_dir/shared-module-files.txt"
        module_args="$module_args -d zend_extension=$build_dir/modules/$module.so"
    done
    printf '%s\n' "$module_args" > "$log_dir/shared-module-arguments.txt"
    "$build_dir/sapi/cli/php" -n -v > "$log_dir/php-version.txt" 2>&1
    cat > "$log_dir/validation.mk" <<'MAKEFILE'
.PHONY: validation-modules
validation-modules:
	$(PHP_EXECUTABLE) -n -d extension_dir=$(top_builddir)/modules/ $(PHP_TEST_SHARED_EXTENSIONS) -m
MAKEFILE
    module_status=0
    make -s -C "$build_dir" -f "$build_dir/Makefile" -f "$log_dir/validation.mk" \
        "PHP_TEST_SHARED_EXTENSIONS=$module_args" validation-modules > "$log_dir/shared-modules.txt" 2>&1 || module_status=$?
    if grep -Ei 'PHP (Warning|Startup|Fatal|Parse)|Unable to load|already loaded|undefined symbol|Segmentation fault' \
        "$log_dir/shared-modules.txt" > "$log_dir/module-errors.txt"; then
        module_status=1
    fi
    if [[ $variant != build-fpm ]]; then
        for extension in gd intl mcrypt PDO mysql mysqlnd xml ldap gmp 'Zend OPcache'; do
            if ! grep -Fxq "$extension" "$log_dir/shared-modules.txt"; then
                echo "Missing shared extension: $extension" >> "$log_dir/module-errors.txt"
                module_status=1
            fi
        done
    fi
    if [[ $module_status -ne 0 ]]; then
        cat "$log_dir/module-errors.txt" >&2
        printf '%s\t0\t0\tMODULE_PREFLIGHT_FAILED\n' "$variant" >> "$output_dir/status.tsv"
        echo FAIL_MODULE_PREFLIGHT > "$output_dir/STATUS"
        exit 1
    fi
    if [[ ${PHP56_PHPT_PREFLIGHT_ONLY:-0} == 1 ]]; then
        printf '%s\t0\t0\tPASS_MODULE_PREFLIGHT\n' "$variant" >> "$output_dir/status.tsv"
        continue
    fi
    export TEST_PHP_JUNIT="$log_dir/junit.xml"
    unset TEST_PHP_CGI_EXECUTABLE TEST_PHPDBG_EXECUTABLE
    if [[ -x "$build_dir/sapi/cgi/php-cgi" ]]; then export TEST_PHP_CGI_EXECUTABLE="$build_dir/sapi/cgi/php-cgi"; fi
    if [[ -x "$build_dir/sapi/phpdbg/phpdbg" ]]; then export TEST_PHPDBG_EXECUTABLE="$build_dir/sapi/phpdbg/phpdbg"; fi
    touch "$log_dir/started.marker"
    echo "Running full PHPT discovery in $variant; log: $log_dir/suite.log"
    set +e
    make -C "$build_dir" -o all test "PHP_TEST_SHARED_EXTENSIONS=$module_args" "TESTS=-w $log_dir/nonpassing-tests.txt" 2>&1 | tee "$log_dir/suite.log"
    pipeline_status=("${PIPESTATUS[@]}")
    set -e
    make_status=${pipeline_status[0]}
    tee_status=${pipeline_status[1]}
    # Normalize progress carriage returns to make every status independently visible.
    tr '\r' '\n' < "$log_dir/suite.log" > "$log_dir/suite-normalized.log"
    grep -E '^(PASS|FAIL|BORK|WARN|LEAK|SKIP|XFAIL)(&| )' "$log_dir/suite-normalized.log" > "$log_dir/test-results.txt" || true
    grep -E '^(Number of tests|Tests (skipped|borked|warned|failed|leaked|passed)|Expected fail|Time taken)' \
        "$log_dir/suite-normalized.log" > "$log_dir/summary.txt" || true
    : > "$log_dir/artifacts.nul"
    while IFS= read -r -d '' artifact; do
        # Restrict to generated PHPT companions, not source Make/configuration logs.
        if [[ -f "${artifact%.*}.phpt" ]]; then
            printf '%s\0' "${artifact#"$source_root/"}" >> "$log_dir/artifacts.nul"
        fi
    done < <(find "$source_root" -type f -newer "$log_dir/started.marker" \
        \( -name '*.diff' -o -name '*.out' -o -name '*.exp' -o -name '*.log' -o -name '*.sh' -o -name '*.php' \) -print0)
    tar -C "$source_root" --null -T "$log_dir/artifacts.nul" -czf "$log_dir/phpt-artifacts.tar.gz"
    status=PASS_WITH_SKIPS_REQUIRING_REVIEW
    if [[ $make_status -ne 0 || $tee_status -ne 0 || $module_status -ne 0 ]] || \
       grep -Eq '^([^ ]*&)?(FAIL|BORK|WARN|LEAK)(&| )' "$log_dir/test-results.txt" || \
       grep -Eq '^Tests (borked|warned|failed|leaked)[[:space:]]*:[[:space:]]*[1-9]' "$log_dir/summary.txt" || \
       ! grep -Eq '^Number of tests[[:space:]]*:[[:space:]]*[1-9][0-9]*' "$log_dir/summary.txt" || \
       ! grep -Eq '^Tests passed[[:space:]]*:[[:space:]]*[1-9][0-9]*' "$log_dir/summary.txt"; then
        status=FAIL
        overall=1
    fi
    printf '%s\t%s\t%s\t%s\n' "$variant" "$make_status" "$tee_status" "$status" >> "$output_dir/status.tsv"
done
if [[ ${PHP56_PHPT_PREFLIGHT_ONLY:-0} == 1 ]]; then
    echo PASS_MODULE_PREFLIGHT > "$output_dir/STATUS"
elif [[ $overall == 0 ]]; then
    echo PASS_PHPT_WITH_SKIPS_REQUIRING_REVIEW > "$output_dir/STATUS"
else
    echo FAIL_PHPT > "$output_dir/STATUS"
fi
cat "$output_dir/status.tsv"
exit "$overall"
