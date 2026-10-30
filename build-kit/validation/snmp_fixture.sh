#!/bin/bash
# Root-only disposable Docker SNMP fixture. Never touches system configuration.
set -Eeuo pipefail
export LC_ALL=C
usage() { echo "Usage: $0 start SOURCE_ROOT NEW_STATE_DIR | stop STATE_DIR" >&2; exit 2; }
[[ $# -ge 2 ]] || usage
action=$1
[[ ${PHP56_ISOLATED_VALIDATION:-} == 1 && -f /.dockerenv && $(id -u) == 0 && $(getconf LONG_BIT) == 32 ]] || {
  echo 'Refusing: explicitly authorized root EL6 i686 Docker fixture required.' >&2; exit 2;
}
grep -Eq 'release 6\.' /etc/redhat-release || exit 2
owned_alive() {
  [[ -r /proc/$pid/stat ]] || return 1
  [[ $(awk '{print $3}' "/proc/$pid/stat") != Z ]] || return 1
  [[ $(readlink "/proc/$pid/exe") == /usr/sbin/snmpd ]] || return 2
  [[ $(awk '{print $22}' "/proc/$pid/stat") == "$starttime" ]] || return 2
  python - "$pid" "$state/snmpd.conf" <<'OWNED'
import sys
argv = open('/proc/'+sys.argv[1]+'/cmdline', 'rb').read().split('\0')
sys.exit(0 if sys.argv[2] in argv else 2)
OWNED
}
if [[ $action == stop ]]; then
  [[ $# == 2 ]] || usage
  state=$(readlink -f "$2")
  [[ -d $state && -f $state/FIXTURE && $(cat "$state/FIXTURE") == PHP56_DISPOSABLE_SNMP_FIXTURE_V1 ]] || exit 2
  [[ -r $state/launcher.pid && -r $state/starttime ]] || { echo 'No recorded daemon PID to stop.'; exit 0; }
  pid=$(cat "$state/launcher.pid"); starttime=$(cat "$state/starttime")
  [[ $pid =~ ^[1-9][0-9]*$ && $starttime =~ ^[0-9]+$ ]] || exit 2
  if owned_alive; then
    kill -TERM "$pid"
    for unused in {1..100}; do
      if owned_alive; then sleep 0.05; else code=$?; [[ $code == 1 ]] || exit 3; break; fi
    done
    if owned_alive; then
      kill -KILL "$pid"
      printf '%s\n' FORCED_KILL_OWNED_FIXTURE > "$state/stop-status"
      exit 3
    else
      code=$?; [[ $code == 1 ]] || exit 3
    fi
  else
    code=$?; [[ $code == 1 ]] || { echo 'Refusing to signal a PID whose ownership changed.' >&2; exit 3; }
  fi
  printf '%s\n' STOPPED_OWNED_FIXTURE > "$state/stop-status"
  exit 0
fi
[[ $action == start && $# == 3 ]] || usage
source_root=$(readlink -f "$2")
[[ $3 == /* && ! -e $3 && $3 != *$'\n'* ]] || exit 2
for file in README snmpd.conf snmp_include.inc bigtest.sh; do
  [[ -r $source_root/ext/snmp/tests/$file ]] || exit 2
done
[[ -x /usr/sbin/snmpd ]] || { echo 'Install the authenticated net-snmp test dependency first.' >&2; exit 2; }
if pgrep -x snmpd >/dev/null; then echo 'Refusing: an SNMP daemon already exists.' >&2; exit 2; fi
# Fail before starting anything if either exact upstream loopback endpoint is busy.
python - <<'PORTS'
import socket
sockets=[]
for family,address in [(socket.AF_INET,('127.0.0.1',161)),(socket.AF_INET6,('::1',161))]:
    sock=socket.socket(family,socket.SOCK_DGRAM)
    if family == socket.AF_INET6: sock.setsockopt(socket.IPPROTO_IPV6,socket.IPV6_V6ONLY,1)
    sock.bind(address)
    sockets.append(sock)
for sock in sockets: sock.close()
PORTS
mkdir -m 700 "$3"
state=$(readlink -f "$3")
printf '%s\n' PHP56_DISPOSABLE_SNMP_FIXTURE_V1 > "$state/FIXTURE"
mkdir -m 700 "$state/persistent" "$state/conf"
cp "$source_root/ext/snmp/tests/snmpd.conf" "$state/snmpd.conf.upstream"
cp "$source_root/ext/snmp/tests/bigtest.sh" "$state/bigtest.sh"
sha256sum "$source_root/ext/snmp/tests/README" "$source_root/ext/snmp/tests/snmpd.conf" \
  "$source_root/ext/snmp/tests/snmp_include.inc" "$source_root/ext/snmp/tests/bigtest.sh" > "$state/upstream-input-sha256.txt"
python - "$state" <<'CONFIG'
import sys
state=sys.argv[1]
source=open(state+'/snmpd.conf.upstream').read()
assert source.count('agentaddress udp:127.0.0.1:161,udp6:[::1]:161') == 1
assert source.count('exec HexTest /bin/sh /etc/snmp/bigtest.sh') == 1
source=source.replace('\nDo not enable them', '\n# Do not enable them')
source=source.replace('exec HexTest /bin/sh /etc/snmp/bigtest.sh','exec HexTest /bin/sh '+state+'/bigtest.sh')
open(state+'/snmpd.conf','w').write(source)
CONFIG
trap 'rc=$?; if [[ $rc != 0 && -r $state/starttime ]]; then "$0" stop "$state" || true; fi; exit "$rc"' EXIT
SNMPCONFPATH="$state/conf" SNMP_PERSISTENT_DIR="$state/persistent" \
  SNMP_PERSISTENT_FILE="$state/persistent/snmpd.conf" \
  /usr/sbin/snmpd -f -Le -C -c "$state/snmpd.conf" -p "$state/snmpd.pid" > "$state/snmpd.log" 2>&1 &
pid=$!
printf '%s\n' "$pid" > "$state/launcher.pid"
starttime=$(awk '{print $22}' "/proc/$pid/stat")
printf '%s\n' "$starttime" > "$state/starttime"
python - "$pid" > "$state/readiness.txt" <<'READY'
import os,socket,sys,time
def tlv(tag,data):
    size=len(data)
    length=chr(size) if size<128 else '\x81'+chr(size)
    return chr(tag)+length+data
oid='\x2b\x06\x01\x02\x01\x01\x01\x00'
binding=tlv(0x30,tlv(0x06,oid)+tlv(0x05,''))
pdu=tlv(0xa0,tlv(0x02,'\x01')+tlv(0x02,'\x00')+tlv(0x02,'\x00')+tlv(0x30,binding))
request=tlv(0x30,tlv(0x02,'\x01')+tlv(0x04,'public')+pdu)
for unused in range(40):
    if not os.path.exists('/proc/'+sys.argv[1]): raise SystemExit('Fixture daemon exited')
    sock=socket.socket(socket.AF_INET,socket.SOCK_DGRAM);sock.settimeout(0.25)
    try:
        sock.sendto(request,('127.0.0.1',161));data,peer=sock.recvfrom(65535)
        if peer==('127.0.0.1',161) and '\xa2' in data and 'public' in data and oid in data:
            print('PASS localhost SNMPv2c GET sysDescr.0; fixture response bytes='+str(len(data)))
            break
    except socket.timeout: pass
    finally: sock.close()
else: raise SystemExit('Fixture SNMP readiness timed out')
READY
owned_alive
[[ $(cat "$state/snmpd.pid") == "$pid" ]]
printf '%s\n' READY_OWNED_LOOPBACK_SNMP_FIXTURE > "$state/STATUS"
trap - EXIT
printf 'SNMP fixture ready: PID %s, state %s; stop with this helper after tests.\n' "$pid" "$state"
