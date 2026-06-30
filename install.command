#!/usr/bin/env bash
#
# Install MECCHA CHAMELEON.command
# One-click installer for MECCHA CHAMELEON on Apple Silicon Macs.
# Double-click to run. First time: right-click and choose Open (Gatekeeper).
#
# Installs the frankea Whisky fork (direct DMG, no Homebrew), creates a Windows
# bottle, installs Steam, enables DXMT, waits for the user to log in + install
# the game, sets the launch option that bypasses the broken UE bootstrapper, and
# drops a Play launcher on the Desktop.
#
set -euo pipefail

readonly LOG="$HOME/meccha-install.log"
readonly APPID="4704690"
readonly BOTTLE="Steam"
readonly WHISKY_DMG="https://github.com/frankea/Whisky/releases/download/app-v3.5.0/Whisky-3.5.0.dmg"
readonly WHISKY_SHA="8f8278e2f27e6bea023458469678b6b1027273a8968153adec5915f056149f40"
readonly WHISKY_APP="/Applications/Whisky.app"
readonly WHISKYCMD="$WHISKY_APP/Contents/Resources/WhiskyCmd"
readonly CONTAINER="$HOME/Library/Containers/com.franke.Whisky"
readonly LAUNCH_OPTS='"C:\Program Files (x86)\Steam\steamapps\common\MECCHA CHAMELEON\Chameleon\Binaries\Win64\PenguinHotel-Win64-Shipping.exe" %command%'

# ---- output helpers -------------------------------------------------------
say()  { printf "\n\033[1;36m==> %s\033[0m\n" "$1"; }
warn() { printf "\033[1;33m[!] %s\033[0m\n" "$1"; }
die()  { printf "\n\033[1;31m[x] %s\033[0m\n" "$1"; exit 1; }
ok()   { printf "\033[1;32m[ok] %s\033[0m\n" "$1"; }

pause_for() {
  # $1 = instruction text. Waits for the user to press Return.
  printf "\n\033[1;35m>>> %s\033[0m\n" "$1"
  printf "\033[1;35m    Press Return here when done...\033[0m "
  read -r _
}

on_err() {
  printf "\n\033[1;31m[x] Something stopped the installer.\033[0m\n"
  printf "Send Alec this file so he can see what happened:\n  %s\n" "$LOG"
}

# ---- preflight ------------------------------------------------------------
preflight() {
  say "Checking this Mac"

  [[ "$(uname -m)" == "arm64" ]] || die "This needs an Apple Silicon Mac (M1 or newer). This one is Intel, which can't run the game."

  local major
  major="$(sw_vers -productVersion | cut -d. -f1)"
  [[ "$major" -ge 15 ]] || die "This needs macOS 15 (Sequoia) or newer. Update macOS in System Settings, then try again."

  local free_gb
  free_gb="$(df -g "$HOME" | awk 'NR==2 {print $4}')"
  [[ "$free_gb" -ge 8 ]] || die "Not enough free space: ${free_gb} GB free, need at least 8 GB. Free up space and try again."

  if ! id -Gn "$USER" | tr ' ' '\n' | grep -qx admin; then
    die "Your account isn't an administrator. This installer needs to copy an app into /Applications. Log in as an admin user (or have one run this), then try again."
  fi

  ok "Mac looks good: $(sysctl -n machdep.cpu.brand_string), macOS $(sw_vers -productVersion), ${free_gb} GB free, admin user."
}

# ---- rosetta + whisky -----------------------------------------------------
ensure_rosetta() {
  say "Ensuring Rosetta 2 (lets Intel apps like Steam run)"
  if /usr/bin/pgrep -q oahd; then
    ok "Rosetta already installed."
    return
  fi
  warn "Installing Rosetta. macOS may ask for your password."
  softwareupdate --install-rosetta --agree-to-license
  ok "Rosetta installed."
}

