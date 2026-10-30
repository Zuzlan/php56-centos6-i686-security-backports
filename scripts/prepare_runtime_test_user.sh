#!/bin/bash
set -Eeuo pipefail
[[ ${PHP56_ISOLATED_VALIDATION:-} == 1 && -f /.dockerenv && $EUID == 0 && $(getconf LONG_BIT) == 32 ]] || exit 2
if ! id phpbuild >/dev/null 2>&1; then
 groupadd -g 1000 phpbuild
 useradd -u 1000 -g phpbuild -M -d /tmp/phpbuild -s /bin/bash phpbuild
fi
[[ $(id -u phpbuild) == 1000 ]] || exit 2
install -d -o phpbuild -g phpbuild -m 0755 /tmp/phpbuild /evidence/unprivileged
