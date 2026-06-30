#!/usr/bin/env bash
#
# reset-whisky.sh
# Completely remove Whisky (frankea fork) and ALL its data from this Mac,
# returning the machine to a clean, never-installed state. Used to test the
# friend-facing installer from scratch.
#
# WIPES (irreversible):
#   - /Applications/Whisky.app and the frankea Homebrew cask + tap
#   - ~/Library/Containers/com.franke.Whisky   (bottles, Steam, installed games, saves, login)
#   - ~/Library/Application Support/com.franke.Whisky  (Wine runtime + DXMT libraries)
#   - ~/Library/Preferences/com.franke.Whisky.plist
#   - ~/Library/Caches/com.franke.Whisky (if present)
#
# Run:  bash reset-whisky.sh
#
set -uo pipefail

say()  { printf "\n\033[1;36m==> %s\033[0m\n" "$1"; }
warn() { printf "\033[1;33m[!] %s\033[0m\n" "$1"; }

say "Force-quitting Steam / Wine / Whisky (they pin the sandbox container)"
# Wine-hosted Windows processes (steam.exe, services.exe, etc.) don't have
# "wine" in their name; they all carry the WINE_ENABLE_POSIX_SIGNALS env marker
# and are managed by wineserver. If any are alive, macOS blocks deleting the
# container with "Operation not permitted". Kill the lot.
killall -9 Whisky WhiskyCmd 2>/dev/null || true
# Shut bottles down the canonical way first (env-var matching is unreliable).
WS="$HOME/Library/Application Support/com.franke.Whisky/Libraries/Wine/bin/wineserver"
if [ -x "$WS" ]; then
  for b in "$HOME/Library/Containers/com.franke.Whisky/Bottles"/*/; do
    [ -d "$b" ] && WINEPREFIX="$b" "$WS" -k 2>/dev/null || true
  done
fi
pkill -9 -f "steam.exe" 2>/dev/null || true
pkill -9 -f "wineserver" 2>/dev/null || true
pkill -9 -f "preloader" 2>/dev/null || true
pkill -9 -f "com.franke.Whisky" 2>/dev/null || true
sleep 2

say "Uninstalling the Homebrew cask (frankea fork)"
if brew list --cask 2>/dev/null | grep -qi '^whisky$'; then
  brew uninstall --cask --force whisky 2>/dev/null || warn "cask uninstall reported an issue; continuing"
else
  warn "whisky cask not registered with Homebrew"
fi

say "Removing the frankea tap"
brew untap frankea/whisky 2>/dev/null || warn "tap not present or already removed"

say "Clearing the cached Whisky DMG so a reinstall downloads fresh (like a friend's Mac)"
rm -rf "/opt/homebrew/Caskroom/whisky"
find "$HOME/Library/Caches/Homebrew" -iname "*whisky*" -delete 2>/dev/null || true

say "Deleting the app bundle (if the cask left it behind)"
rm -rf "/Applications/Whisky.app"

say "Deleting all Whisky user data (bottles, runtime, libs, prefs)"
rm -rf "$HOME/Library/Application Support/com.franke.Whisky"
rm -rf "$HOME/Library/Caches/com.franke.Whisky"
rm -f  "$HOME/Library/Preferences/com.franke.Whisky.plist"
rm -rf "$HOME/Library/Saved Application State/com.franke.Whisky.savedState"

# The sandbox container is the tricky one. Two distinct reasons it resists rm:
#   1) a bottle process (Steam/Wine) is still alive and pins it -> kill, retry.
#   2) once an app has RUN in the container, macOS seals its
#      .com.apple.containermanagerd.metadata.plist; Terminal can't delete that
#      without Full Disk Access (EPERM) even with nothing running. Finder HAS the
#      entitlement, so we ask Finder to move the container to the Trash.
CONTAINER="$HOME/Library/Containers/com.franke.Whisky"
rm -rf "$CONTAINER" 2>/dev/null || true

# Case 1: a process is holding it.
if [ -e "$CONTAINER" ]; then
  warn "Container still present; killing any bottle processes and retrying."
  pkill -9 -f "WINE_ENABLE_POSIX_SIGNALS" 2>/dev/null || true
  pkill -9 -f "wineserver" 2>/dev/null || true
  killall -9 Whisky 2>/dev/null || true
  sleep 2
  rm -rf "$CONTAINER" 2>/dev/null || true
fi

# Case 2: macOS-sealed metadata. Finder has the entitlement Terminal lacks, but
# Terminal first needs Automation permission to control Finder. The system shows
# a one-time popup ("<your terminal> wants to control Finder") - click OK. Don't
# swallow the error, so if it's blocked the reason is visible.
if [ -e "$CONTAINER" ]; then
  warn "Container is protected by macOS; asking Finder to move it to the Trash."
  warn "(If a popup asks to let your terminal control Finder, click OK.)"
  ferr="$(osascript -e "tell application \"Finder\" to delete (POSIX file \"$CONTAINER\" as alias)" 2>&1)" || true
  sleep 1
  if [ -e "$CONTAINER" ] && [ -n "${ferr:-}" ]; then warn "Finder reported: $ferr"; fi
fi

# Last resort: manual path, plus the reassurance that it does not matter.
if [ -e "$CONTAINER" ]; then
  warn "Couldn't auto-remove the container. Two ways to finish:"
  warn "  EASIEST - drag it to the Trash yourself: open Finder, press Shift+Cmd+G,"
  warn "            paste this path, press Return, then drag the folder to the Trash:"
  warn "              $CONTAINER"
  warn "  OR grant permission once: System Settings > Privacy & Security > Automation"
  warn "     > (your terminal app) > switch ON Finder, then re-run this script."
  warn "  NOTE: this leftover is just an empty folder. Reinstalling works fine even"
  warn "  if you leave it - the installer reuses it. Removing it is only for a"
  warn "  perfectly pristine test."
fi

say "Verifying clean state"
clean=1
for p in \
  "/Applications/Whisky.app" \
  "$HOME/Library/Containers/com.franke.Whisky" \
  "$HOME/Library/Application Support/com.franke.Whisky" \
  "$HOME/Library/Preferences/com.franke.Whisky.plist"; do
  if [ -e "$p" ]; then warn "STILL PRESENT: $p"; clean=0; else echo "  gone: $p"; fi
done
if brew list --cask 2>/dev/null | grep -qi '^whisky$'; then warn "STILL PRESENT: brew cask whisky"; clean=0; fi

if [ "$clean" = 1 ]; then
  printf "\n\033[1;32m[ok] Mac is clean. No Whisky artifacts remain.\033[0m\n"
else
  printf "\n\033[1;31m[x] Some artifacts remain (see above). Re-run or remove manually.\033[0m\n"
  exit 1
fi
