# c7shell

A Hyprland desktop: the compositor configured in Lua, plus **c7shell** — a
[Quickshell](https://quickshell.org) shell providing the bar, launcher, global
menu, notifications, OSDs, capture/recording, power menu and settings app.

```
hypr/                 hyprland.lua + conf/*.lua   (Hyprland 0.56+, Lua config)
quickshell/c7shell/   shell.qml, Modules, Services, Theme, Assets, bin, scripts
bin/                  c7shell-setup (copies the configs into ~/.config),
                      c7shell-doctor (checks the runtime requirements),
                      c7shell-bootstrap (sets up a bare Arch install),
                      c7shell-upgrade (updates an existing install)
PKGBUILD              the package
```

## Install

From a bare Arch install — a CLI, `sudo` and a network connection is enough:

```bash
git clone https://github.com/Jonohas/c7shell.git
cd c7shell
./install.sh         # bootstrap the system, then build and install c7shell
c7shell-setup        # copies the configs into ~/.config (run as your user)
```

`./install.sh` runs four steps, and shows you the plan before it changes
anything:

1. **build tools** — `base-devel`, because `makepkg` will not start without
   them (see below).
2. **`c7shell-bootstrap`** — what a fresh Arch box is missing underneath the
   session: GPU driver, SDDM, the pipewire daemons, fonts, an icon theme,
   `xdg-utils`, and the enabled system services. It prints the whole plan and
   waits for a `y` first. `./install.sh --dry-run` shows that plan and stops.
3. **`makepkg -si`** — builds and installs the package itself.
4. **`c7shell-doctor`** — checks the result and offers the optional programs.

What the bootstrap decides for you, and how to override it:

| Area | What it does |
| --- | --- |
| GPU | `lspci` detection → `mesa` plus `vulkan-intel` / `vulkan-radeon`, or `nvidia-open-dkms` + `nvidia-utils` + the headers of every installed kernel, and `/etc/modprobe.d/c7shell-nvidia.conf` setting `nvidia_drm modeset=1`. A pre-Turing card (GTX 10xx and older) is reported, not guessed at — `nvidia-open-dkms` does not support it. `--no-drivers` opts out. |
| Greeter | `sddm`, enabled but not started, so it takes over at the next boot. If gdm/lightdm/greetd is already enabled it says so and enables nothing — two display managers fight over the seat and neither comes up. `--no-greeter` opts out. |
| Audio | `pipewire`, `pipewire-pulse`, `pipewire-alsa`, `wireplumber` + the user units. `wireplumber` is a session manager, not a sound server: without the daemons under it the volume keys do nothing. |
| Network | `NetworkManager` and `bluetooth` enabled — unless `systemd-networkd` or `iwd` is already driving the network, in which case it warns instead of stacking two managers on one link. |
| Fonts, icons | `ttf-jetbrains-mono` (`Theme.fontMono`), `noto-fonts`, `noto-fonts-emoji`, `hicolor`/`adwaita`/`breeze` icon themes for the launcher's real app icons. |
| Qt app theming | `plasma-integration` + `breeze` + `breeze-icons`, but **only** alongside `dolphin` — installed with it, added if the machine already has it, skipped otherwise. Nothing in the shell needs them; only QWidget-based Qt/KDE apps do. |
| AUR | `paru` (the source package, so it links the libalpm actually installed -- `paru-bin` ships a binary built against one specific `libalpm.so` while declaring `libalpm.so>=14`, so pacman lets it outlive the soname it needs) if no *working* AUR helper is present, for `ttf-space-grotesk` (`Theme.fontDisplay`, not in the official repos; fontconfig falls back without it). `--no-aur` opts out. |
| Extras | `kitty`, `dolphin` (the SUPER+Q / SUPER+E binds), `ddcutil`, `brightnessctl`, `playerctl`, plus `i2c-dev` and the `i2c` group so `ddcutil` can reach external monitors. `--no-extras` opts out. |

It also runs a full `pacman -Syu` first: a partial upgrade is unsupported on
Arch, and a DKMS driver built against the headers of a kernel you are not
running is the same as no driver at all. `--no-upgrade` skips it.

`c7shell-bootstrap` is installed as a command too, so it can be re-run later
(`c7shell-bootstrap --dry-run` to see what it would change).

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
c7shell-doctor            # required + optional checks, exits 1 if something required is missing
c7shell-doctor --quiet    # problems only
c7shell-doctor --fix      # pacman -S --needed the packages behind the failures
c7shell-doctor --optional # pick which of the optional packages to install
```

`install.sh` ends with the `--optional` picker: it lists the optional packages
you do not have — terminal, file manager, `ddcutil`/`brightnessctl`, `upower`,
`playerctl`, `solaar`, `jq`, `kwallet` — with what each one is for, and installs
only the ones you choose (numbers, ranges, `a` for all, enter for none).
Nothing is installed without a selection, and with no terminal to ask on it
says so and moves on. `C7SHELL_SKIP_OPTIONAL=1 ./install.sh` skips the
question entirely.

A session that shows a black screen and drops straight back to the greeter is
almost always one of the things it checks — most often that `c7shell-setup`
was never run, since the package installs to `/usr/share/c7shell` and neither
hyprland nor quickshell reads config from there.

The PKGBUILD is a git source: `makepkg` clones the branch named in it and
builds *that*, not the working tree you run `./install.sh` from. Local commits
and pulled feature branches therefore do nothing until they are pushed and
named — to build one, `C7SHELL_BRANCH=my-branch ./install.sh`.

Then log out and pick the **c7shell** session, or run `start-hyprland` from a
TTY. `start-hyprland` rather than `Hyprland`: since 0.53 it is the launcher
Hyprland expects, it exports the session and portal environment, and it gives
you crash recovery and safe mode. Launching the binary directly makes Hyprland
warn that it "was started without start-hyprland".

The shell installs as a [named Quickshell
config](https://quickshell.org/docs/master/guide/distribution/) at
`~/.config/quickshell/c7shell`, so it never collides with a Quickshell config
you already have. It runs as `qs -c c7shell`, and every `qs ipc call` in
`hypr/conf/binds.lua` carries the same `-c c7shell`.

Everything comes from the Arch `extra` repository — no AUR helper needed.

## Qt and KDE app colours

The shell's palette lives in `~/.config/hypr/appearance.json`; Qt and KDE apps
read `~/.config/kdeglobals`. `quickshell/c7shell/scripts/c7shell-theme-export.py`
writes the second from the first and emits the signal that repaints running
apps — the settings app runs it whenever the accent or variant changes, and
`c7shell-setup` seeds it once at install time so a fresh session is not a
themed shell beside a stock-looking dolphin.

This only applies if you actually run a QWidget-based Qt/KDE app. The shell
itself is QML — the bar, launcher and settings window take none of this — so
the packages below are `optdepends`, the bootstrap installs them only together
with `dolphin`, and `c7shell-doctor` skips the whole section on a machine with
no such app rather than warning about something it has no use for. Picking
`dolphin` in `c7shell-doctor --optional` brings them along, since dolphin
without them is dolphin that ignores the palette.

When one is installed, three things have to be in place, and `c7shell-doctor`
checks all three:

- `QT_QPA_PLATFORMTHEME=kde` — set in `hypr/conf/environment.lua`. Not `qt6ct`:
  KDE apps ignore qt6ct's palette and come up stock light while their
  KColorScheme parts stay dark, which is the mixed look.
- **`plasma-integration`** — provides the `kde` platform theme plugin
  (`/usr/lib/qt6/plugins/platformthemes/KDEPlasmaPlatformTheme6.so`). Without
  it the variable above does nothing at all.
- **`breeze`** — the Qt6 widget style that platform theme draws with.

To export by hand at any time:

```bash
python3 ~/.config/quickshell/c7shell/scripts/c7shell-theme-export.py
```

## Global menu

Apps that export a menu bar over dbusmenu — dolphin and other Qt/KDE apps —
show it in the top bar next to the workspaces, and hide their own. That is a
choice, not a fixture: **settings → topbar → global menu** turns it off, and
the setting persists in `~/.config/hypr/shell.json`.

The switch is the `com.canonical.AppMenu.Registrar` bus name itself, not just
the chips in the bar. An app hands its menu bar over precisely because it finds
that name owned, so a shell that only stopped drawing the export would leave
dolphin with no menus anywhere. Off tells `c7shell-appmenud` to release the
name; on tells it to take it back.

A toolkit asks for the registrar once, when a window's menu bar is created, and
caches the answer — so windows that are already open keep the menu bar they
started with. Reopen them to see the change.

## Updating

```bash
c7shell-upgrade              # rebuild the package from git, then refresh ~/.config
c7shell-upgrade --dry-run    # show what both halves would change
```

`pacman -Syu` cannot do this: `c7shell` is built locally, so there is no
repository to upgrade it from. `c7shell-upgrade` keeps a build clone under
`~/.cache/c7shell`, rebuilds when the installed commit is behind (the commit is
baked into `pkgver`), and then refreshes the configs.

The config half is pacnew-style, because `~/.config` is yours to edit:

| Your file | What happens |
| --- | --- |
| untouched since it was installed | updated in place |
| edited by you, and changed upstream | **kept**, new version written beside it as `<file>.new`, listed at the end (exit 4) |
| edited by you, unchanged upstream | left alone |
| new upstream | added |
| dropped upstream, untouched by you | removed |
| dropped upstream, edited by you | kept, reported |

Which case a file falls into comes from a manifest of the hashes last
installed (`~/.local/state/c7shell/manifest`, written by `c7shell-setup` and
`c7shell-upgrade`). An install predating that manifest has nothing to compare
against, so every difference is treated as your edit and kept — the safe
direction, at the cost of more `.new` files on the first run.

`--package-only` and `--config-only` run one half. To replace your copies
outright instead, `c7shell-setup --force` still backs them up to
`.bak-<stamp>` first; without `--force` it refuses and exits 3, so it can never
eat local edits by accident.

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
| `~/.config/hypr/shell.json` | shell preferences the settings app writes (global menu) |

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
tests/test-bootstrap.sh
tests/test-upgrade.sh
```
