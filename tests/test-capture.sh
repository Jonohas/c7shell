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

mkdir -p "$tmp/qs/Services" "$tmp/qs/Theme" "$tmp/Quickshell/Io"

# RedactionLayer is an Item, not a layer surface, so unlike the two windows it
# can be instantiated here -- and its snapping rule is one half of a pair, the
# other half being snap_rect() in the cropper. Copied next to the test so the
# same-directory resolution the shell uses applies here too.
cp "$src/Modules/Capture/RedactionLayer.qml" "$tmp/"
cp "$here/capture-qml-test.qml" "$tmp/"

# Only the two tokens the mosaic's outline is drawn with; nothing here looks at
# a colour.
cat > "$tmp/qs/Theme/Theme.qml" <<'THEME'
pragma Singleton
import QtQuick
QtObject {
  property color accent: "#ffffff"
  function alpha(c, a) { return c }
}
THEME
printf 'module qs.Theme\nsingleton Theme 1.0 Theme.qml\n' > "$tmp/qs/Theme/qmldir"

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
timeout 60 qml6 -I "$tmp" "$tmp/capture-qml-test.qml" >"$log" 2>&1 \
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

  # --- pixelate -----------------------------------------------------------
  # A redaction that is only in the preview is worse than no redaction at all:
  # you looked at the mosaic, agreed the private thing was covered, and saved a
  # file with it still legible. So the flags have to actually burn into the PNG.
  python3 "$cropper" "$tmp/src.png" "$tmp/redacted.png" 0 0 100 80 \
    --block 10 --pixelate 20,20,40,40 \
    || fail "the cropper exited non-zero on a valid --pixelate rectangle"

  read -r flat inside outside < <(python3 - "$tmp/redacted.png" <<'READ'
import sys
import gi
gi.require_version("GdkPixbuf", "2.0")
from gi.repository import GdkPixbuf
p = GdkPixbuf.Pixbuf.new_from_file(sys.argv[1])
px, rs, nc = p.get_pixels(), p.get_rowstride(), p.get_n_channels()
def at(x, y):
    o = y * rs + x * nc
    return tuple(px[o:o + 3])
# One block is flat, the source gradient it replaced was not, and a pixel
# outside the rectangle still says which source pixel it came from.
print(int(at(20, 20) == at(29, 29) == at(24, 26)),
      int(at(20, 20) != at(30, 20)),
      int(at(5, 5) == (10, 15, 0)))
READ
)
  [[ $flat == 1 ]] || fail "--pixelate left the block it covered ungridded; the mosaic is not in the file"
  [[ $inside == 1 ]] || fail "every block came out identical -- that is a fill, not a pixelation"
  [[ $outside == 1 ]] || fail "--pixelate changed pixels outside the rectangle it was given"

  # Rectangles are grown out to whole blocks, so half a glyph cannot survive
  # along an edge -- and the overlay's preview snaps the same way, or the file
  # would not be what was agreed to on screen.
  read -r grown < <(python3 - "$tmp/tail.png" "$cropper" "$tmp/src.png" <<'READ'
import subprocess
import sys
import gi
gi.require_version("GdkPixbuf", "2.0")
from gi.repository import GdkPixbuf
out, cropper, src = sys.argv[1], sys.argv[2], sys.argv[3]
# 25,25 30x30 with a block of 10 covers 20,20 through 60,60 once grown.
subprocess.run(["python3", cropper, src, out, "0", "0", "100", "80",
                "--block", "10", "--pixelate", "25,25,30,30"], check=True)
p = GdkPixbuf.Pixbuf.new_from_file(out)
px, rs, nc = p.get_pixels(), p.get_rowstride(), p.get_n_channels()
def at(x, y):
    o = y * rs + x * nc
    return tuple(px[o:o + 3])
print(int(at(20, 20) == at(24, 24) and at(55, 55) == at(59, 59)))
READ
)
  [[ $grown == 1 ]] || fail "a rectangle that starts mid-block was not grown out to the block grid.
