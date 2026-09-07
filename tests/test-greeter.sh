#!/usr/bin/env bash
# Self-check for the sddm greeter theme. Run it directly: tests/test-greeter.sh
#
# A greeter is the one part of the desktop you cannot try without logging out,
# and sddm's own greeter binary swallows QML diagnostics -- a theme with a
# broken binding still comes up, just missing whatever the binding fed. So the
# theme keeps its models out of Main.qml (see sddm/themes/c7shell/Greeter.qml),
# tests/greeter-preview.qml feeds it mock ones, and this runs that offscreen in
# every state and fails on any QML warning at all.
set -euo pipefail

here=$(cd -- "$(dirname -- "$0")" && pwd)
theme=$here/../sddm/themes/c7shell
preview=$here/greeter-preview.qml
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

# --- the theme is a theme -------------------------------------------------
for f in metadata.desktop theme.conf Main.qml Greeter.qml qmldir Theme.qml PaletteStore.qml; do
  [[ -f $theme/$f ]] || fail "sddm/themes/c7shell/$f is missing"
done

# --- the palette is compiled, so it can go stale ---------------------------
# Theme.qml reads its colours from PaletteStore.qml, which is generated from
# quickshell/c7shell/palette.json. It has to be generated rather than read: the
# greeter is plain QtQuick with no FileView, and QML's XMLHttpRequest will not
# open a local file without QML_XHR_ALLOW_FILE_READ in the environment, which
# is not ours to set for a process sddm launches. The cost of compiling it in
# is that it can fall behind the palette, and a greeter wearing last year's
# crimson is exactly the drift this whole arrangement exists to prevent.
if command -v python3 >/dev/null; then
  "$here/../tools/gen-palette-qml.py" "$here/../quickshell/c7shell/palette.json" \
    "$tmp/PaletteStore.qml" || fail 'tools/gen-palette-qml.py failed'
  diff -u "$theme/PaletteStore.qml" "$tmp/PaletteStore.qml" > "$tmp/palette.diff" 2>&1 \
    || fail "sddm/themes/c7shell/PaletteStore.qml is behind
  quickshell/c7shell/palette.json. Regenerate it:

    tools/gen-palette-qml.py quickshell/c7shell/palette.json sddm/themes/c7shell/PaletteStore.qml

$(cat "$tmp/palette.diff")"
fi
grep -q '^MainScript=Main.qml' "$theme/metadata.desktop" \
  || fail 'metadata.desktop does not name Main.qml as MainScript'
grep -q '^Theme-Id=c7shell' "$theme/metadata.desktop" \
  || fail 'metadata.desktop Theme-Id must match the directory name'
grep -q '^ConfigFile=theme.conf' "$theme/metadata.desktop" \
  || fail 'metadata.desktop does not name theme.conf'

# The one that costs a black screen at boot when it is wrong. sddm builds the
# greeter path as /usr/bin/sddm-greeter + (QtVersion ? "-qt<n>" : ""), so a
# theme that does not declare 6 is handed to the *Qt5* greeter -- which Arch
# ships, but whose Qt5 libraries are only an optdepend of sddm: it exits 127 and
# the login screen is a black rectangle. This theme is Qt6 QML (versionless
# imports, required properties, QtQuick.Effects), so it has to say so.
grep -q '^QtVersion=6' "$theme/metadata.desktop" \
  || fail 'metadata.desktop does not declare QtVersion=6, so sddm would launch the Qt5 greeter'

# Comments are deliberately absent from that file: Qt parses it with QSettings'
# INI reader, which does not treat every comment marker the way a .desktop file
# would, and a mis-parsed metadata line is exactly what a black screen looks
# like. Explanations belong here instead.
grep -q '^[[:space:]]*[#;]' "$theme/metadata.desktop" \
  && fail 'metadata.desktop has a comment line; keep it to bare keys (see above)'

# Every key Main.qml reads has to exist in theme.conf: config.stringValue() on
# a key that is in neither theme.conf nor sddm.conf returns an empty string,
# and the default silently becomes whatever the fallback happens to be.
while read -r key; do
  grep -q "^$key=" "$theme/theme.conf" || fail "Main.qml reads config key '$key', theme.conf does not define it"
done < <(grep -o 'stringValue("[a-zA-Z]*")' "$theme/Main.qml" | sed 's/.*("\(.*\)")/\1/' | sort -u)

# --- the network dispatcher ------------------------------------------------
# The greeter cannot ask NetworkManager anything (QML, no D-Bus, running as the
# sddm user), so this script publishes the connection to a file it can read.
# Exercised for real: it is a few lines of bash, and every one of them decides
# whether the pill appears or lies.
dispatcher=$here/../share/c7shell-network-dispatcher
[[ -x $dispatcher ]] || fail 'share/c7shell-network-dispatcher is missing or not executable'
bash -n "$dispatcher" || fail 'the dispatcher script does not parse'

