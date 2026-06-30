# MECCHA CHAMELEON on a Mac — free setup (Whisky + DXMT)

Verified working on an Apple M4 Max, macOS 26.5, June 2026. This replaces the
earlier draft, which assumed the old Whisky's D3D12-via-D3DMetal path. That path
does **not** work on the current maintained Whisky. Read the "Why this is different"
section before following a generic Whisky/Game Porting Toolkit guide — most of them
are wrong for this fork.

## TL;DR of the working config

- **Whisky:** the maintained **frankea** fork (Wine 11.0 runtime).
- **Graphics:** **DXMT** (Direct3D **11** → Metal). NOT D3DMetal/D3D12.
- **Steam launch options:** launch the game's **shipping exe directly** to skip the
  Unreal bootstrapper (whose prerequisite check is broken under Wine):
  ```
  "C:\Program Files (x86)\Steam\steamapps\common\MECCHA CHAMELEON\Chameleon\Binaries\Win64\PenguinHotel-Win64-Shipping.exe" %command%
  ```
- Launch from **Steam** (logged in) so Steamworks hands the game an auth token.

## Why this is different from every other guide

1. **No D3D12 on this fork.** The maintained frankea Whisky bundles **DXMT** (D3D11→Metal)
   and **DXVK** (D3D9-11→Vulkan). It does **not** ship Apple's GPTK/D3DMetal, so there is
   **no Direct3D 12 path at all**. Forcing `-dx12` gives "DirectX 12 is not supported on
   your system." The game runs fine in **D3D11** via DXMT.
2. **Don't bother manually installing GPTK 4.0 beta.** It loads (D3D12 actually
   initializes), but its `libd3dshared.dylib` is ABI-incompatible with Whisky's Wine 11.0
   threading and crashes instantly with a null-deref in `libsystem_pthread`. If you ever
   want the D3DMetal/D3D12 path, you'd need the GPTK version that matches Wine 11.0
   (GPTK **3.0**, Dec 2025 — *not* the 4.0 beta), and even then it's unsupported here.
   DXMT is the supported, working answer.
3. **The Unreal bootstrapper is broken under Wine.** `PenguinHotel.exe` at the game root
   is a UE5 launcher that prereq-checks Visual C++ and quits with
   "Microsoft Visual C++ 2015-2022 Redistributable (x64) is required" — even when VC++ is
   correctly installed. The fix is to bypass it and launch the real
   `PenguinHotel-Win64-Shipping.exe` directly (see launch options above).
4. **Env vars don't go in Steam launch options.** The Windows Steam client inside the
   bottle does **not** parse a `VAR=value %command%` prefix (that's a Linux/SteamOS Steam
   feature). Doing so gives "File not found." Per-bottle env vars go in Whisky's bottle
   Config, not Steam.

## Requirements

- **Apple Silicon** (M1+). **macOS Sequoia 15 / Tahoe 26 or newer.**
- Steam ownership of MECCHA CHAMELEON (log into the owning account, or Family Share it).
- ~6 GB free (Steam + 2.4 GB game).

## Step 1 — Install the maintained Whisky fork

```bash
bash setup-whisky.sh
```

Installs Rosetta 2, Homebrew (if missing), and `frankea/whisky/whisky`. The plain
`brew install --cask whisky` installs the **archived** original — always use the
qualified `frankea/whisky/whisky` form.

## Step 2 — Bottle + Steam + game (GUI)

1. Open **Whisky**. On first run it downloads the Wine runtime (~313 MB).
2. Create a bottle: **+** → **Windows 10**, 64-bit → name it `Steam`.
3. Get `SteamSetup.exe` from <https://store.steampowered.com/about/>.
4. In the bottle, **Run...** → `SteamSetup.exe`. Let Steam install/update, then **log in**.
5. Install MECCHA CHAMELEON (~2.4 GB).
6. (Recommended, harmless) Install the VC++ runtime into the bottle so the shipping exe's
   `msvcp140`/`vcruntime140` imports resolve: download
   <https://aka.ms/vs/17/release/vc_redist.x64.exe> and **Run...** it in the bottle.

## Step 3 — Enable DXMT for the bottle

**Preferred (GUI):** In Whisky → the `Steam` bottle → **Config**, enable **DXMT**
(listed as Experimental on app >= 3.4.0). Whisky copies the DXMT DLLs into the bottle and
wires up `winemetal` for you.

**If your build doesn't expose the toggle, deploy it manually:**

```bash
bash deploy-dxmt.sh "$HOME/Library/Containers/com.franke.Whisky/Bottles/<YOUR-BOTTLE-UUID>"
```

(Find the UUID with: `ls ~/Library/Containers/com.franke.Whisky/Bottles/`.)
The script copies DXMT's `d3d11`/`dxgi`/`d3d10core` (+ `winemetal`, and the
`nvngx`/`nvapi64` MetalFX/DLSS shims) into the bottle and sets the
`dxgi,d3d11,d3d10core=native,builtin` overrides. Steam must be closed when you run it.

## Step 4 — Set the launch options (bypass the bootstrapper)

In Steam → MECCHA CHAMELEON → **Properties → Launch Options**, paste **exactly**
(mind the leading quote):

```
"C:\Program Files (x86)\Steam\steamapps\common\MECCHA CHAMELEON\Chameleon\Binaries\Win64\PenguinHotel-Win64-Shipping.exe" %command%
```

No `-dx12`. No env-var prefix.

## Step 5 — Play

Press **Play** from Steam (so Steamworks authenticates the session). First launch
compiles UE5 shaders, so expect a black/slow window for a bit before the menu.

## Troubleshooting — the exact errors and what they mean

| Symptom | Cause | Fix |
|---|---|---|
| "File not found" | Env-var prefix or broken quoting in launch options | Use the exact launch string above (leading `"`, no `VAR=`). |
| "Microsoft Visual C++ 2015-2022 Redistributable (x64) is required" | Steam is launching the UE **bootstrapper** `PenguinHotel.exe`, whose prereq check is broken under Wine | Launch the **shipping exe** directly via launch options (Step 4). |
| "A D3D11-compatible GPU ... is required" | No D3D11 translation layer active | Enable **DXMT** (Step 3). |
| "DirectX 12 is not supported on your system" | You passed `-dx12`; this fork has no D3D12 | Remove `-dx12`. DXMT is D3D11 only. |
| In-game "invalid or missing authentication token" | Game launched outside Steam | Launch from the Steam client, logged in. |
| Instant crash, null-deref in `libsystem_pthread` (`libd3dshared` in backtrace) | You manually installed GPTK D3DMetal; the 4.0 beta is ABI-incompatible with Wine 11.0 | Don't use GPTK 4.0 beta. Use DXMT. |

## What this is NOT

DXMT (0.80, the last MIT build) is open source. There is no fully-free D3D12 path on this
fork; D3D12 needs Apple's proprietary GPTK D3DMetal, which isn't bundled and (at 4.0 beta)
doesn't run on Whisky's Wine 11.0 anyway.