Half of what was being hidden stays legible along the edge."

  # Nothing about the plain crop may change when no rectangle is drawn.
  python3 "$cropper" "$tmp/src.png" "$tmp/plain.png" 10 20 30 25 --block 10 \
    || fail "the cropper rejected --block with nothing to pixelate"

  python3 "$cropper" "$tmp/src.png" "$tmp/x.png" 0 0 10 10 --pixelate 1,2,3 2>/dev/null \
    && fail "the cropper accepted a --pixelate rectangle with three numbers in it"
  python3 "$cropper" "$tmp/src.png" "$tmp/x.png" 0 0 10 10 --block 0 2>/dev/null \
    && fail "the cropper accepted a zero block, which is a divide by zero in the downscale"
  python3 "$cropper" "$tmp/src.png" "$tmp/off.png" 0 0 10 10 --pixelate 500,500,10,10 \
    || fail "a redaction rectangle entirely off the frame lost the whole screenshot"

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

# --------------------------------------------------------------------------
# The mosaic the overlay draws is a picture on a layer surface and reaches no
# file at all. If cut() forgets to hand the rectangles to the cropper, the
# capture still works, the toast still says so, and the private thing is still
# in the PNG -- the one failure mode this tool cannot have.
# --------------------------------------------------------------------------
sed -n '/function cut()/,/^  }/p' "$overlay" | grep -q 'redactions.rects' \
  || fail "CaptureOverlay's cut() does not pass the pixelate rectangles to cropFrozen().
The overlay would draw the mosaic and save a file without it."
sed -n '/function cut()/,/^  }/p' "$overlay" | grep -q 'redactBlock' \
  || fail "CaptureOverlay's cut() does not pass the mosaic block to cropFrozen().
The cropper would fall back to its own default and grid the file differently
from the preview that was agreed to."

# --------------------------------------------------------------------------
# The still is a picture, not a screen, and the capture-target chips aim at the
# screen. `window` is the one that genuinely reaches past the frame: it snaps
# to Hyprland's LIVE client list, so a window that moved or closed during the
# three seconds puts the rectangle where this frame never had it -- and the
# saved crop is wrong with nothing on screen to say so.
# --------------------------------------------------------------------------
toolbar=$src/Modules/Capture/CaptureToolbar.qml
for chip in region window; do
  sed -n "/label: \"$chip\"/,/^    }/p" "$toolbar" | grep -q 'visible: !bar.overlay.frozen' \
    || fail "CaptureToolbar's \"$chip\" chip is offered on the frozen still.
A still has one picture and one question -- which part of it to keep -- and
\"window\" answers it out of the live desktop's geometry instead of the frame."
done

# The chips being hidden is not enough on its own: the target is a property,
# and a capture armed with `window` before the countdown would otherwise arrive
# on the still still set to it -- snapping on hover, with no chip left to
# unset it.
sed -n '/onVisibleChanged/,/^  }/p' "$overlay" \
  | grep -q 'win.target = win.frozen && win.target === "screen" ? "screen" : "region"' \
  || fail "CaptureOverlay's onVisibleChanged does not pin the target on a frozen reopen.
A capture started with \"window\" reaches the still in window mode and hover-snaps
to the live desktop, which is not the picture being cropped."

# Refreshing the client list on a frozen reopen is the same mistake stated
# earlier: it deliberately re-reads the desktop as CURRENT, for a frame that is
# already three seconds old.
sed -n '/onVisibleChanged/,/^  }/p' "$overlay" \
  | grep -q 'if (!win.frozen) Hyprland.refreshToplevels()' \
  || fail "CaptureOverlay refreshes Hyprland's toplevels when reopening onto a still.
Nothing on a still needs live geometry, and fetching it is what makes the stale
rectangle look current."

# The preview and the burnt-in redaction have to snap to the same grid, and
# they are two implementations of one rule in two languages.
grep -q 'Math.floor(x / mosaic.block)' "$src/Modules/Capture/RedactionLayer.qml" \
  || fail "RedactionLayer no longer snaps rectangles out to the block grid, so the
preview and scripts/c7shell-crop.py disagree about where the mosaic falls."
grep -q 'def snap_rect' "$cropper" \
  || fail "the cropper no longer snaps rectangles out to the block grid, so the file
is not gridded the way the overlay previewed it."

echo 'test-capture.sh: all checks passed'
