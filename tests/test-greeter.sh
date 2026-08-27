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
for f in metadata.desktop theme.conf Main.qml Greeter.qml qmldir Theme.qml; do
  [[ -f $theme/$f ]] || fail "sddm/themes/c7shell/$f is missing"
done
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

render resting
render failed --failed
render sessions --sessions
render caps --caps
render manual --manual
render single --one-user
render hd --size 1920x1080
render small --size 1366x768
render wide --size 3440x1440

echo 'PASS: sddm greeter theme'
