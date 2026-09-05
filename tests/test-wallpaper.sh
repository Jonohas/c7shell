#!/usr/bin/env bash
# Self-check for the shell-painted wallpaper. Run it directly:
#   tests/test-wallpaper.sh
#
# Which program owns the wallpaper is decided in lua and acted on in QML, and
# tests/test-gpu.lua covers the lua half -- the detection, and what autostart,
# environment and look-and-feel each do with it. This is the QML half: that the
# shell instantiates the window, only where it should, and that the store stops
# talking to a hyprpaper that is not running.
#
# It is structural, and deliberately so: PanelWindow, WlrLayershell and the
# Quickshell singleton only exist inside the qs binary (its QML plugin is linked
# into it, so qml6 cannot even load the module), and a layer surface cannot be
# rendered offscreen. What can be checked without a compositor is checked here;
# the rest was verified against a live session -- with the layer up the desktop
# reads the wallpaper's own black, with it down Hyprland's #111111.  # palette-literal-ok: hyprland's built-in background, not ours
set -euo pipefail

here=$(cd -- "$(dirname -- "$0")" && pwd)
shell=$here/../quickshell/c7shell
paper=$shell/Modules/Wallpaper/Wallpaper.qml
store=$shell/Services/AppearanceStore.qml

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

[[ -f $paper ]] || fail 'Modules/Wallpaper/Wallpaper.qml is missing'

# An instantiated component, or it is dead code however correct.
grep -q '^import qs.Modules.Wallpaper$' "$shell/shell.qml" \
  || fail 'shell.qml does not import the wallpaper module'
grep -q '^  Wallpaper {}$' "$shell/shell.qml" \
  || fail 'shell.qml does not instantiate Wallpaper'

# Below every window and reserving nothing. On the wrong layer it would cover
# the desktop rather than back it.
grep -q 'WlrLayershell.layer: WlrLayer.Background' "$paper" \
  || fail 'the wallpaper is not on the background layer'
grep -q 'exclusionMode: ExclusionMode.Ignore' "$paper" \
  || fail 'the wallpaper reserves screen space'
# An empty input region. Without it a full-screen surface under everything
# swallows every click meant for the desktop.
grep -q 'mask: Region {}' "$paper" \
  || fail 'the wallpaper takes pointer input'

# The two conditions on mapping anything at all. Dropping the second paints a
# black rectangle over Hyprland's own background on machines with no wallpaper.
grep -q 'AppearanceStore.shellDrawsWallpaper && AppearanceStore.wallpaper !== ""' "$paper" \
  || fail 'the wallpaper window is not gated on both the backend and a path'

# The env var hypr/conf/environment.lua exports. Unset means hyprpaper, so a
# shell run outside a c7shell session behaves the way it always did.
grep -q 'readonly property bool shellDrawsWallpaper: Quickshell.env("C7SHELL_WALLPAPER") === "shell"' "$store" \
  || fail 'AppearanceStore does not read C7SHELL_WALLPAPER'

# And the half that would otherwise still be talking to a process that SIGABRTed
# at session start. Harmless, but it is what makes the two backends exclusive
# rather than merely different.
grep -q 'if (root.shellDrawsWallpaper) return' "$store" \
  || fail 'the store still pushes the wallpaper at hyprpaper when the shell owns it'

# Cover, not stretch: hyprpaper crops a mismatched aspect, and the two backends
# must not frame the same picture differently.
grep -q 'fillMode: Image.PreserveAspectCrop' "$paper" \
  || fail 'the wallpaper does not crop to fill the way hyprpaper does'

echo 'PASS: shell-painted wallpaper'
