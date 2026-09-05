#!/usr/bin/env bash
# Self-check for the wifi scan list. Run it directly: tests/test-wifi.sh
#
# Same trick as tests/test-toasts.sh: NetworkService's list logic is plain JS
# over properties, so the Quickshell types around it are shimmed and the rule
# under test -- when the SSID list a Repeater is handed is republished, and
# when it must not be -- is real. No compositor and no NetworkManager.
#
# What it defends: a republish rebuilds every row, and a row owns the password
# field grown underneath it. Republishing on the signal-strength updates that
# arrive continuously while scanning threw away passwords mid-typing (#124).
set -euo pipefail

here=$(cd -- "$(dirname -- "$0")" && pwd)
src=$here/../quickshell/c7shell
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT

fail() { printf 'FAIL: %b\n' "$1" >&2; exit 1; }

command -v qml6 >/dev/null || {
  echo 'SKIP: qml6 not installed (package: qt6-declarative)'
  exit 0
}

mkdir -p "$tmp/qs/Services" "$tmp/qs/Common" "$tmp/qs/Theme" \
  "$tmp/Quickshell/Io" "$tmp/Quickshell/Networking"

cp "$src/Services/NetworkService.qml" "$tmp/qs/Services/"
printf 'module qs.Services\nsingleton NetworkService 1.0 NetworkService.qml\n' \
  > "$tmp/qs/Services/qmldir"

# The field is under test too: it owns both ends of the freeze, and a leak
# either way is invisible until someone cannot see a network appear again.
cp "$src/Common/PskField.qml" "$tmp/qs/Common/"
printf 'module qs.Common\nPskField 1.0 PskField.qml\n' > "$tmp/qs/Common/qmldir"

# The Theme stand-in, from tests/fixtures/theme-stub.sh -- one copy, with its
# colours read from the same palette.json the real Theme reads.
# shellcheck source=fixtures/theme-stub.sh
. "$here/fixtures/theme-stub.sh"
write_theme_stub "$tmp/qs" "$src"

# -- the Quickshell types NetworkService names -------------------------------
# A default property, because the service parents a Binding and two Timers to
# itself. Not Item, which would bring an `enabled` the service also declares.
cat > "$tmp/Quickshell/Singleton.qml" <<'QML'
import QtQuick
QtObject {
  default property list<QtObject> children
}
QML
printf 'module Quickshell\nSingleton 1.0 Singleton.qml\n' > "$tmp/Quickshell/qmldir"

# The IPv4 probe. Never started here -- the timer that runs it is gated on
# wantScan, which this test leaves false -- so exec() only has to exist.
cat > "$tmp/Quickshell/Io/Process.qml" <<'QML'
import QtQuick
Item {
  property bool running: false
  property var stdout: null
  signal exited(int code, int status)
  function exec(argv) {}
}
QML
cat > "$tmp/Quickshell/Io/StdioCollector.qml" <<'QML'
import QtQuick
Item {
  property string text: ""
  signal streamFinished
}
QML
printf 'module Quickshell.Io\nProcess 1.0 Process.qml\nStdioCollector 1.0 StdioCollector.qml\n' \
  > "$tmp/Quickshell/Io/qmldir"

# Networking.devices is what the test drives: it writes deviceList and the
# service's own bindings do the rest, exactly as they do against the real
# NetworkManager.
cat > "$tmp/Quickshell/Networking/Networking.qml" <<'QML'
pragma Singleton
import QtQuick
QtObject {
  id: root
  property var deviceList: []
  readonly property var devices: ({ values: root.deviceList })
  property bool wifiEnabled: true
  property bool wifiHardwareEnabled: true
}
QML
# The three enums are JS resources rather than singleton QtObjects, because a
# QML property name cannot begin with an upper case letter and every one of
# these members does.
cat > "$tmp/Quickshell/Networking/DeviceType.js" <<'JS'
.pragma library
var Wifi = 1
var Wired = 2
JS
cat > "$tmp/Quickshell/Networking/WifiSecurityType.js" <<'JS'
.pragma library
var Unknown = 0
var Open = 1
var StaticWep = 2
var DynamicWep = 3
var Leap = 4
var Owe = 5
var WpaPsk = 6
var WpaEap = 7
var Wpa2Psk = 8
var Wpa2Eap = 9
var Sae = 10
var Wpa3SuiteB192 = 11
JS
cat > "$tmp/Quickshell/Networking/ConnectionFailReason.js" <<'JS'
.pragma library
var NoSecrets = 1
JS
{
  printf 'module Quickshell.Networking\n'
  printf 'singleton Networking 1.0 Networking.qml\n'
  for f in DeviceType WifiSecurityType ConnectionFailReason; do
    printf '%s 1.0 %s.js\n' "$f" "$f"
  done
} > "$tmp/Quickshell/Networking/qmldir"

log=$tmp/wifi.log
# QT_FORCE_STDERR_LOGGING: without a tty Qt sends its messages to journald,
# where this test cannot see them.
QT_QPA_PLATFORM=offscreen \
QT_FORCE_STDERR_LOGGING=1 \
timeout 30 qml6 -I "$tmp" "$here/wifi-qml-test.qml" >"$log" 2>&1 \
  || fail "qml6 exited non-zero:\n$(cat "$log")"

# Both, in this order: a failed check names itself, and only a run that got
# all the way to the end may call itself a pass.
if grep -q 'WIFI-TEST-FAIL' "$log"; then
  fail "$(grep 'WIFI-TEST-FAIL' "$log")"
fi
grep -q 'WIFI-TEST-PASS' "$log" || fail "the test never reached its end:\n$(cat "$log")"
# Any line naming a .qml file is a warning, an error or a type failure.
if grep -q '\.qml:' "$log"; then
  fail "QML diagnostics:\n$(grep '\.qml:' "$log")"
fi

echo 'test-wifi.sh: all checks passed'
