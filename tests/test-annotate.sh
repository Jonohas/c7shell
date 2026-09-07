#!/usr/bin/env bash
# Self-check for the annotate editor. Run it directly: tests/test-annotate.sh
#
# Two halves, because the feature is two programs. The editor decides what the
# scene contains; scripts/c7shell-render.py decides what the file contains. The
# preview and the PNG are two different pictures of the same thing and only one
# of them is kept, so the second half is where the checks that matter live.
#
# The editor's surfaces are not here -- AnnotateWindow is a layer surface and
# needs a compositor. What they contribute is checked statically at the bottom.
set -euo pipefail

here=$(cd -- "$(dirname -- "$0")" && pwd)
src=$here/../quickshell/c7shell
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT

fail() { printf 'FAIL: %b\n' "$1" >&2; exit 1; }

renderer=$src/scripts/c7shell-render.py
[[ -x $renderer ]] || fail "scripts/c7shell-render.py is missing or not executable.
AnnotateService resolves it relative to itself and shells out to it; a missing
file there is an editor that draws everything and saves nothing."

# --------------------------------------------------------------------------
# The renderer, which is a program and can just be run.
# --------------------------------------------------------------------------
if python3 -c 'import cairo' 2>/dev/null; then
  # 100x80, every pixel encoding its own coordinates, so an annotation drawn at
  # the wrong offset cannot come out looking plausible.
  python3 - "$tmp" <<'MAKE'
import sys

import cairo

w, h = 100, 80
surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, w, h)
data = surface.get_data()
stride = surface.get_stride()
for y in range(h):
    for x in range(w):
        o = y * stride + x * 4
        # BGRA, premultiplied; opaque, so the channels are the values.
        data[o:o + 4] = bytes((0, y * 3, x * 2, 255))
surface.mark_dirty()
surface.write_to_png(f"{sys.argv[1]}/src.png")
MAKE

  probe() {   # <png> <x> <y> -> "r g b" of that pixel
    python3 - "$1" "$2" "$3" <<'READ'
import sys

import cairo

p = cairo.ImageSurface.create_from_png(sys.argv[1])
x, y = int(sys.argv[2]), int(sys.argv[3])
o = y * p.get_stride() + x * 4
b, g, r = p.get_data()[o:o + 3]
print(r, g, b)
READ
  }

  size() {
    python3 - "$1" <<'READ'
import sys

import cairo

p = cairo.ImageSurface.create_from_png(sys.argv[1])
print(p.get_width(), p.get_height())
READ
  }

  scene() {   # <objects json> [crop json] -> a scene file
    printf '{"source": "%s", "objects": %s, "crop": %s}\n' \
      "$tmp/src.png" "$1" "${2:-null}" > "$tmp/scene.json"
  }

  # A scene with nothing in it must reproduce the capture exactly. This is the
  # path a shot takes when the editor is opened and nothing is drawn, and a
  # renderer that shifts or recolours it there would do so under every
  # annotation as well.
  scene '[]'
  python3 "$renderer" "$tmp/plain.png" --scene "$tmp/scene.json" \
    || fail "the renderer exited non-zero on an empty scene"
  read -r w h < <(size "$tmp/plain.png")
  [[ $w == 100 && $h == 80 ]] || fail "an unedited capture came out ${w}x${h}, not 100x80"
  [[ $(probe "$tmp/plain.png" 30 20) == "60 60 0" ]] \
    || fail "an empty scene changed the image: 30,20 came out $(probe "$tmp/plain.png" 30 20)"

  # A filled rectangle, checked inside and outside. Coordinates are image
  # pixels -- the same numbers the editor stores -- so a scale factor applied
  # anywhere in between shows up here as a rectangle in the wrong place.
  scene '[{"kind":"rect","x":20,"y":20,"w":40,"h":30,"colour":"#ffffff","fill":true}]'
  python3 "$renderer" "$tmp/filled.png" --scene "$tmp/scene.json" \
    || fail "the renderer exited non-zero on a filled rectangle"
  [[ $(probe "$tmp/filled.png" 40 30) == "255 255 255" ]] \
    || fail "the middle of a filled rectangle is $(probe "$tmp/filled.png" 40 30), not the colour it was given"
  [[ $(probe "$tmp/filled.png" 10 10) == "20 30 0" ]] \
    || fail "a filled rectangle changed a pixel outside itself"
  # One pixel past the far edge. Off-by-one here is a rectangle that does not
  # end where the editor showed it ending.
  [[ $(probe "$tmp/filled.png" 60 30) == "120 90 0" ]] \
    || fail "the rectangle overran its own width: 60,30 is $(probe "$tmp/filled.png" 60 30)"

  # An outlined rectangle is a border and a hole. A stroke centred on the path
  # would put half of it outside the rectangle that was drawn -- and for a
  # rectangle flush against the edge of the shot, that half is off the frame.
  scene '[{"kind":"rect","x":20,"y":20,"w":40,"h":30,"colour":"#ffffff","stroke":4}]'
  python3 "$renderer" "$tmp/outline.png" --scene "$tmp/scene.json" \
    || fail "the renderer exited non-zero on an outlined rectangle"
  [[ $(probe "$tmp/outline.png" 40 21) == "255 255 255" ]] \
    || fail "the top edge of an outlined rectangle was not drawn"
  [[ $(probe "$tmp/outline.png" 40 35) == "80 105 0" ]] \
    || fail "an outlined rectangle was filled in: its middle is $(probe "$tmp/outline.png" 40 35)"
  [[ $(probe "$tmp/outline.png" 40 18) == "80 54 0" ]] \
    || fail "the stroke was drawn outside the rectangle. Centred on the path, half
