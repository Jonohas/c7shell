#!/usr/bin/env bash
# Static checks on the shell's QML. Run it directly: tests/test-qml-hygiene.sh
#
# Everything here is a mistake that a compositor-less test cannot catch and
# qmllint reports only as noise, but that takes the whole shell down when the
# real config loads -- quickshell aborts the entire configuration on one bad
# property assignment, so a typo in a popover nobody has opened yet is still a
# desktop with no bar on it.
set -euo pipefail

here=$(cd -- "$(dirname -- "$0")" && pwd)
src=$here/../quickshell/c7shell

fail() { printf 'FAIL: %b\n' "$1" >&2; exit 1; }

# --------------------------------------------------------------------------
# font.pixelSize and font.weight are ints. A fractional literal is not rounded
# and is not a warning -- it is "Invalid property assignment: int expected",
# which fails the load of the file, every file that imports it, and therefore
# the shell. Common/SectionLabel.qml carries the note that 9.5 is written as
# 10 for exactly this reason; this makes the rule enforceable instead of
# folklore.
# --------------------------------------------------------------------------
hits=$(grep -rn --include='*.qml' -E '\b(pixelSize|weight):[[:space:]]*[0-9]+\.[0-9]' "$src" || true)
if [[ -n $hits ]]; then
  fail "font.pixelSize and font.weight are ints; a fractional literal fails the
  whole configuration load, not just the binding. Round it (the design's 9.5
  is written as 10 -- see Common/SectionLabel.qml):\n$hits"
fi

# --------------------------------------------------------------------------
# A singleton named from another directory without importing its module
# resolves at call time, not load time: the shell starts clean and the button
# does nothing the first time somebody presses it. Files inside Services/ are
# exempt -- the containing directory is an implicit import, so siblings
# resolve without one, which is why DisplayService has always worked.
# --------------------------------------------------------------------------
while read -r f; do
  case $f in "$src"/Services/*) continue ;; esac
  grep -q '^import qs.Services' "$f" && continue
  while read -r used; do
    [[ -f $src/Services/$used.qml ]] || continue
    fail "$(basename "$f") uses the $used singleton from another directory but
  does not 'import qs.Services'. That resolves at call time, so the shell loads
  clean and the feature fails on first use."
    # Comments are stripped first: naming a singleton in a comment is not
    # using it, and a note like "Keys match SettingsService.open(page)" is
    # exactly the kind of prose this file is full of.
  done < <(sed 's|//.*||' "$f" \
    | grep -oE '\b[A-Z][A-Za-z]*(Service|Manager|Store|Server|Actions)\.' | tr -d '.' | sort -u)
done < <(find "$src" -name '*.qml')

# --------------------------------------------------------------------------
# Every QML file the shell ships has to be reachable from shell.qml's imports.
# A component in a directory nothing imports loads only by accident of being a
# sibling, which is exactly how a file ends up working in one place and
# "unavailable" in another.
# --------------------------------------------------------------------------
while read -r dir; do
  rel=${dir#"$src/"}
  [[ $rel == "$src" || -z $rel ]] && continue
  mod=qs.${rel//\//.}
  # Assets and scripts are not QML modules; Theme and Common are imported by
  # nearly every file rather than by shell.qml.
  case $rel in Assets*|scripts*|bin*|docs*|Theme|Common) continue ;; esac
  grep -rqF "import $mod" "$src" && continue
  # A standalone entry point is loaded by path rather than imported --
  # Modules/SharePicker/PickerApp.qml is launched by bin/screenshare-picker.sh
  # for xdph. Those are fine; a module nothing reaches at all is not.
  entry=0
  while read -r q; do
    grep -rqF "$(basename "$q")" "$src"/bin "$src"/scripts "$here/.." --include='*.sh' \
      --include='*.lua' --include='*.py' --include='PKGBUILD' 2>/dev/null && entry=1
  done < <(find "$dir" -maxdepth 1 -name '*.qml')
  ((entry)) \
    || fail "no file imports $mod and nothing launches it by path, so the QML in
  $rel is only reachable by accident of directory adjacency"
done < <(find "$src" -mindepth 1 -type d -not -path '*/Assets/*')

# --------------------------------------------------------------------------
# PopoverManager holds ONE name at a time, so a name claimed by two popovers
# means both windows map on the same click. Each then asks Hyprland for a focus
# grab, the second request cancels the first, HyprlandFocusGrab.onCleared calls
# PopoverManager.close(), and both panels vanish. What the user sees is a
# popover that flashes and disappears; what the log says is nothing at all.
#
# This happened for real: the battery popover was named "power", which the
# session menu behind the bar's power button already answered to.
# --------------------------------------------------------------------------
# GlassPopover subclasses declare `name:`; PowerDropdown is a PopupSurface of
# its own and declares the same identity as `open: ... === "x"`.
names=$(
  # Exactly two spaces: that is a property of the popover's own root object.
  # Anything deeper is a nested Icon, which uses `name` for its glyph.
  { grep -rh --include='*.qml' -E '^  name: "[a-z]+"$' "$src/Modules/Popovers" 2>/dev/null \
      | sed -E 's/.*"([a-z]+)".*/\1/'
    grep -rh --include='*.qml' -E 'open: PopoverManager\.current === "[a-z]+"' "$src" 2>/dev/null \
      | sed -E 's/.*=== "([a-z]+)".*/\1/'
  } | sort
)
dupes=$(printf '%s\n' "$names" | uniq -d)
if [[ -n $dupes ]]; then
  fail "two popovers answer to the same PopoverManager name, so one click maps
  both windows and their focus grabs cancel each other -- the panel flashes and
  vanishes with nothing in the log:\n$dupes"
fi

# The other half of the same mistake: a bar module that toggles a name no
# popover answers to is a button that visibly does nothing.
while read -r want; do
  printf '%s\n' "$names" | grep -qx "$want" \
    || fail "PopoverManager.toggle(\"$want\", ...) names a popover that does not
  exist, so the button it is on does nothing at all"
done < <(grep -rho --include='*.qml' -E 'PopoverManager\.toggle\("[a-z]+"' "$src" \
  | sed -E 's/.*\("([a-z]+)".*/\1/' | sort -u)

echo 'test-qml-hygiene.sh: all checks passed'