install_whisky() {
  say "Installing Whisky 3.5.0"
  if [[ -x "$WHISKYCMD" ]]; then
    ok "Whisky already installed at $WHISKY_APP."
    return
  fi

  local dmg mount
  dmg="$(mktemp -t whisky).dmg"
  say "Downloading Whisky (~9 MB)"
  curl -fL "$WHISKY_DMG" -o "$dmg" || die "Couldn't download Whisky. Check the internet connection and try again."

  say "Verifying the download"
  local got
  got="$(shasum -a 256 "$dmg" | awk '{print $1}')"
  [[ "$got" == "$WHISKY_SHA" ]] || { rm -f "$dmg"; die "Whisky download was corrupted (checksum mismatch). Try again."; }

  say "Installing the app"
  mount="$(mktemp -d)"
  hdiutil attach "$dmg" -nobrowse -quiet -mountpoint "$mount" || die "Couldn't open the Whisky disk image."
  cp -R "$mount/Whisky.app" /Applications/ || { hdiutil detach "$mount" -quiet || true; die "Couldn't copy Whisky into /Applications."; }
  hdiutil detach "$mount" -quiet || true
  rm -f "$dmg"; rmdir "$mount" 2>/dev/null || true

  # Strip quarantine so it opens without a Gatekeeper prompt (it is notarized).
  xattr -dr com.apple.quarantine "$WHISKY_APP" 2>/dev/null || true

  [[ -x "$WHISKYCMD" ]] || die "Whisky installed but WhiskyCmd is missing. Tell Alec."
  ok "Whisky installed."
}

# ---- bottle ---------------------------------------------------------------
bottle_prefix() {
  # Echo the prefix path of the bottle named $BOTTLE. Matches by Metadata.plist
  # name, so it works even before the Wine prefix (drive_c) is bootstrapped.
  local b
  for b in "$CONTAINER"/Bottles/*/; do
    [[ -f "${b}Metadata.plist" ]] || continue
    if /usr/libexec/PlistBuddy -c 'Print :info:name' "${b}Metadata.plist" 2>/dev/null | grep -qx "$BOTTLE"; then
      echo "${b%/}"; return 0
    fi
  done
  # Fallback: if exactly one bottle exists, use it.
  local count
  count="$(ls -d "$CONTAINER"/Bottles/*/ 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "$count" == "1" ]]; then
    echo "$(ls -d "$CONTAINER"/Bottles/*/ | head -1 | sed 's:/*$::')"; return 0
  fi
  return 1
}

# The shared Wine runtime (~300 MB) downloads on Whisky's first GUI launch. The
# CLI can't trigger that download, so if it's missing we ask the user to open
# Whisky once and click through the dialog. This is the ONLY manual Whisky step.
ensure_wine_runtime() {
  local wine="$HOME/Library/Application Support/com.franke.Whisky/Libraries/Wine/bin/wine"
  [[ -e "$wine" ]] && return 0

  say "One quick manual step: Whisky needs to download its Windows support files (~300 MB), one time"
  open "$WHISKY_APP" || true   # bring Whisky to the front
  pause_for "Whisky just opened. If it shows a dialog to download/install support files (Wine / GPTK), click Next / Install / Download and let it finish. When it's done downloading, come back here and press Return."

  local tries=0
  until [[ -e "$wine" ]] || [[ $tries -ge 6 ]]; do
    warn "I don't see the support files finished downloading yet."
    pause_for "Wait until the Whisky download is completely finished, then come back here."
    tries=$((tries+1))
  done
  [[ -e "$wine" ]] || die "The Windows support files didn't download. Open Whisky once, let it finish, then re-run this installer."
}