of it lands outside what the editor showed -- and off the frame entirely for a
rectangle against the edge of the shot."

  # A rectangle dragged right-to-left arrives with a negative width. The editor
  # leaves it that way on purpose -- normalising mid-drag makes it jump under
  # the pointer -- so this end has to cope.
  scene '[{"kind":"rect","x":60,"y":50,"w":-40,"h":-30,"colour":"#ffffff","fill":true}]'
  python3 "$renderer" "$tmp/backwards.png" --scene "$tmp/scene.json" \
    || fail "the renderer exited non-zero on a rectangle dragged backwards"
  [[ $(probe "$tmp/backwards.png" 40 30) == "255 255 255" ]] \
    || fail "a rectangle dragged right-to-left was not drawn where it was dragged"

  # The crop is applied last, so annotations stay in whole-image coordinates
  # and a crop made after them does not move them.
  scene '[{"kind":"rect","x":20,"y":20,"w":40,"h":30,"colour":"#ffffff","fill":true}]' \
        '{"x":10,"y":10,"w":60,"h":50}'
  python3 "$renderer" "$tmp/cropped.png" --scene "$tmp/scene.json" \
    || fail "the renderer exited non-zero on a cropped scene"
  read -r w h < <(size "$tmp/cropped.png")
  [[ $w == 60 && $h == 50 ]] || fail "a 60x50 crop produced ${w}x${h}"
  # The rectangle's own 20,20 is 10,10 in the cropped frame.
  [[ $(probe "$tmp/cropped.png" 30 20) == "255 255 255" ]] \
    || fail "the crop moved the annotations with it; they are in image coordinates
and the crop is applied after they are drawn."

  # A crop overhanging the frame clamps rather than failing. It is a rounding
  # question at the edge of the image, not a reason to lose the screenshot.
  scene '[]' '{"x":80,"y":60,"w":60,"h":50}'
  python3 "$renderer" "$tmp/edge.png" --scene "$tmp/scene.json" \
    || fail "a crop overhanging the frame was rejected instead of clamped"

  # --- the failures that have to be loud ----------------------------------
  # A kind the renderer cannot draw is the one that must never be a warning:
  # the editor showed the annotation, and a file quietly missing it still lands
  # in ~/Pictures looking finished.
  scene '[{"kind":"blur","x":0,"y":0,"w":10,"h":10}]'
  if err=$(python3 "$renderer" "$tmp/x.png" --scene "$tmp/scene.json" 2>&1); then
    fail "the renderer accepted an object kind it cannot draw. The editor would
