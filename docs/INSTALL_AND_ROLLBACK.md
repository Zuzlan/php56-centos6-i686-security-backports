# Installation and rollback

Artem Loboda reported this release working on the production server on 2026-10-30. Other installations need their own package selection, backups and application checks. The local package rehearsal covered 47.2 → 47.3 → 47.2, not a verified rollback to the historical `5.6.40-9.el6.remi` installation.

## Prepare an isolated clone first

Keep a restorable system snapshot, application/database backups, configuration backups and the exact old signed RPMs. Record third-party PHP extensions and long-running workers. Match the clone to the target server's installed packages and configuration.

Read [SIGNATURES.md](SIGNATURES.md). The delivered PHP RPMs and source RPM use Artem Loboda's release signing key. Verify its full fingerprint through an independent trusted channel before importing it. The external dependencies require the original Remi key. Do not disable signature or dependency checking.

Verify the full release before selecting packages:

```bash
sha256sum --check SHA256SUMS
(cd dist && sha256sum --check SHA256SUMS)
```

Run the following in one administrator Bash session on the isolated clone. It selects only core packages already installed. Put the exact old RPMs into the newly created `rollback/` directory before continuing to the next block. The staging directory contains private configuration/inventory data and must not be published.

```bash
set -euo pipefail
release_dir=$(pwd -P)
change_dir=$(mktemp -d /root/php56-change.XXXXXXXX)
mkdir "$change_dir/rollback" "$change_dir/evidence"
rpm -qa --qf '%{NAME}\t%{EPOCH}\t%{VERSION}\t%{RELEASE}\t%{ARCH}\n' \
  | sort > "$change_dir/evidence/installed-before.tsv"
php -v > "$change_dir/evidence/php-before.txt"
php -m > "$change_dir/evidence/extensions-before.txt"
if rpm -q php-mysql >/dev/null 2>&1; then
  echo 'STOP: this release uses mysqlnd; rehearse a libmysql backend transition separately.' >&2
  exit 1
fi
shopt -s nullglob
upgrade=()
for package in "$release_dir"/dist/RPMS/i686/*.rpm; do
  name=$(rpm -qp --qf '%{NAME}' "$package")
  if rpm -q "$name" >/dev/null 2>&1; then upgrade+=("$package"); fi
done
[[ ${#upgrade[@]} -gt 0 ]]
printf '%s\n' "${upgrade[@]}" > "$change_dir/evidence/upgrade-files.txt"
printf 'Stage exact old RPMs under: %s/rollback\n' "$change_dir"
```

Validate every rollback identity and signature before changing packages. The RPM database must already contain the independently trusted signing keys. An unknown or absent signature stops this procedure.

```bash
rollback=()
for package in "${upgrade[@]}"; do
  name=$(rpm -qp --qf '%{NAME}' "$package")
  old_file=$(rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}.rpm' "$name")
  old_package="$change_dir/rollback/$old_file"
  [[ -f $old_package ]]
  query='%{NAME} %{EPOCH} %{VERSION} %{RELEASE} %{ARCH}'
  [[ $(rpm -qp --qf "$query" "$old_package") == $(rpm -q --qf "$query" "$name") ]]
  rollback+=("$old_package")
done
for package in "${upgrade[@]}" "${rollback[@]}"; do
  result=$(rpm -Kv "$package" 2>&1)
  printf '%s\n' "$result" >> "$change_dir/evidence/signatures.txt"
  printf '%s\n' "$result" | grep -Eiq 'Signature, key ID [[:xdigit:]]+: OK'
  if printf '%s\n' "$result" | grep -Eiq \
    '(^|[^[:alnum:]_])(NOKEY|NOT[[:space:]]+OK|NOTTRUSTED|BAD)([^[:alnum:]_]|$)'; then
    exit 1
  fi
done
rpm -Uvh --test "${upgrade[@]}" > "$change_dir/evidence/upgrade-test.txt" 2>&1
config=()
for path in /etc/php.ini /etc/php.d /etc/php-zts.d /etc/php-fpm.conf \
  /etc/php-fpm.d /etc/httpd/conf.d/php.conf; do
  if [[ -e $path ]]; then config+=("${path#/}"); fi
done
[[ ${#config[@]} -gt 0 ]]
tar -C / -cpf "$change_dir/php-configuration.tar" "${config[@]}"
```

If dependency checks fail, stop and stage the required signed packages. The four external dependency RPMs are supplied for review, do not install all of them blindly. Any newly added package, removed conflict or backend transition changes the rollback plan and must be rehearsed separately. Never use `--nodeps`, `--force` or an automatic `yum history undo` as a substitute.

## Apply and verify on the clone

Record which PHP-serving services and bot/job workers are running. Stop those affected processes during the rehearsed maintenance window. Do not stop unrelated services. Apply the frozen package selection:

```bash
rpm -Uvh "${upgrade[@]}" > "$change_dir/evidence/upgrade-install.txt" 2>&1
php -v
php -m
if command -v httpd >/dev/null; then httpd -t; fi
if command -v php-fpm >/dev/null; then php-fpm -t; fi
```

Review `.rpmnew`/`.rpmsave` files and configuration differences. Start only previously running services and workers. Check application pages, authentication, sessions, uploads, MySQL transactions, scheduled jobs and bots. Recreated workers clear old PHP code and OPcache state. Test the disabled upload-progress behavior and abrupt OOM exit described in [RELEASE_NOTES.md](RELEASE_NOTES.md).

## Rehearse rollback

Stop the affected workers again and use the frozen exact old package list:

```bash
rpm -Uvh --oldpackage --test "${rollback[@]}" \
  > "$change_dir/evidence/rollback-test.txt" 2>&1
rpm -Uvh --oldpackage "${rollback[@]}" \
  > "$change_dir/evidence/rollback-install.txt" 2>&1
```

Review and restore configuration from the protected backup where necessary, do not overwrite the RPM database. Start only the previously running services, and repeat configuration/application checks. A package downgrade does not itself justify restoring databases, data recovery must follow the independently rehearsed application backup plan.

After both directions succeed on the clone, the operator can repeat the same reviewed package lists and service/configuration steps on the matching target during its maintenance window. Keep rollback payloads locally available instead of relying on an EOL repository.

