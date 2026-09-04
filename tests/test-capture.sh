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

# --- the crop, which is a program and can just be run ---------------------
# The delayed shutter fires before the rectangle exists, so the region is cut
# out of the captured frame afterwards. A crop that is off by a scale factor is
# not an error -- it is a screenshot of the wrong part of the screen.
cropper=$src/scripts/c7shell-crop.py
[[ -x $cropper ]] || fail "scripts/c7shell-crop.py is missing or not executable.
CaptureService resolves it relative to itself and shells out to it; a missing
file there is a delayed capture that gets as far as the still and then loses it."

if python3 -c 'import gi; gi.require_version("GdkPixbuf", "2.0"); from gi.repository import GdkPixbuf' 2>/dev/null; then
  python3 - "$tmp" <<'MAKE'
import sys
import gi
gi.require_version("GdkPixbuf", "2.0")
from gi.repository import GdkPixbuf, GLib
# 100x80, and every pixel encodes its own coordinates so a crop taken from the
# wrong offset cannot come out looking plausible.
w, h = 100, 80
data = bytearray()
for y in range(h):
    for x in range(w):
        data += bytes((x * 2, y * 3, 0))
GdkPixbuf.Pixbuf.new_from_bytes(GLib.Bytes.new(bytes(data)),
                                GdkPixbuf.Colorspace.RGB, False, 8, w, h, w * 3) \
    .savev(f"{sys.argv[1]}/src.png", "png", [], [])
MAKE

  python3 "$cropper" "$tmp/src.png" "$tmp/out.png" 10 20 30 25 \
    || fail "the cropper exited non-zero on a valid rectangle"

  read -r gw gh gx gy < <(python3 - "$tmp/out.png" <<'READ'
import sys
import gi
gi.require_version("GdkPixbuf", "2.0")
from gi.repository import GdkPixbuf
p = GdkPixbuf.Pixbuf.new_from_file(sys.argv[1])
px = p.get_pixels()
# The top-left pixel says which source pixel it came from.
print(p.get_width(), p.get_height(), px[0] // 2, px[1] // 3)
READ
)
  [[ $gw == 30 && $gh == 25 ]] || fail "cropping 30x25 produced ${gw}x${gh}"
  [[ $gx == 10 && $gy == 20 ]] || fail "the crop starts at ${gx},${gy}, not the 10,20 it was asked for"

  # A selection flush against the edge of a fractionally scaled output rounds a
  # pixel past the frame. That is a rounding question, not a reason to lose the
  # screenshot -- so it clamps rather than failing.
  python3 "$cropper" "$tmp/src.png" "$tmp/edge.png" 90 70 30 25 \
    || fail "a rectangle overhanging the frame was rejected instead of clamped"

  # Real failures still have to be loud: the service reports the stderr.
  python3 "$cropper" "$tmp/nope.png" "$tmp/x.png" 0 0 10 10 2>/dev/null \
    && fail "the cropper exited zero on a source file that does not exist"
  python3 "$cropper" "$tmp/src.png" "$tmp/x.png" 0 0 10 2>/dev/null \
    && fail "the cropper exited zero on the wrong number of arguments"
else
  echo 'SKIP: the crop checks (no GdkPixbuf typelib -- package: gdk-pixbuf2)'
fi

# --------------------------------------------------------------------------
# Closing the overlay on a still nobody cut has to throw the frame away. It is
# a full screenshot of the desktop in the runtime dir, and the next delayed
# capture would draw a stale one under the new selection.
# --------------------------------------------------------------------------
sed -n '/onVisibleChanged/,/^  }/p' "$src/Modules/Capture/CaptureOverlay.qml" \
  | grep -q 'CaptureService.discardFrozen()' \
  || fail "CaptureOverlay's onVisibleChanged does not call CaptureService.discardFrozen().
esc on a frozen frame then leaves a screenshot of the whole desktop behind."

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