create_bottle() {
  say "Creating the Windows environment (\"bottle\")"
  if bottle_prefix >/dev/null 2>&1; then
    ok "Bottle \"$BOTTLE\" already exists."
  else
    # WhiskyCmd create takes only the bottle name (no --win-version flag).
    "$WHISKYCMD" create "$BOTTLE" || die "Couldn't create the Whisky bottle."
  fi

  local prefix; prefix="$(bottle_prefix)" || die "Bottle created but its folder wasn't found."

  # A freshly created bottle has no Wine prefix (drive_c) yet. The GUI dialog only
  # fetches the shared runtime; the per-bottle prefix is created on first Wine run.
  # So: make sure the runtime exists, then bootstrap the prefix ourselves.
  if [[ ! -d "$prefix/drive_c/windows/system32" ]]; then
    ensure_wine_runtime
    say "Setting up the Windows files inside the bottle (no clicks needed)"
    "$WHISKYCMD" run "$BOTTLE" wineboot >/dev/null 2>&1 || true   # async; creates drive_c
    local tries=0
    until [[ -d "$prefix/drive_c/windows/system32" ]] || [[ $tries -ge 60 ]]; do
      sleep 2; tries=$((tries+1))
    done
    [[ -d "$prefix/drive_c/windows/system32" ]] || die "Couldn't set up the Windows files in the bottle. Tell Alec (log: $LOG)."
  fi
  ok "Bottle ready at: $prefix"
}

# ---- steam + vc++ ---------------------------------------------------------
steam_dir() { echo "$(bottle_prefix)/drive_c/Program Files (x86)/Steam"; }

install_steam() {
  say "Installing Steam into the bottle"
  local steam_exe; steam_exe="$(steam_dir)/steam.exe"

  if [[ -f "$steam_exe" ]]; then
    ok "Steam already installed in the bottle."
  else
    local setup; setup="$(mktemp -t SteamSetup).exe"
    curl -fL "https://cdn.fastly.steamstatic.com/client/installer/SteamSetup.exe" -o "$setup" \
      || die "Couldn't download the Steam installer."
    say "Running the Steam installer (silent)"
    "$WHISKYCMD" run "$BOTTLE" "$setup" /S || warn "Steam installer returned nonzero; checking for steam.exe anyway."
    rm -f "$setup"
    [[ -f "$steam_exe" ]] || die "Steam did not install. Tell Alec (check the log)."
    ok "Steam installed."
  fi

  say "Installing the Visual C++ runtime into the bottle (harmless if already there)"
  local vc; vc="$(mktemp -t vc_redist).exe"
  if curl -fL "https://aka.ms/vs/17/release/vc_redist.x64.exe" -o "$vc"; then
    "$WHISKYCMD" run "$BOTTLE" "$vc" /install /quiet /norestart || warn "VC++ installer returned nonzero; continuing."
    rm -f "$vc"
  else
    warn "Couldn't download VC++ runtime; continuing (the game may still work)."
  fi
  ok "Steam + VC++ step done."
}

