#!/usr/bin/env bash
# Self-check for the screenshot delay. Run it directly: tests/test-capture.sh
#
# Same trick as tests/test-auth.sh: the Quickshell types CaptureService names
# are shimmed so qml6 can load it, and the service itself is the real file.
#
# The two surfaces are not here -- CaptureOverlay and CountdownPill are
# PanelWindows and need a compositor. What they contribute is checked
# statically at the bottom: the names they read off the service, and the one
# call that stops a countdown from firing into a reopened overlay.
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

mkdir -p "$tmp/qs/Services" "$tmp/Quickshell/Io"

cp "$src/Services/CaptureService.qml" "$tmp/qs/Services/"
# NotifServer is only reached by fail(), which nothing here trips, but naming a
# singleton that does not exist is a load error for the whole file.
printf 'pragma Singleton\nimport QtQuick\nQtObject { function send(a, b) {} }\n' \
  > "$tmp/qs/Services/NotifServer.qml"
printf 'module qs.Services\nsingleton CaptureService 1.0 CaptureService.qml\nsingleton NotifServer 1.0 NotifServer.qml\n' \
  > "$tmp/qs/Services/qmldir"

# env() for the screenshots directory, execDetached() for the mkdir -p the
# service runs on completion. Neither is under test; both are named at load.
cat > "$tmp/Quickshell/QuickshellGlobal.qml" <<'GLOBAL'
pragma Singleton
import QtQuick
QtObject {
  property var screens: []
  function env(name) { return "/nonexistent" }
  function execDetached(argv) {}
}
GLOBAL
printf 'import QtQuick\nItem {}\n' > "$tmp/Quickshell/Singleton.qml"
printf 'module Quickshell\nsingleton Quickshell 1.0 QuickshellGlobal.qml\nSingleton 1.0 Singleton.qml\n' \
  > "$tmp/Quickshell/qmldir"

cat > "$tmp/Quickshell/Io/Process.qml" <<'PROC'
import QtQuick
Item {
  property var command: []
  property bool running: false
  property var stderr: null
  signal exited(int code, int status)
  function exec(argv) {}
}
PROC
printf 'import QtQuick\nItem { property string text: "" }\n' \
  > "$tmp/Quickshell/Io/StdioCollector.qml"
printf 'import QtQuick\nItem { property string target: "" }\n' \
  > "$tmp/Quickshell/Io/IpcHandler.qml"
printf 'module Quickshell.Io\nProcess 1.0 Process.qml\nStdioCollector 1.0 StdioCollector.qml\nIpcHandler 1.0 IpcHandler.qml\n' \
  > "$tmp/Quickshell/Io/qmldir"

log=$tmp/capture.log
# QT_FORCE_STDERR_LOGGING: without a tty Qt sends its messages to journald,
# where this test cannot see them.
QT_QPA_PLATFORM=offscreen \
QT_FORCE_STDERR_LOGGING=1 \
timeout 60 qml6 -I "$tmp" "$here/capture-qml-test.qml" >"$log" 2>&1 \
  || fail "qml6 exited non-zero:\n$(cat "$log")"

grep -q 'CAPTURE-TEST-PASS' "$log" || fail "the test never reached its end:\n$(cat "$log")"
if grep -q '\.qml:' "$log"; then
  fail "QML diagnostics:\n$(grep '\.qml:' "$log")"
fi

# --- the two surfaces, which nothing above can instantiate ----------------
# Both are PanelWindows. Their risk is not the layer surface -- it is the names
# they read off CaptureService. A misspelt one is not a load failure:
# quickshell logs a binding warning and carries on, so the shell comes up
# looking right and the delay quietly loses exactly one piece.
svc=$src/Services/CaptureService.qml
for f in "$src/Modules/Capture/CaptureOverlay.qml" "$src/Modules/Capture/CountdownPill.qml"; do
  missing=()
  while read -r name; do
    grep -qE "^[[:space:]]*(readonly[[:space:]]+)?property[[:space:]]+[A-Za-z0-9_<>]+[[:space:]]+$name\b" "$svc" && continue
    grep -qE "^[[:space:]]*function[[:space:]]+$name\b" "$svc" && continue
    grep -qE "^[[:space:]]*signal[[:space:]]+$name\b" "$svc" && continue
    missing+=("$name")
  done < <(sed 's|//.*||' "$f" | grep -oE 'CaptureService\.[A-Za-z_][A-Za-z0-9_]*' \
           | sed 's/CaptureService\.//' | sort -u)

  if ((${#missing[@]})); then
    fail "$(basename "$f") reads these off CaptureService, which does not declare them:
  ${missing[*]}
A misspelt binding here is a warning, not an error -- the shell loads clean and
that piece of the delay silently goes missing."
  fi
done

# --------------------------------------------------------------------------
# The overlay must cancel a running countdown when it reopens. Stopping only
# its own shutter timer leaves the countdown to hand back a second later, and
# the capture is then taken with the new session's geometry -- silently, since
# that geometry is perfectly valid.
# --------------------------------------------------------------------------
overlay=$src/Modules/Capture/CaptureOverlay.qml
sed -n '/onVisibleChanged/,/^  }/p' "$overlay" | grep -q 'CaptureService.cancelCountdown()' \
  || fail "CaptureOverlay's onVisibleChanged does not call CaptureService.cancelCountdown().
A countdown left running across a reopen fires into the new session."

# CountdownPill has to be unmapped before grim reads the screen, exactly like
# the overlay -- it is a layer surface too. Zero on the count is what takes it
# down, so the shutter has to wait out the recomposite grace after that rather
# than firing from the tick.
grep -q 'onCountdownElapsed' "$overlay" \
  || fail "CaptureOverlay does not handle CaptureService.countdownElapsed, so nothing
takes the delayed screenshot when the count runs out."

echo 'test-capture.sh: all checks passed'
