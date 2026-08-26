# GambleLand

A Hyprland desktop: the compositor configured in Lua, plus **gambleland** — a
[Quickshell](https://quickshell.org) shell providing the bar, launcher, global
menu, notifications, OSDs, capture/recording, power menu and settings app.

```
hypr/        hyprland.lua + conf/*.lua   (Hyprland 0.56+, Lua config)
quickshell/  shell.qml, Modules, Services, Theme, Assets, scripts
bin/         gambleland-setup            (copies the configs into ~/.config)
PKGBUILD     the package
```

## Install

```bash
git clone https://github.com/Jonohas/GambleLand.git
cd GambleLand
makepkg -si          # builds and installs the gambleland package + dependencies
gambleland-setup     # copies the configs into ~/.config (run as your user)
```

Then log out and pick the **GambleLand** session, or run `Hyprland` from a TTY.

Everything comes from the Arch `extra` repository — no AUR helper needed.

## Updating

The package owns `/usr/share/gambleland`; your copies in `~/.config` are yours.
After a `pacman -Syu` that bumps `gambleland`:

```bash
gambleland-setup --force    # backs up ~/.config/{hypr,quickshell} first
```

Without `--force` the command refuses to touch existing config and exits 3, so
it can never eat local edits by accident.

## What is where

| Path | Purpose |
| --- | --- |
| `hypr/hyprland.lua` | entry point; requires each `conf/*.lua` module |
| `hypr/conf/binds.lua` | keybinds — media keys and brightness route through the shell's IPC |
| `hypr/conf/autostart.lua` | starts the appmenu daemon, `qs`, hyprpaper, hypridle, solaar |
| `quickshell/shell.qml` | shell entry point |
| `quickshell/Services/` | brightness, network, bluetooth, audio, notifications, capture |
| `quickshell/scripts/gambleland-appmenud.py` | `com.canonical.AppMenu.Registrar` for the global menu |

## Optional pieces

`kitty` (`SUPER+Q`), `dolphin` (`SUPER+E`), `ddcutil` (external-monitor
backlight over DDC/CI), `brightnessctl` (internal panel), `playerctl` (media
keys), `upower` (battery), `solaar` (Logitech gestures — needs your own
`~/.config/solaar/rules.yaml`). All are `optdepends`; the shell degrades
without them.

## Tests

```bash
tests/test-setup.sh
```
