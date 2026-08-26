# c7shell

A Hyprland desktop: the compositor configured in Lua, plus **c7shell** — a
[Quickshell](https://quickshell.org) shell providing the bar, launcher, global
menu, notifications, OSDs, capture/recording, power menu and settings app.

```
hypr/                 hyprland.lua + conf/*.lua   (Hyprland 0.56+, Lua config)
quickshell/c7shell/   shell.qml, Modules, Services, Theme, Assets, bin, scripts
bin/                  c7shell-setup   (copies the configs into ~/.config)
PKGBUILD              the package
```

## Install

```bash
git clone https://github.com/Jonohas/c7shell.git
cd c7shell
makepkg -si          # builds and installs the c7shell package + dependencies
c7shell-setup     # copies the configs into ~/.config (run as your user)
```

Then log out and pick the **c7shell** session, or run `Hyprland` from a TTY.

The shell installs as a [named Quickshell
config](https://quickshell.org/docs/master/guide/distribution/) at
`~/.config/quickshell/c7shell`, so it never collides with a Quickshell config
you already have. It runs as `qs -c c7shell`, and every `qs ipc call` in
`hypr/conf/binds.lua` carries the same `-c c7shell`.

Everything comes from the Arch `extra` repository — no AUR helper needed.

## Updating

The package owns `/usr/share/c7shell`; your copies in `~/.config` are yours.
After a `pacman -Syu` that bumps `c7shell`:

```bash
c7shell-setup --force    # backs up ~/.config/hypr and ~/.config/quickshell/c7shell first
```

Without `--force` the command refuses to touch existing config and exits 3, so
it can never eat local edits by accident.

## What is where

| Path | Purpose |
| --- | --- |
| `hypr/hyprland.lua` | entry point; requires each `conf/*.lua` module |
| `hypr/conf/binds.lua` | keybinds — media keys and brightness route through the shell's IPC |
| `hypr/conf/autostart.lua` | starts the appmenu daemon, `qs`, hyprpaper, hypridle, solaar |
| `hypr/xdph.conf` | points xdph's screencopy picker at the shell's own picker |
| `quickshell/c7shell/shell.qml` | shell entry point |
| `quickshell/c7shell/Services/` | brightness, network, bluetooth, audio, notifications, capture |
| `quickshell/c7shell/bin/screenshare-picker.sh` | xdph `custom_picker_binary` wrapper |
| `quickshell/c7shell/scripts/c7shell-appmenud.py` | `com.canonical.AppMenu.Registrar` for the global menu |

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
