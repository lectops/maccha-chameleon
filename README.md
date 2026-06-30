# maccha-chameleon: Play MECCHA CHAMELEON on Mac (Apple Silicon)

**How to play [MECCHA CHAMELEON](https://store.steampowered.com/app/4704690/) on a Mac, with one command.**

MECCHA CHAMELEON is a Windows-only game. This installer gets it running on Apple Silicon Macs automatically: it sets up [Whisky](https://github.com/frankea/Whisky) (an open-source Windows compatibility layer), installs Steam inside it, enables the right graphics translation (DXMT), and applies the one tweak the game needs to launch. No CrossOver licence, no Homebrew, no terminal expertise required.

You still need to buy the game on Steam. This installer just sets up the copy you own to run on a Mac.

When it finishes you get a **Play MECCHA CHAMELEON** button on your Desktop. That's it.

---

## What you need

- A **Mac with Apple Silicon** (M1, M2, M3, M4, or newer).
- **macOS 15 (Sequoia)** or newer.
- To **own MECCHA CHAMELEON on your own Steam account**. Don't own it yet? You can buy it from the Steam Store during the install. The game costs money; this installer does not get you the game, it just makes the copy you own run on a Mac.

---

## Install (one command)

Open the **Terminal** app (press `Cmd`+`Space`, type `Terminal`, press Return), then paste this and press Return:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/lectops/maccha-chameleon/main/install.command)"
```

Then just follow the prompts. The whole thing is guided, and it pauses to let you log into Steam and install the game.

### Prefer not to use Terminal?

1. Download **`install.command`** from this repo (click the file, then the download button).
2. **Right-click it and choose Open** (the first time only). macOS blocks downloaded scripts until you do this once. Click **Open** in the dialog.
3. Follow the prompts.

---

## What it does, step by step

1. Checks your Mac is supported (Apple Silicon, macOS 15+, enough space).
2. Installs Whisky (downloaded straight from its official release, version-pinned and checksum-verified).
3. Creates a Windows environment and downloads its support files (one click in Whisky the first time).
4. Installs Steam and the Visual C++ runtime inside it.
5. Turns on **DXMT**, the Direct3D-to-Metal translation the game needs.
6. Pauses so you can **log into Steam and install MECCHA CHAMELEON**.
7. Applies the launch setting that makes the game start correctly.
8. Drops a **Play MECCHA CHAMELEON** launcher on your Desktop.

First launch is slow because the game compiles its shaders. The window may be black for a minute. That is normal.

---

## Playing

Double-click **Play MECCHA CHAMELEON** on your Desktop. It launches through Steam so your session is signed in.

---

## If something goes wrong

The installer writes a full log to `~/meccha-install.log`. If you hit a snag, open an issue here and attach that file.

You can also just run the installer again. Every step is safe to repeat, so if your game download wasn't finished the first time, double-click and continue.

---

## Uninstall / start over

This repo includes `reset-whisky.sh`, which removes Whisky and everything it created (the Windows environment, Steam inside it, the game, and saved logins) and returns your Mac to a clean state:

```bash
bash reset-whisky.sh
```

Note: macOS protects an app's sandbox folder once it has been used. If the script can't remove the last folder, it tells you exactly how to drag it to the Trash. That leftover empty folder is harmless and does not affect reinstalling.

---

## How it works (for the curious)

The maintained [frankea fork of Whisky](https://github.com/frankea/Whisky) bundles **DXMT** (Direct3D 11 to Metal) and DXVK. It does **not** ship Apple's Game Porting Toolkit, so there is no Direct3D 12 path; the game runs in D3D11 via DXMT and runs well.

Two non-obvious things this installer handles for you:

- **The Unreal bootstrapper is broken under Wine.** The game's launcher does a Visual C++ prerequisite check that fails even when VC++ is installed. The fix is to bypass it and launch the actual shipping executable directly, which this installer sets as the Steam launch option.
- **Steam must be fully closed when that option is written**, or Steam overwrites it on exit. The installer shuts Steam down itself before saving, so you don't have to.

---

## Credits, and please support the people who make this possible

This installer is just glue. The real work belongs to others:

- **Wine** is the open-source compatibility layer that runs Windows software on macOS. The bulk of Wine is written and funded by [**CodeWeavers**](https://www.codeweavers.com/wine), the company behind the paid app [**CrossOver**](https://www.codeweavers.com/). Their developers account for roughly two-thirds of all Wine commits, and CrossOver sales are what pay for that work. If this is useful to you and you can afford it, **buy CrossOver**. It runs this same game (and a lot more) with proper support, and it directly funds the Wine development that everything here depends on.
- [**Whisky**](https://github.com/frankea/Whisky) is the macOS Wine wrapper this uses. The original Whisky was made by Isaac Marovitz, who retired it in 2025 and pointed people to CrossOver for exactly the reason above. This installer uses the community-maintained frankea fork. Thanks to Isaac and the fork maintainers.
- [**DXMT**](https://github.com/3Shain/dxmt) by 3Shain provides the Direct3D 11 to Metal translation that makes the game render.

### Disclaimer

- Unofficial community installer. Not affiliated with or endorsed by the developers of MECCHA CHAMELEON, Valve, Apple, CodeWeavers, or the Whisky authors.
- You must own the game. This does not bypass purchase, DRM, or Steam login in any way.

Made so I could play with friends who only have a Mac.