export C7SHELL_NETWORK_FILE=$tmp/network
field() { grep "^$1=" "$C7SHELL_NETWORK_FILE" | cut -d= -f2-; }

# A wireless interface really present on the machine running the test, so the
# /sys probe for wireless-vs-wired is exercised rather than mocked. Falls back
# to asserting only what does not depend on one.
wifi_iface=''
for i in /sys/class/net/*; do [[ -d $i/wireless ]] && wifi_iface=${i##*/}; done

CONNECTION_ID='c7-office' "$dispatcher" "${wifi_iface:-eth0}" up
[[ -f $C7SHELL_NETWORK_FILE ]] || fail 'the dispatcher wrote nothing on "up"'
[[ $(field name) == c7-office ]] || fail "the connection name is '$(field name)', not c7-office"
[[ $(field state) == up ]] || fail "state is '$(field state)', not up"
if [[ -n $wifi_iface ]]; then
  [[ $(field kind) == wireless ]] || fail "a wireless interface was reported as '$(field kind)'"
fi
# World-readable, or the sddm user cannot read it and the pill never appears.
perms=$(stat -c '%a' "$C7SHELL_NETWORK_FILE")
[[ $perms == 644 ]] || fail "the published file is mode $perms, and the greeter runs as another user"

# "down" must not leave a stale network named in the greeter
CONNECTION_ID='c7-office' "$dispatcher" "${wifi_iface:-eth0}" down
[[ $(field state) == down ]] || fail 'a disconnect did not update the file'

# Loopback and virtual interfaces are not networks anyone is "on"
printf 'state=up\nkind=wireless\niface=x\nname=sentinel\n' > "$C7SHELL_NETWORK_FILE"
CONNECTION_ID='lo' "$dispatcher" lo up
[[ $(field name) == sentinel ]] || fail 'the dispatcher published loopback as a network'
CONNECTION_ID='docker' "$dispatcher" docker0 up
[[ $(field name) == sentinel ]] || fail 'the dispatcher published a docker bridge as a network'
# ...and neither are the phases that say nothing new about a settled connection
CONNECTION_ID='other' "$dispatcher" "${wifi_iface:-eth0}" pre-up
[[ $(field name) == sentinel ]] || fail 'the dispatcher acted on pre-up'
unset C7SHELL_NETWORK_FILE

command -v qml6 >/dev/null || {
  echo 'SKIP: qml6 not installed (package: qt6-declarative), only the metadata was checked'
  exit 0
}

# --- render every state, offscreen, and fail on any diagnostic ------------
# QT_FORCE_STDERR_LOGGING: without a tty Qt sends its messages to journald,
# where this test cannot see them -- which is exactly how a broken binding goes
# unnoticed in the first place.
# QML_XHR_ALLOW_FILE_READ: the greeter reads /proc/version and the battery
# through XMLHttpRequest, and the sddm.conf.d drop-in sets the same variable.
render() {
  local name=$1; shift
  local log=$tmp/$name.log
  QT_QPA_PLATFORM=offscreen \
  QT_FORCE_STDERR_LOGGING=1 \
  QML_XHR_ALLOW_FILE_READ=1 \
  timeout 60 qml6 "$preview" -- --exit-after 900 --shot "$tmp/$name.png" "$@" >"$log" 2>&1 \
    || fail "$name: qml6 exited non-zero:\n$(cat "$log")"
  # Any line naming a .qml file is a warning, an error or a type failure.
  if grep -q '\.qml:' "$log"; then
    fail "$name: QML diagnostics:\n$(grep '\.qml:' "$log")"
  fi
  [[ -s $tmp/$name.png ]] || fail "$name: nothing was rendered"
}

# The network file the dispatcher above would have written, so the pill has
# something to draw, and a password with characters in it, so the dot row and
# the caret are rendered rather than assumed.
printf 'state=up\nkind=wireless\niface=wlan0\nname=c7-office\n' > "$tmp/network"
printf 'state=up\nkind=wired\niface=enp0s1\nname=Wired connection 1\n' > "$tmp/network-wired"

render resting
render typed --typed 7
render network --network-file "$tmp/network"
render network-wired --network-file "$tmp/network-wired"
render failed --failed
render sessions --sessions
render caps --caps
render manual --manual
render single --one-user
render hd --size 1920x1080
render small --size 1366x768
render wide --size 3440x1440

echo 'PASS: sddm greeter theme'
