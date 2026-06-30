#!/usr/bin/env bash
# Offline test for vdf_set_launchopts (no Whisky/Steam required).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/../install.command"
source "$SRC"   # guard prevents main from running
set +e          # the .command enables `set -e`; the harness must not inherit it

WANT='"\"C:\\Program Files (x86)\\Steam\\steamapps\\common\\MECCHA CHAMELEON\\Chameleon\\Binaries\\Win64\\PenguinHotel-Win64-Shipping.exe\" %command%"'
VAL='"C:\Program Files (x86)\Steam\steamapps\common\MECCHA CHAMELEON\Chameleon\Binaries\Win64\PenguinHotel-Win64-Shipping.exe" %command%'

fail=0
run_case() {
  local name="$1" fixture="$2"
  local tmp; tmp="$(mktemp)"; cp "$HERE/fixtures/$fixture" "$tmp"
  vdf_set_launchopts "$tmp" "4704690" "$VAL"; local rc=$?
  local line; line="$(grep -m1 "LaunchOptions" "$tmp" || true)"
  if [[ $rc -eq 0 ]] && [[ "$line" == *"$WANT" ]]; then
    echo "PASS: $name"
  else
    echo "FAIL: $name (rc=$rc)"; echo "  got:  $line"; echo "  want suffix: $WANT"; fail=1
  fi
  local n; n="$(grep -c 'LaunchOptions' "$tmp")"
  [[ "$n" -eq 1 ]] || { echo "FAIL: $name has $n LaunchOptions lines (want 1)"; fail=1; }
  rm -f "$tmp" "$tmp".*.bak 2>/dev/null || true
}

run_case "overwrite existing block" with-block.vdf
run_case "inject missing block"     no-block.vdf
run_case "real-like (dup id, nested subblock, no LaunchOptions yet)" real-like.vdf

# Structural guard for the real-like case: LaunchOptions must land inside the
# 4704690 apps block (before the sibling 228980 block) and the Licenses hex line
# must be untouched.
tmp="$(mktemp)"; cp "$HERE/fixtures/real-like.vdf" "$tmp"
vdf_set_launchopts "$tmp" "4704690" "$VAL" >/dev/null
lo_line="$(grep -n 'LaunchOptions' "$tmp" | head -1 | cut -d: -f1)"
app228="$(grep -n '"228980"' "$tmp" | tail -1 | cut -d: -f1)"
if [[ -n "$lo_line" && -n "$app228" && "$lo_line" -lt "$app228" ]]; then
  echo "PASS: LaunchOptions placed inside the 4704690 apps block"
else
  echo "FAIL: LaunchOptions misplaced (lo_line=$lo_line, 228980_apps=$app228)"; fail=1
fi
if grep -q '"4704690"		"3200000004000000ff95cd0cdeadbeef"' "$tmp"; then
  echo "PASS: Licenses hex line untouched"
else
  echo "FAIL: Licenses hex line was modified"; fail=1
fi
rm -f "$tmp" "$tmp".*.bak 2>/dev/null || true

[[ $fail -eq 0 ]] && echo "ALL PASS" || echo "SOME FAILED"
exit $fail