have shown that annotation and the exported file would not contain it."
  fi
  # A non-zero exit on its own proves nothing: an unhandled KeyError on the
  # draw table exits non-zero too, and would keep doing so after the check that
  # is supposed to catch this had been deleted. So the message has to be the
  # renderer's own, and has to name the kind.
  grep -q '^c7shell-render: ' <<<"$err" \
    || fail "the renderer crashed on an unknown object kind rather than reporting
one. The exit code is the same either way, which is why this looks at what it
said:\n$err"
  grep -q 'blur' <<<"$err" \
    || fail "the renderer rejected an unknown kind without saying which one:\n$err"

  python3 "$renderer" "$tmp/x.png" --scene "$tmp/nope.json" 2>/dev/null \
    && fail "the renderer exited zero on a scene file that does not exist"
  python3 "$renderer" "$tmp/x.png" --scene-json 'not json' 2>/dev/null \
    && fail "the renderer exited zero on a scene that is not JSON"
  printf '{"source": "%s/nope.png", "objects": []}\n' "$tmp" > "$tmp/scene.json"
  python3 "$renderer" "$tmp/x.png" --scene "$tmp/scene.json" 2>/dev/null \
    && fail "the renderer exited zero on a source image that does not exist"
  scene '[{"kind":"rect","x":0,"y":0,"w":5,"h":5,"colour":"accent","fill":true}]'
  python3 "$renderer" "$tmp/x.png" --scene "$tmp/scene.json" 2>/dev/null \
    && fail "the renderer accepted a palette token as a colour. Tokens are resolved
in AnnotateService.scene(); one arriving here means it was not, and the
annotation would be drawn in a colour nobody chose."
  python3 "$renderer" "$tmp/x.png" 2>/dev/null \
    && fail "the renderer exited zero with no scene at all"
else
  echo 'SKIP: the render checks (no cairo python module -- package: python-cairo)'
fi

# --------------------------------------------------------------------------
# The scene, which is what the renderer above is handed.
# --------------------------------------------------------------------------
if ! command -v qml6 >/dev/null; then
  echo 'SKIP: the scene checks (qml6 not installed -- package: qt6-declarative)'
else
  mkdir -p "$tmp/qs/Services" "$tmp/Quickshell/Io"
  cp "$here/annotate-qml-test.qml" "$tmp/"
  cp "$src/Services/AnnotateService.qml" "$tmp/qs/Services/"

  # CaptureService is named by AnnotateService's export path (deliver, fail)
  # and by nothing under test here. Naming a singleton that does not exist is a
  # load error for the whole file, so it is stubbed rather than copied -- the
  # real one would drag in grim, the toast and the preference with it.
  cat > "$tmp/qs/Services/CaptureService.qml" <<'CAPTURE'
pragma Singleton
import QtQuick
QtObject {
  function deliver(file, copy) {}
  function fail(what, why) {}
}
CAPTURE
  printf 'module qs.Services\nsingleton AnnotateService 1.0 AnnotateService.qml\nsingleton CaptureService 1.0 CaptureService.qml\n' \
    > "$tmp/qs/Services/qmldir"

  printf 'import QtQuick\nItem {}\n' > "$tmp/Quickshell/Singleton.qml"
  cat > "$tmp/Quickshell/QuickshellGlobal.qml" <<'GLOBAL'
