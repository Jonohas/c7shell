# Maintainer: Jonohas <https://github.com/Jonohas>
pkgname=c7shell
pkgver=0.1.0.r27.ga9d7ea2
pkgrel=1
pkgdesc='c7shell desktop environment: Hyprland (lua config) with the c7shell Quickshell shell'
arch=('any')
url='https://github.com/Jonohas/c7shell'
license=('MIT')
# Hyprland 0.56+ is required: the config is hyprland.lua, not hyprland.conf.
depends=(
  'hyprland>=0.56'
  'quickshell'
  'hypridle'
  'hyprlock'
  'hyprpaper'
  'hyprpicker'
  'hyprpolkitagent'
  'qt6-declarative'
  'wireplumber'
  'networkmanager'
  'bluez'
  'bluez-utils'
  'python'
  'python-dbus'
  'python-gobject'
  'grim'
  'wf-recorder'
  'wl-clipboard'
  'libnotify'
  'xdg-desktop-portal-hyprland'
  # xdph implements screencast, not Settings -- and Settings is the interface an
  # app asks whether the desktop prefers dark through. Without a backend that
  # implements it, everything that detects a system theme comes up light next to
  # a dark shell (appearance.json's colorScheme, exported by
  # scripts/c7shell-theme-export.py). hyprland-portals.conf already names gtk as
  # the fallback backend, so installing it is the whole fix.
  'xdg-desktop-portal-gtk'
)
optdepends=(
  'kitty: terminal bound to SUPER+Q'
  'dolphin: file manager bound to SUPER+E'
  # QT_QPA_PLATFORMTHEME=kde (hypr/conf/environment.lua) only means something
  # with plasma-integration's platform theme plugin, and it only matters if a
  # QWidget-based Qt/KDE app is installed to be themed. The shell itself is
  # QML, so a machine without such apps gains nothing from these three.
  'plasma-integration: makes Qt/KDE apps (dolphin) follow the c7shell palette'
  'breeze: Qt6 widget style that platform theme draws with'
  'breeze-icons: icon theme Qt/KDE apps expect'
  'hyprlauncher: fallback launcher (the shell provides its own)'
  'ddcutil: DDC/CI backlight control for external monitors'
  'brightnessctl: backlight control for internal panels'
  'upower: battery readout in the bar'
  'playerctl: media keys (XF86Audio{Next,Prev,Play,Pause})'
  'solaar: Logitech device support, autostarted if present'
  'jq: helper scripting'
  'kwallet: secret storage unlocked at login by conf/autostart.lua'
)
# lua: tests/test-monitors.lua loads conf/monitors.lua against a stubbed hl.
makedepends=('git' 'lua')
# makepkg builds the branch cloned here, NOT the working tree you run it from:
# a local commit or a pulled feature branch has no effect until it is pushed and
# named here. Override for testing a branch before it lands:
#   C7SHELL_BRANCH=my-branch ./install.sh
_branch=${C7SHELL_BRANCH:-main}
source=("$pkgname::git+$url.git#branch=$_branch")
sha256sums=('SKIP')
install="$pkgname.install"

pkgver() {
  cd "$srcdir/$pkgname"
  printf '0.1.0.r%s.g%s' "$(git rev-list --count HEAD)" "$(git rev-parse --short HEAD)"
}

check() {
  cd "$srcdir/$pkgname"
  # Every one of these stubs the machine it tests (pacman, lspci, systemctl,
  # $HOME), so they are safe to run mid-build and mean the package cannot be
  # built out of a tree whose scripts are broken.
  for t in tests/*.sh; do "$t"; done
  # From hypr/, because monitors.lua resolves its own require("conf/...")
  # relative to the working directory.
  cd hypr && lua ../tests/test-monitors.lua
}

package() {
  cd "$srcdir/$pkgname"

  # The configs are shipped read-only under /usr/share and copied into the
  # user's ~/.config by c7shell-setup: hyprland and quickshell both read
  # their config only from $XDG_CONFIG_HOME, and the user is expected to edit
  # what lands there. The shell ships as the named quickshell config
  # `quickshell/c7shell`, so it lands in ~/.config/quickshell/c7shell and
  # leaves any other config in ~/.config/quickshell alone (`qs -c c7shell`).
  install -dm755 "$pkgdir/usr/share/$pkgname"
  cp -a hypr quickshell "$pkgdir/usr/share/$pkgname/"
  # Dev-facing only, and setup copies whatever is here into the user's config.
  rm -rf "$pkgdir/usr/share/$pkgname/quickshell/c7shell/docs"
  chmod -R u=rwX,go=rX "$pkgdir/usr/share/$pkgname"
  chmod 755 "$pkgdir/usr/share/$pkgname/quickshell/c7shell/scripts/c7shell-appmenud.py" \
            "$pkgdir/usr/share/$pkgname/quickshell/c7shell/bin/screenshare-picker.sh"

  install -Dm755 bin/c7shell-setup "$pkgdir/usr/bin/c7shell-setup"
  # Checks what depends= cannot: the Hyprland version, the QML modules
  # quickshell was built with, the DRM device, and whether the configs have
  # been copied into ~/.config yet.
  install -Dm755 bin/c7shell-doctor "$pkgdir/usr/bin/c7shell-doctor"
  # Re-runnable after install: drivers, greeter, services and fonts are system
  # state a package must not touch itself, so it stays a command you invoke.
  install -Dm755 bin/c7shell-bootstrap "$pkgdir/usr/bin/c7shell-bootstrap"
  # The only way an installed c7shell gets a newer version: pacman has no
  # repository to upgrade a locally built package from.
  install -Dm755 bin/c7shell-upgrade "$pkgdir/usr/bin/c7shell-upgrade"
  install -Dm644 share/c7shell.desktop \
    "$pkgdir/usr/share/wayland-sessions/c7shell.desktop"

  # The settings window is a launchable app, so its entry and icon go where
  # every launcher already looks. They also travel inside the shipped config
  # above (the shell reads its own Assets), but a copy under ~/.config is not
  # on any launcher's search path -- these two lines are what make the app
  # appear in the launcher's "apps" tab, wofi, rofi and any app grid.
  install -Dm644 quickshell/c7shell/Assets/applications/c7shell-settings.desktop \
    "$pkgdir/usr/share/applications/c7shell-settings.desktop"
  install -Dm644 quickshell/c7shell/Assets/applications/c7shell-settings.svg \
    "$pkgdir/usr/share/icons/hicolor/scalable/apps/c7shell-settings.svg"
  install -Dm644 README.md "$pkgdir/usr/share/doc/$pkgname/README.md"
  # MIT is not one of the licences pacman ships in /usr/share/licenses/common,
  # so the text has to travel with the package.
  install -Dm644 LICENSE "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
}
