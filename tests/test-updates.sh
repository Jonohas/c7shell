#!/usr/bin/env bash
# Self-check for the update flow's QML. Run it directly: tests/test-updates.sh
#
# Same trick as tests/test-osd.sh: quickshell's QML plugin is statically linked
# into the quickshell binary, so the handful of Quickshell types these files
# touch are shimmed with plain Items here and everything under test -- the
# version-delta arithmetic, the size and duration formatting, the verdict
# properties -- is real. No compositor, no package manager, no root.
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
         "$tmp/Quickshell" "$tmp/Quickshell/Io"

cp "$src/Common/VersionDelta.qml" "$tmp/qs/Common/"
printf 'module qs.Common\nVersionDelta 1.0 VersionDelta.qml\n' > "$tmp/qs/Common/qmldir"

cp "$src/Services/UpdatesService.qml" "$tmp/qs/Services/"
# Terminal is a singleton UpdatesService calls into for the three things that
# belong in a terminal (merge, view diff, view log). None of them are under
# test; a stub keeps the import resolvable.
printf 'pragma Singleton\nimport QtQuick\nQtObject { function run(argv) {} }\n' \
  > "$tmp/qs/Services/Terminal.qml"
printf 'module qs.Services\nsingleton UpdatesService 1.0 UpdatesService.qml\nsingleton Terminal 1.0 Terminal.qml\n' \
  > "$tmp/qs/Services/qmldir"

# Only the tokens VersionDelta reads. The real Theme pulls in AppearanceStore,
# which pulls in FileView, which needs quickshell proper.
cat > "$tmp/qs/Theme/Theme.qml" <<'EOF'
pragma Singleton
import QtQuick
QtObject {
  readonly property string fontMono: "monospace"
  readonly property color text: "#f0eff1"
  readonly property color accentSoft: "#e5717a"
  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
}
EOF
printf 'module qs.Theme\nsingleton Theme 1.0 Theme.qml\n' > "$tmp/qs/Theme/qmldir"

# The Quickshell types UpdatesService names. Process is the only one with any
# surface: the service assigns `command`, flips `running` and calls exec() and
# signal(), and none of those may throw while the pure logic is under test.
printf 'import QtQuick\nItem {}\n' > "$tmp/Quickshell/Singleton.qml"
printf 'module Quickshell\nSingleton 1.0 Singleton.qml\n' > "$tmp/Quickshell/qmldir"
cat > "$tmp/Quickshell/Io/Process.qml" <<'EOF'
import QtQuick
Item {
  property var command: []
  property bool running: false
  property var stdout: null
  property var stderr: null
  signal exited(int code, int status)
  function exec(argv) {}
  function signal(sig) {}
}
EOF
printf 'import QtQuick\nItem { property string text: ""\n  signal streamFinished() }\n' \
  > "$tmp/Quickshell/Io/StdioCollector.qml"
printf 'import QtQuick\nItem { property string splitMarker: "\\n"\n  signal read(string data) }\n' \
  > "$tmp/Quickshell/Io/SplitParser.qml"
printf 'module Quickshell.Io\nProcess 1.0 Process.qml\nStdioCollector 1.0 StdioCollector.qml\nSplitParser 1.0 SplitParser.qml\n' \
  > "$tmp/Quickshell/Io/qmldir"

log=$tmp/updates.log
# QT_FORCE_STDERR_LOGGING: without a tty Qt sends its messages to journald,
# where this test cannot see them.
QT_QPA_PLATFORM=offscreen \
QT_FORCE_STDERR_LOGGING=1 \
timeout 30 qml6 -I "$tmp" "$here/updates-qml-test.qml" >"$log" 2>&1 \
  || fail "qml6 exited non-zero:\n$(cat "$log")"

grep -q 'UPDATES-TEST-PASS' "$log" || fail "the test never reached its end:\n$(cat "$log")"
# Any line naming a .qml file is a warning, an error or a type failure.
if grep -q '\.qml:' "$log"; then
  fail "QML diagnostics:\n$(grep '\.qml:' "$log")"
fi

echo 'test-updates.sh: all checks passed'
