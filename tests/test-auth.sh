#!/usr/bin/env bash
# Self-check for the password prompt's QML. Run it directly: tests/test-auth.sh
#
# Same trick as tests/test-updates.sh: quickshell's QML plugin is statically
# linked into the quickshell binary, so the few Quickshell types these files
# touch are shimmed and everything actually under test is the real file --
# AuthService's event machine, SecretField, AuthPrompt's per-state labels.
#
# The window itself (Modules/Auth/AuthWindow.qml) is not here: PanelWindow and
# WlrLayershell need a compositor. What it contributes -- the keyboard grab and
# the backdrop -- is not logic that can be silently wrong.
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

mkdir -p "$tmp/qs/Common" "$tmp/qs/Services" "$tmp/qs/Theme" \
         "$tmp/qs/Modules/Auth" "$tmp/Quickshell" "$tmp/Quickshell/Io"

# The real components, not stand-ins.
parts=(SecretField Icon GlassPanel Spinner)
printf 'module qs.Common\n' > "$tmp/qs/Common/qmldir"
for f in "${parts[@]}"; do
  cp "$src/Common/$f.qml" "$tmp/qs/Common/"
  printf '%s 1.0 %s.qml\n' "$f" "$f" >> "$tmp/qs/Common/qmldir"
done

cp "$src/Services/AuthService.qml" "$tmp/qs/Services/"
printf 'module qs.Services\nsingleton AuthService 1.0 AuthService.qml\n' > "$tmp/qs/Services/qmldir"

cp "$src/Modules/Auth/AuthPrompt.qml" "$src/Modules/Auth/PromptButton.qml" "$tmp/qs/Modules/Auth/"
printf 'module qs.Modules.Auth\nAuthPrompt 1.0 AuthPrompt.qml\nPromptButton 1.0 PromptButton.qml\n' \
  > "$tmp/qs/Modules/Auth/qmldir"

# Only the tokens these files read. The real Theme pulls in AppearanceStore,
# which pulls in FileView, which needs quickshell proper. iconsDir points at
# the real icons, so an icon this design names but nobody drew is a visible
# warning here rather than a blank tile on someone's screen.
cat > "$tmp/qs/Theme/Theme.qml" <<THEME
pragma Singleton
import QtQuick
QtObject {
  readonly property string fontMono: "monospace"
  readonly property color text: "#f0eff1"
  readonly property color text2: Qt.rgba(1, 1, 1, 0.55)
  readonly property color text3: Qt.rgba(1, 1, 1, 0.40)
  readonly property color textOnAccent: "#ffffff"
  readonly property color accent: "#e53a44"
  readonly property color accentSoft: "#e5717a"
  readonly property color accentFill: Qt.rgba(0.9, 0.23, 0.27, 0.14)
  readonly property color surface04: Qt.rgba(1, 1, 1, 0.04)
  readonly property color surface05: Qt.rgba(1, 1, 1, 0.05)
  readonly property color surface07: Qt.rgba(1, 1, 1, 0.07)
  readonly property color hairline: Qt.rgba(1, 1, 1, 0.08)
  readonly property color hairlineStrong: Qt.rgba(1, 1, 1, 0.10)
  readonly property color hoverPill: Qt.rgba(1, 1, 1, 0.09)
  readonly property color glassBase: "#0f0f13"
  readonly property real glassAlphaPanel: 0.80
  readonly property int radiusPanel: 18
  readonly property url iconsDir: "file://$src/Assets/icons"
  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
}
THEME
printf 'module qs.Theme\nsingleton Theme 1.0 Theme.qml\n' > "$tmp/qs/Theme/qmldir"

# The Quickshell types AuthService names. Process is the one with any surface:
# the service flips `running` and calls write(), and the test reads back what
# was written to prove which command reached the daemon.
printf 'import QtQuick\nItem {}\n' > "$tmp/Quickshell/Singleton.qml"
printf 'module Quickshell\nSingleton 1.0 Singleton.qml\n' > "$tmp/Quickshell/qmldir"
cat > "$tmp/Quickshell/Io/Process.qml" <<'PROC'
import QtQuick
Item {
  property var command: []
  property bool running: false
  property bool stdinEnabled: false
  property var stdout: null
  property var stderr: null
  property var written: []
  signal exited(int code, int status)
  function write(data) { written = written.concat([data]) }
  function exec(argv) {}
  function signal(sig) {}
}
PROC
printf 'import QtQuick\nItem { property string text: ""\n  signal streamFinished() }\n' \
  > "$tmp/Quickshell/Io/StdioCollector.qml"
printf 'import QtQuick\nItem { property string splitMarker: "\\n"\n  signal read(string data) }\n' \
  > "$tmp/Quickshell/Io/SplitParser.qml"
printf 'module Quickshell.Io\nProcess 1.0 Process.qml\nStdioCollector 1.0 StdioCollector.qml\nSplitParser 1.0 SplitParser.qml\n' \
  > "$tmp/Quickshell/Io/qmldir"

log=$tmp/auth.log
# QT_FORCE_STDERR_LOGGING: without a tty Qt sends its messages to journald,
# where this test cannot see them.
QT_QPA_PLATFORM=offscreen \
QT_FORCE_STDERR_LOGGING=1 \
timeout 30 qml6 -I "$tmp" "$here/auth-qml-test.qml" >"$log" 2>&1 \
  || fail "qml6 exited non-zero:\n$(cat "$log")"

grep -q 'AUTH-TEST-PASS' "$log" || fail "the test never reached its end:\n$(cat "$log")"
# The service warns on purpose when it did not win the polkit registration, and
# the stub daemon here never claims one -- that line is the expected output of
# a behaviour under test, not a diagnostic.
if grep '\.qml:' "$log" | grep -qv 'another polkit agent'; then
  fail "QML diagnostics:\n$(grep '\.qml:' "$log" | grep -v 'another polkit agent')"
fi

echo 'test-auth.sh: all checks passed'