# ---- dxmt -----------------------------------------------------------------
deploy_dxmt() {
  say "Enabling DXMT (the graphics translation the game needs)"
  local prefix; prefix="$(bottle_prefix)" || die "No bottle for DXMT."
  local support="$HOME/Library/Application Support/com.franke.Whisky"
  local dxmt="$support/Libraries/DXMT"
  local wine="$support/Libraries/Wine/bin/wine64"
  local wineserver="$support/Libraries/Wine/bin/wineserver"
  local sys32="$prefix/drive_c/windows/system32"
  local syswow="$prefix/drive_c/windows/syswow64"

  [[ -d "$dxmt/x64" ]] || die "DXMT libraries missing from Whisky. Tell Alec."
  [[ -x "$wine" ]] || die "Wine not found in Whisky. Tell Alec."

  WINEPREFIX="$prefix" "$wineserver" -k 2>/dev/null || true

  local f
  for f in d3d11 dxgi d3d10core; do
    [[ -f "$sys32/$f.dll" ]] && cp -n "$sys32/$f.dll" "$sys32/$f.dll.pre-dxmt.bak" 2>/dev/null || true
  done
  for f in d3d11 dxgi d3d10core; do
    cp -f "$dxmt/x64/$f.dll" "$sys32/$f.dll"
    [[ -f "$dxmt/x32/$f.dll" ]] && cp -f "$dxmt/x32/$f.dll" "$syswow/$f.dll" || true
  done
  for f in winemetal nvngx nvapi64; do
    [[ -f "$dxmt/x64/$f.dll" ]] && cp -f "$dxmt/x64/$f.dll" "$sys32/$f.dll" || true
  done

  export WINEPREFIX="$prefix" WINEDEBUG=-all
  for f in d3d11 dxgi d3d10core; do
    "$wine" reg add "HKCU\\Software\\Wine\\DllOverrides" /v "$f" /d "native,builtin" /f >/dev/null 2>&1
  done
  WINEPREFIX="$prefix" "$wineserver" -k 2>/dev/null || true

  local size; size="$(stat -f%z "$sys32/d3d11.dll")"
  [[ "$size" -gt 1000000 ]] || die "DXMT didn't deploy (d3d11.dll is only ${size} bytes, expected multi-MB)."
  ok "DXMT enabled (d3d11.dll ${size} bytes)."
}

# ---- wait for game + launch option ---------------------------------------
wait_for_game() {
  say "Time to log in and install the game"
  "$WHISKYCMD" run "$BOTTLE" "$(steam_dir)/steam.exe" >/dev/null 2>&1 &
  printf '\n\033[1;37m  Steam is starting. Do these steps, in order:\033[0m\n'
  printf '\033[1;37m   1.\033[0m Steam often opens BEHIND this window. Look in your Dock for the\n'
  printf '      Steam icon and click it to bring it to the front.\n'
  printf '\033[1;37m   2.\033[0m Let Steam download and update its own files for a minute\n'
  printf '      (you will see an "updating" window).\n'
  printf '\033[1;37m   3.\033[0m At the login screen, log in: scan the QR code with the Steam\n'
  printf '      phone app, or type your username and password.\n'
  printf '\033[1;37m   4.\033[0m Open your Library, find MECCHA CHAMELEON, and click Install.\n'
  printf '      Do not own it yet? Go to the Store tab, buy it first, and it will\n'
  printf '      then show up in your Library to install.\n'
  printf '\033[1;37m   5.\033[0m Wait until it is FULLY downloaded. Do NOT press Play.\n'
  pause_for "When MECCHA CHAMELEON has finished downloading (and you did NOT press Play), press Return."

  local manifest exe
  manifest="$(steam_dir)/steamapps/appmanifest_${APPID}.acf"
  exe="$(steam_dir)/steamapps/common/MECCHA CHAMELEON/Chameleon/Binaries/Win64/PenguinHotel-Win64-Shipping.exe"
  while [[ ! -f "$exe" ]]; do
    warn "I don't see the game fully installed yet."
    [[ -f "$manifest" ]] && warn "(It looks like it's still downloading.)"
    pause_for "Wait until MECCHA CHAMELEON shows as Installed in your Library (not still downloading), do NOT press Play, then press Return."
  done
  ok "Game detected."
}

find_localconfig() {
  # Echo the localconfig.vdf whose apps block references our APPID; else the sole user.
  local f
  for f in "$(steam_dir)"/userdata/*/config/localconfig.vdf; do
    [[ -f "$f" ]] || continue
    grep -q "\"$APPID\"" "$f" && { echo "$f"; return 0; }
  done
  local first; first="$(ls "$(steam_dir)"/userdata/*/config/localconfig.vdf 2>/dev/null | head -1)"
  [[ -n "$first" ]] && { echo "$first"; return 0; }
  return 1
}

