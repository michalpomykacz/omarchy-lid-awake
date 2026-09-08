#!/bin/bash
# Cycles the toggle and asserts the reported state, the persisted state, and
# the number of held inhibitor locks agree every time. Catches the failure this
# was actually written for: a surface whose glyph says "off" while its lock is
# still held.
set -u

STATE="$HOME/.local/state/omarchy/indicators/lid-awake"
fail=0

locks() { systemd-inhibit --list | grep -c 'Lid awake'; }

check() {
  local want="$1" status file n
  status=$(omarchy-shell lid status)
  file=$(cat "$STATE" 2>/dev/null)
  n=$(locks)

  [[ $status == "$want" ]] || { echo "FAIL status=$status want=$want"; fail=1; }
  [[ $file == "$want" ]] || { echo "FAIL file=$file want=$want"; fail=1; }
  if [[ $want == awake ]]; then
    ((n > 0)) || { echo "FAIL awake but no inhibitor lock"; fail=1; }
  else
    ((n == 0)) || { echo "FAIL suspend but $n inhibitor lock(s) held"; fail=1; }
  fi
}

original=$(omarchy-shell lid status)

# The live lid policy must not be left changed by a test that dies halfway.
restore() {
  omarchy-shell lid "$([[ $original == awake ]] && echo on || echo off)" >/dev/null 2>&1
}
trap restore EXIT INT TERM

for i in {1..8}; do
  if ((i % 2)); then want=awake; omarchy-shell lid on >/dev/null
  else want=suspend; omarchy-shell lid off >/dev/null; fi
  sleep 1
  check "$want"
done

# Toggle must be absolute across surfaces, not a per-surface flip.
omarchy-shell lid off >/dev/null; sleep 1
[[ $(omarchy-shell lid toggle) == awake ]] || { echo "FAIL toggle did not report awake"; fail=1; }
sleep 1
check awake

# A write must land even when the value matches what the writing surface last
# saw. FileView.setText used to drop exactly this write, so clicking on one
# monitor and then another left the file disagreeing with every visible icon,
# and the next shell start believed the file. Forcing the file out from under
# the shell stands in for the second monitor's stale cache, which IPC cannot
# reach on its own.
omarchy-shell lid off >/dev/null; sleep 1
printf 'awake\n' > "$STATE"
omarchy-shell lid off >/dev/null; sleep 1.5
[[ $(cat "$STATE") == suspend ]] || {
  echo "FAIL no-op write skipped: reported $(omarchy-shell lid status), file $(cat "$STATE")"
  fail=1
}

((fail)) && { echo "FAILED"; exit 1; }
echo "OK"
