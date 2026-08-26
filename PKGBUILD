# Maintainer: Jonohas <https://github.com/Jonohas>
pkgname=gambleland
pkgver=0.1.0
pkgrel=1
pkgdesc='GambleLand desktop environment: Hyprland (lua config) with the gambleland Quickshell shell'
arch=('any')
url='https://github.com/Jonohas/GambleLand'
license=('custom')
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
  'jq: helper scripting'
)
makedepends=('git')
source=("$pkgname::git+$url.git#branch=main")
sha256sums=('SKIP')
install="$pkgname.install"

pkgver() {
  cd "$srcdir/$pkgname"
  printf '0.1.0.r%s.g%s' "$(git rev-list --count HEAD)" "$(git rev-parse --short HEAD)"
}

package() {
  cd "$srcdir/$pkgname"

  # The configs are shipped read-only under /usr/share and copied into the
  # user's ~/.config by gambleland-setup: hyprland and quickshell both read
  # their config only from $XDG_CONFIG_HOME, and the user is expected to edit
  # what lands there.
  install -dm755 "$pkgdir/usr/share/$pkgname"
  cp -a hypr quickshell "$pkgdir/usr/share/$pkgname/"
  # Dev-facing only, and setup copies whatever is here into the user's config.
  rm -rf "$pkgdir/usr/share/$pkgname/quickshell/docs"
  chmod -R u=rwX,go=rX "$pkgdir/usr/share/$pkgname"
  chmod 755 "$pkgdir/usr/share/$pkgname/quickshell/scripts/gambleland-appmenud.py"

  install -Dm755 bin/gambleland-setup "$pkgdir/usr/bin/gambleland-setup"
  install -Dm644 share/gambleland.desktop \
    "$pkgdir/usr/share/wayland-sessions/gambleland.desktop"
  install -Dm644 README.md "$pkgdir/usr/share/doc/$pkgname/README.md"
}
