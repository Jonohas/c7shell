# c7shell

A Hyprland desktop: the compositor configured in Lua, plus **c7shell** — a
[Quickshell](https://quickshell.org) shell providing the bar, launcher, global
menu, notifications, OSDs, capture/recording, power menu and settings app.

```
hypr/                 hyprland.lua + conf/*.lua   (Hyprland 0.56+, Lua config)
quickshell/c7shell/   shell.qml, Modules, Services, Theme, Assets, bin, scripts
bin/                  c7shell-setup (copies the configs into ~/.config),
                      c7shell-doctor (checks the runtime requirements)
PKGBUILD              the package
```

## Install

```bash
git clone https://github.com/Jonohas/c7shell.git
cd c7shell
./install.sh         # builds and installs the c7shell package + dependencies
c7shell-setup        # copies the configs into ~/.config (run as your user)
```

`install.sh` is a thin wrapper around `makepkg -si`. On a fresh machine
`makepkg` aborts before it reads the PKGBUILD if the Arch build tools are not
there ("Cannot find the fakeroot binary", "Cannot find the debugedit binary"),
so the wrapper installs `base-devel` first and then hands every argument you
gave it to `makepkg`. If you already have `base-devel`, `makepkg -si` on its
own still works exactly as before.

After the build it runs `c7shell-doctor`, which checks everything `pacman`
cannot: that Hyprland is 0.56 or newer (older versions do not read
`hyprland.lua` at all), that quickshell was built with every QML module the
shell imports, that the appmenu daemon's python modules import, that there is
a DRM device to open, and that the configs have reached `~/.config`. Anything
missing is reported with the package that provides it, and
`c7shell-doctor --fix` installs those packages. Run it any time:

```bash
c7shell-doctor          # required + optional checks, exits 1 if something required is missing
c7shell-doctor --quiet  # problems only
c7shell-doctor --fix    # pacman -S --needed the packages behind the failures
```

A session that shows a black screen and drops straight back to the greeter is
almost always one of the things it checks — most often that `c7shell-setup`
was never run, since the package installs to `/usr/share/c7shell` and neither
hyprland nor quickshell reads config from there.

The PKGBUILD is a git source: `makepkg` clones the branch named in it and
builds *that*, not the working tree you run `./install.sh` from. Local commits
and pulled feature branches therefore do nothing until they are pushed and
named — to build one, `C7SHELL_BRANCH=my-branch ./install.sh`.

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
tests/test-doctor.sh
```