pragma Singleton
import QtQuick
QtObject {
  function env(name) { return "/nonexistent" }
  function execDetached(argv) {}
}
GLOBAL
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
  printf 'module Quickshell.Io\nProcess 1.0 Process.qml\nStdioCollector 1.0 StdioCollector.qml\n' \
    > "$tmp/Quickshell/Io/qmldir"

  log=$tmp/annotate.log
  # QT_FORCE_STDERR_LOGGING: without a tty Qt sends its messages to journald,
  # where this test cannot see them.
  QT_QPA_PLATFORM=offscreen \
  QT_FORCE_STDERR_LOGGING=1 \
  timeout 60 qml6 -I "$tmp" "$tmp/annotate-qml-test.qml" >"$log" 2>&1 \
    || fail "qml6 exited non-zero:\n$(cat "$log")"

  grep -q 'ANNOTATE-TEST-PASS' "$log" || fail "the test never reached its end:\n$(cat "$log")"
  if grep -q '\.qml:' "$log"; then
    fail "QML diagnostics:\n$(grep '\.qml:' "$log")"
  fi
fi

# --------------------------------------------------------------------------
# The surfaces, which nothing above can instantiate. Their risk is not the
# layer surface -- it is the names they read off AnnotateService. A misspelt
# one is not a load failure: quickshell logs a binding warning and carries on,
# so the editor comes up looking right and one tool silently does nothing.
# --------------------------------------------------------------------------
svc=$src/Services/AnnotateService.qml
while read -r f; do
  missing=()
  while read -r name; do
    grep -qE "^[[:space:]]*(readonly[[:space:]]+)?property[[:space:]]+[A-Za-z0-9_<>]+[[:space:]]+$name\b" "$svc" && continue
    grep -qE "^[[:space:]]*function[[:space:]]+$name\b" "$svc" && continue
    grep -qE "^[[:space:]]*signal[[:space:]]+$name\b" "$svc" && continue
    missing+=("$name")
  done < <(sed 's|//.*||' "$f" | grep -oE 'AnnotateService\.[A-Za-z_][A-Za-z0-9_]*' \
           | sed 's/AnnotateService\.//' | sort -u)

  if ((${#missing[@]})); then
    fail "$(basename "$f") reads these off AnnotateService, which does not declare them:
  ${missing[*]}
A misspelt binding here is a warning, not an error -- the editor loads clean and
that piece of it silently goes missing."
  fi
done < <(find "$src/Modules/Annotate" -name '*.qml')

# --------------------------------------------------------------------------
# The tool bar IS the number-key mapping: AnnotateWindow indexes into it rather
# than carrying a second list. Two lists would be one list that disagrees with
# itself, and the symptom is a key that selects the wrong tool.
# --------------------------------------------------------------------------
grep -q 'toolbar.tools\[slot\]' "$src/Modules/Annotate/AnnotateWindow.qml" \
  || fail "AnnotateWindow no longer takes the number-key mapping from the tool bar's
own order, so 1-9 and the bar can disagree about which tool is which."

# --------------------------------------------------------------------------
# Every tool the bar offers must be a kind the renderer can draw. A tool added
# to the bar without an arm in the renderer draws on screen and then fails the
# export -- loudly, which is the right failure, but it fails it every time.
# `select` and `crop` are not object kinds: neither puts anything in the list.
# --------------------------------------------------------------------------
# The renderer's own list, not the whole file: `"rect"` appears in it several
# times over, and a tool named only in a comment there would pass a plain grep
# while drawing nothing.
kinds=$(sed -n '/^KINDS = (/,/)/p' "$renderer" | grep -oE '"[a-z]+"' | tr -d '"')
[[ -n $kinds ]] || fail "could not read KINDS out of scripts/c7shell-render.py; this
check would pass for every tool without looking at anything."

while read -r tool; do
  case $tool in select | crop) continue ;; esac
  printf '%s\n' "$kinds" | grep -qx "$tool" && continue
  fail "the tool bar offers \"$tool\" but it is not in scripts/c7shell-render.py's
KINDS, so the renderer has no arm for it. Every export from a capture carrying
one would fail -- loudly, which is the right failure, but every time."
done < <(grep -oE '\{ id: "[a-z]+"' "$src/Modules/Annotate/EditorToolBar.qml" \
  | sed -E 's/.*"([a-z]+)".*/\1/')

echo 'test-annotate.sh: all checks passed'
