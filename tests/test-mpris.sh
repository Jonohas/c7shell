#!/usr/bin/env bash
# Self-check for the MPRIS service singleton. Run it directly: tests/test-mpris.sh
#
# Same shape as test-osd.sh: MprisService.qml is plain QML over one Quickshell
# module, so it runs under qml6 offscreen with no compositor and no D-Bus.
# Quickshell's QML plugin is statically linked into the quickshell binary, so
# `Singleton` and the whole Quickshell.Services.Mpris module are shimmed here --
# every property, filter and function under test is the real file's.
#
# The stub is not a mock of MPRIS. It is the smallest thing MprisService reads:
# a `players` list whose members carry the properties it binds to. Which player
# the service picks out of that list is the entire point of the test.
set -euo pipefail

here=$(cd -- "$(dirname -- "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT

fail() { printf 'FAIL: %b\n' "$1" >&2; exit 1; }

command -v qml6 >/dev/null || {
  echo 'SKIP: qml6 not installed (package: qt6-declarative)'
  exit 0
}

mkdir -p "$tmp/mpristest" "$tmp/Quickshell" "$tmp/Quickshell/Services/Mpris"
cp "$here/../quickshell/c7shell/Services/MprisService.qml" "$tmp/mpristest/"
printf 'module mpristest\nsingleton MprisService 1.0 MprisService.qml\n' > "$tmp/mpristest/qmldir"

printf 'module Quickshell\nSingleton 1.0 Singleton.qml\n' > "$tmp/Quickshell/qmldir"
printf 'import QtQuick\nItem {}\n' > "$tmp/Quickshell/Singleton.qml"

# The service reads Mpris.players.values and nothing else off the module, so
# the stub is a settable list of whatever the test puts in it.
cat > "$tmp/Quickshell/Services/Mpris/qmldir" <<'QMLDIR'
module Quickshell.Services.Mpris
singleton Mpris 1.0 Mpris.qml
singleton MprisPlaybackState 1.0 MprisPlaybackState.qml
singleton MprisLoopState 1.0 MprisLoopState.qml
QMLDIR

cat > "$tmp/Quickshell/Services/Mpris/Mpris.qml" <<'QML'
pragma Singleton
import QtQuick
QtObject {
  readonly property QtObject players: QtObject { property var values: [] }
}
QML

# The two enums, in the order Quickshell's C++ declares them -- QML numbers an
# enum from zero in declaration order, so getting the order right here is what
# makes a service that compares against the wrong value fail in this test rather
# than at the desk. A property cannot be named `Playing` (QML forbids an
# upper-case property name), which is why these are enums and not constants.
cat > "$tmp/Quickshell/Services/Mpris/MprisPlaybackState.qml" <<'QML'
pragma Singleton
import QtQuick
QtObject { enum Enum { Stopped, Playing, Paused } }
QML

cat > "$tmp/Quickshell/Services/Mpris/MprisLoopState.qml" <<'QML'
pragma Singleton
import QtQuick
QtObject { enum Enum { None, Track, Playlist } }
QML

log=$tmp/mpris.log
# QT_FORCE_STDERR_LOGGING: without a tty Qt sends its messages to journald,
# where this test cannot see them.
QT_QPA_PLATFORM=offscreen \
QT_FORCE_STDERR_LOGGING=1 \
timeout 30 qml6 -I "$tmp" "$here/mpris-service-test.qml" >"$log" 2>&1 \
  || fail "qml6 exited non-zero:\n$(cat "$log")"

grep -q 'MPRIS-TEST-PASS' "$log" || fail "the test never reached its end:\n$(cat "$log")"
# Any line naming a .qml file is a warning, an error or a type failure. A
# binding loop or a "cannot assign" in the service is exactly the kind of thing
# that loads clean and misbehaves later, so none of them are tolerated.
if grep -q '\.qml:' "$log"; then
  fail "QML diagnostics:\n$(grep '\.qml:' "$log")"
fi

printf 'PASS: MPRIS service\n'
