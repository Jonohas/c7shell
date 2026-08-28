#!/usr/bin/env bash
# Self-check for the OSD manager singleton. Run it directly: tests/test-osd.sh
#
# OsdManager.qml only imports Quickshell and QtQuick, so it runs under plain
# qml6 offscreen -- no compositor needed. Quickshell's QML plugin is statically
# linked into the quickshell binary, so its `Singleton` type is shimmed with a
# plain Item here; every property, function and Timer under test is real. The
# singleton is registered through a generated qmldir because `pragma Singleton`
# files cannot be instantiated directly.
set -euo pipefail

here=$(cd -- "$(dirname -- "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT

fail() { printf 'FAIL: %b\n' "$1" >&2; exit 1; }

command -v qml6 >/dev/null || {
  echo 'SKIP: qml6 not installed (package: qt6-declarative)'
  exit 0
}

mkdir -p "$tmp/osdtest" "$tmp/Quickshell"
cp "$here/../quickshell/c7shell/Services/OsdManager.qml" "$tmp/osdtest/"
printf 'module osdtest\nsingleton OsdManager 1.0 OsdManager.qml\n' > "$tmp/osdtest/qmldir"
printf 'module Quickshell\nSingleton 1.0 Singleton.qml\n' > "$tmp/Quickshell/qmldir"
printf 'import QtQuick\nItem {}\n' > "$tmp/Quickshell/Singleton.qml"

log=$tmp/osd.log
# QT_FORCE_STDERR_LOGGING: without a tty Qt sends its messages to journald,
# where this test cannot see them.
QT_QPA_PLATFORM=offscreen \
QT_FORCE_STDERR_LOGGING=1 \
timeout 30 qml6 -I "$tmp" "$here/osd-manager-test.qml" >"$log" 2>&1 \
  || fail "qml6 exited non-zero:\n$(cat "$log")"

grep -q 'OSD-TEST-PASS' "$log" || fail "the test never reached its end:\n$(cat "$log")"
# Any line naming a .qml file is a warning, an error or a type failure.
if grep -q '\.qml:' "$log" ; then
  fail "QML diagnostics:\n$(grep '\.qml:' "$log")"
fi

printf 'PASS: OSD manager\n'