vdf_set_launchopts() {
  # $1 vdf path, $2 appid, $3 raw launch option value (unescaped).
  # Returns 0 on success, 2 if the file structure is unrecognized.
  # The value is passed via the environment (VDF_VALUE) and emitted with awk
  # `print` so neither awk's -v escape handling nor sub()'s &/\ handling can
  # mangle the VDF backslashes and quotes.
  local vdf="$1" appid="$2" raw="$3"
  [[ -f "$vdf" ]] || return 2

  # VDF-escape: backslash -> \\, doublequote -> \"
  local esc="$raw"
  esc="${esc//\\/\\\\}"
  esc="${esc//\"/\\\"}"
  export VDF_VALUE="\"$esc\""   # the full quoted value field

  cp "$vdf" "$vdf.$(date +%Y%m%d-%H%M%S).bak"

  # Must contain the apps section to be a recognizable localconfig.
  grep -q '"apps"' "$vdf" || return 2

  if grep -qE "^[[:space:]]*\"$appid\"[[:space:]]*$" "$vdf"; then
    # The app block exists (id is a lone key followed by a brace). Enter it,
    # replace LaunchOptions if present, otherwise insert before the closing brace.
    awk -v id="$appid" '
      BEGIN { val = ENVIRON["VDF_VALUE"] }
      !inblk && $0 ~ ("^[ \t]*\"" id "\"[ \t]*$") { pend=1; print; next }
      pend && $0 ~ /^[ \t]*\{[ \t]*$/ { pend=0; inblk=1; depth=1; print; next }
      inblk {
        if ($0 ~ /^[ \t]*\{[ \t]*$/) { depth++; print; next }
        if ($0 ~ /^[ \t]*\}[ \t]*$/) {
          depth--
          if (depth == 0) {
            if (!done) { print "\t\t\t\t\t\t\"LaunchOptions\"\t\t" val; done=1 }
            inblk=0; print; next
          }
          print; next
        }
        if ($0 ~ /"LaunchOptions"/ && !done) {
          match($0, /^[ \t]*/); ind=substr($0, 1, RLENGTH)
          print ind "\"LaunchOptions\"\t\t" val; done=1; next
        }
        print; next
      }
      { print }
    ' "$vdf" > "$vdf.tmp" && mv "$vdf.tmp" "$vdf"
  else
    # Inject a whole appid block right after the apps opening brace.
    awk -v id="$appid" '
      BEGIN { val = ENVIRON["VDF_VALUE"] }
      { print }
      /"apps"/ { pend=1; next }
      pend && $0 ~ /^[ \t]*\{[ \t]*$/ && !done {
        print "\t\t\t\t\t\"" id "\""
        print "\t\t\t\t\t{"
        print "\t\t\t\t\t\t\"LaunchOptions\"\t\t" val
        print "\t\t\t\t\t}"
        done=1; pend=0
      }
    ' "$vdf" > "$vdf.tmp" && mv "$vdf.tmp" "$vdf"
  fi

  grep -q "LaunchOptions" "$vdf" || return 2
  return 0
}

paste_fallback() {
  printf '%s' "$LAUNCH_OPTS" | pbcopy
  "$WHISKYCMD" run "$BOTTLE" "$(steam_dir)/steam.exe" "steam://gameproperties/$APPID" >/dev/null 2>&1 &
  pause_for "I copied the launch line to your clipboard. In the game's Properties window, click the Launch Options box and paste (Cmd+V), then close it."
}

kill_bottle() {
  # Shut down everything running inside the bottle. `wineserver -k` is the
  # canonical, prefix-scoped way and is reliable; pkill on steam.exe is a backup.
  # Do NOT match on the WINE_ENABLE_POSIX_SIGNALS env marker: it only shows in
  # the process listing for some launches, so it silently matches nothing.
  # steam.exe matches only the bottle's Steam, never the native macOS Steam.
  local prefix ws
  prefix="$(bottle_prefix 2>/dev/null)" || true
  ws="$HOME/Library/Application Support/com.franke.Whisky/Libraries/Wine/bin/wineserver"
  [[ -n "${prefix:-}" && -x "$ws" ]] && WINEPREFIX="$prefix" "$ws" -k 2>/dev/null || true
  pkill -9 -f "steam.exe" 2>/dev/null || true
}

set_launch_option() {
  say "Setting the launch option that makes the game start correctly"
  # Force-quit the bottle's Steam ourselves. If Steam is running when we edit its
  # config, it overwrites our change on exit and the game then fails with a VC++
  # error.
  say "Closing Steam so the setting saves correctly (automatic, no clicks needed)"
  kill_bottle
  local tries=0
  while pgrep -f "steam.exe" >/dev/null 2>&1 && [[ $tries -lt 15 ]]; do
    kill_bottle; sleep 1; tries=$((tries+1))
  done

  local vdf
  if ! vdf="$(find_localconfig)"; then
    paste_fallback
    return
  fi
  if vdf_set_launchopts "$vdf" "$APPID" "$LAUNCH_OPTS"; then
    ok "Launch option saved automatically."
  else
    warn "Couldn't save it automatically; using the copy-paste method instead."
    paste_fallback
  fi
}

# ---- play launcher + final check -----------------------------------------
make_play_launcher() {
  say "Putting a \"Play\" button on your Desktop"
  local launcher="$HOME/Desktop/Play MECCHA CHAMELEON.command"
  cat > "$launcher" <<EOF
#!/usr/bin/env bash
# Launches MECCHA CHAMELEON through Steam (so it gets its Steam login token).
"$WHISKYCMD" run "$BOTTLE" "$(steam_dir)/steam.exe" "steam://rungameid/$APPID"
EOF
  chmod +x "$launcher"
  xattr -dr com.apple.quarantine "$launcher" 2>/dev/null || true
  ok "Created: $launcher"
}

self_verify() {
  say "Final check"
  local prefix; prefix="$(bottle_prefix)" || die "Bottle missing at final check."
  local sys32="$prefix/drive_c/windows/system32"
  local pass=1
  [[ -x "$WHISKYCMD" ]] || { warn "Whisky missing"; pass=0; }
  [[ -f "$prefix/drive_c/Program Files (x86)/Steam/steam.exe" ]] || { warn "Steam missing"; pass=0; }
  [[ "$(stat -f%z "$sys32/d3d11.dll" 2>/dev/null || echo 0)" -gt 1000000 ]] || { warn "DXMT d3d11.dll looks like a stub"; pass=0; }
  [[ -f "$HOME/Desktop/Play MECCHA CHAMELEON.command" ]] || { warn "Play launcher missing"; pass=0; }
  if [[ $pass -eq 1 ]]; then
    ok "All set. Double-click \"Play MECCHA CHAMELEON\" on your Desktop to play."
    echo "First launch compiles shaders, so the window may be black for a minute. That's normal."
  else
    warn "Some checks failed. Send Alec this file: $LOG"
  fi
}

# ---- main -----------------------------------------------------------------
main() {
  # Send everything to console AND the log (only when actually running, not when sourced for tests).
  exec > >(tee -a "$LOG") 2>&1
  trap on_err ERR

  say "MECCHA CHAMELEON installer starting ($(date))"
  preflight
  ensure_rosetta
  install_whisky
  create_bottle
  install_steam
  deploy_dxmt
  wait_for_game
  set_launch_option
  make_play_launcher
  self_verify
}

# Run main UNLESS this file is being *sourced* (e.g. by the test harness).
#   - direct execution (./install.command):       BASH_SOURCE[0] == $0     -> run
#   - curl one-liner (bash -c "$(curl ...)"):      BASH_SOURCE[0] is empty  -> run
#   - sourced (source install.command, in tests):  BASH_SOURCE[0] set, != $0 -> skip
# Use `if` (not `&& main`) so a false test doesn't trip `set -e`.
if [[ -z "${BASH_SOURCE[0]:-}" || "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
