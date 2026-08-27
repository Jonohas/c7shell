# Maintainer: Jonohas <https://github.com/Jonohas>
# The AUR name carries the -git suffix because source= tracks a branch and
# pkgver() counts commits. _name is the installed name: bin/c7shell-setup
# reads /usr/share/c7shell, so the payload paths must not follow pkgname.
pkgname=c7shell-git
_name=c7shell
pkgver=0.1.0
pkgrel=1
pkgdesc='c7shell desktop environment: Hyprland (lua config) with the c7shell Quickshell shell'
arch=('any')
provides=('c7shell')
conflicts=('c7shell')
url='https://github.com/Jonohas/c7shell'
# MIT is this repository; OFL-1.1 is the Space Grotesk font vendored below.
license=('MIT' 'OFL-1.1')
# Hyprland 0.56+ is required: the config is hyprland.lua, not hyprland.conf.
depends=(
  'hyprland>=0.56'
  'quickshell'
  'hypridle'
  'hyprlock'
  'hyprpaper'
  'hyprpolkitagent'
  'qt6-declarative'
  # Theme.qml and hyprlock.conf both name the mono face; without the font the
  # bar, launcher and lock screen silently fall back to default sans. Space
  # Grotesk, the display face, is in no repository and is vendored below.
  'ttf-jetbrains-mono'
  # conf/environment.lua sets QT_QPA_PLATFORMTHEME=kde: plasma-integration is
  # the platform theme that reads kdeglobals, which is what
  # scripts/c7shell-theme-export.py writes the accent and variant into. Breeze
  # is the widget style and icon set that scheme names.
  'plasma-integration'
  'breeze'
  'breeze-icons'
  # conf/environment.lua names Adwaita as XCURSOR_THEME and
  # c7shell-theme-export.py writes it into kcminputrc. It is only ever reached
  # implicitly otherwise -- default-cursors' index.theme inherits it -- so
  # depend on the theme itself rather than on that inheritance holding.
  'adwaita-cursors'
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
  # Services/UpdatesService.qml runs `checkupdates`, the bar's updates pill.
  'pacman-contrib'
  # Services/CaptureService.qml opens captures with xdg-open and deletes them
  # with `gio trash`.
  'xdg-utils'
  'glib2'
  # The settings app's .desktop and icon land in /usr/share/{applications,
  # icons/hicolor}; these two carry the pacman hooks that refresh both caches.
  'desktop-file-utils'
  'hicolor-icon-theme'
)
optdepends=(
  'kitty: terminal bound to SUPER+Q'
  'dolphin: file manager bound to SUPER+E'
  'hyprlauncher: fallback launcher (the shell provides its own)'
  'ddcutil: DDC/CI backlight control for external monitors'
  'brightnessctl: backlight control for internal panels'
  'upower: battery readout in the bar'
  'playerctl: media keys (XF86Audio{Next,Prev,Play,Pause})'
  'solaar: Logitech device support, autostarted if present'
  'kwallet: secrets service, started by conf/autostart.lua when installed'
  'kwallet-pam: unlocks that wallet with the login password'
  'paru: AUR count in the updates pill'
  'flatpak: flatpak count in the updates pill'
  'fprintd: fingerprint unlock (commented out in hypr/hyprlock.conf)'
  'jq: helper scripting'
)
# lua: tests/test-monitors.lua loads conf/monitors.lua against a stubbed hl.
makedepends=('git' 'lua')
# Space Grotesk (OFL-1.1) is vendored rather than depended on: it is the display
# face in Theme.qml and hyprlock.conf, and no Arch repository carries it, so
# without this the clock and headings fall back to default sans on every machine
# but the author's -- where it happens to be installed by hand.
_sgver=2.0.0
source=(
  "$_name::git+$url.git#branch=main"
  "space-grotesk-$_sgver.tar.gz::https://github.com/floriankarsten/space-grotesk/archive/refs/tags/$_sgver.tar.gz"
)
sha256sums=(
  'SKIP'
  '366da4ddec4f637f6d2d342251c2e5e8b8af67d10653f347a9d9d603cc64547a'
)
install="$_name.install"

pkgver() {
  cd "$srcdir/$_name"
  printf '0.1.0.r%s.g%s' "$(git rev-list --count HEAD)" "$(git rev-parse --short HEAD)"
}

check() {
  cd "$srcdir/$_name"
  tests/test-setup.sh
  # From hypr/, because monitors.lua resolves its own require("conf/...")
  # relative to the working directory.
  cd hypr && lua ../tests/test-monitors.lua
}

package() {
  cd "$srcdir/$_name"

  # The configs are shipped read-only under /usr/share and copied into the
  # user's ~/.config by c7shell-setup: hyprland and quickshell both read
  # their config only from $XDG_CONFIG_HOME, and the user is expected to edit
  # what lands there. The shell ships as the named quickshell config
  # `quickshell/c7shell`, so it lands in ~/.config/quickshell/c7shell and
  # leaves any other config in ~/.config/quickshell alone (`qs -c c7shell`).
  install -dm755 "$pkgdir/usr/share/$_name"
  cp -a hypr quickshell "$pkgdir/usr/share/$_name/"
  # Dev-facing only, and setup copies whatever is here into the user's config.
  rm -rf "$pkgdir/usr/share/$_name/quickshell/c7shell/docs"
  chmod -R u=rwX,go=rX "$pkgdir/usr/share/$_name"
  chmod 755 "$pkgdir/usr/share/$_name/quickshell/c7shell/scripts/c7shell-appmenud.py" \
            "$pkgdir/usr/share/$_name/quickshell/c7shell/scripts/c7shell-theme-export.py" \
            "$pkgdir/usr/share/$_name/quickshell/c7shell/bin/screenshare-picker.sh"

  install -Dm755 bin/c7shell-setup "$pkgdir/usr/bin/c7shell-setup"
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

  # Space Grotesk, statics only: Theme.qml asks for weights 400-600 by name and
  # the four static faces answer that the way every other Arch font package
  # does. Shipping the variable TTF alongside them leaves fontconfig choosing
  # between two families with the same name.
  local sg="$srcdir/space-grotesk-$_sgver"
  install -dm755 "$pkgdir/usr/share/fonts/$_name"
  install -m644 "$sg"/fonts/ttf/static/SpaceGrotesk-*.ttf \
    "$pkgdir/usr/share/fonts/$_name/"
  install -Dm644 "$sg/OFL.txt" \
    "$pkgdir/usr/share/licenses/$pkgname/OFL-1.1-space-grotesk.txt"

  install -Dm644 LICENSE "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
  install -Dm644 README.md "$pkgdir/usr/share/doc/$pkgname/README.md"
}
