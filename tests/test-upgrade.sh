#!/usr/bin/env bash
# Self-check for bin/c7shell-upgrade. Run it directly: tests/test-upgrade.sh
#
# Only the config half is exercised (--config-only): the package half rebuilds
# from git and installs with pacman, which a test has no business doing. The
# config half is the part that can lose your edits, so that is what is checked.
set -euo pipefail

here=$(cd -- "$(dirname -- "$0")" && pwd)
upgrade=$here/../bin/c7shell-upgrade
setup=$here/../bin/c7shell-setup
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT

export C7SHELL_SHARE=$tmp/share
export XDG_CONFIG_HOME=$tmp/conf
export C7SHELL_STATE=$tmp/state
export C7SHELL_ROOT=$tmp/root
export C7SHELL_SDDM_THEMES=$tmp/root/usr/share/sddm/themes

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
ship() { mkdir -p -- "$(dirname -- "$C7SHELL_SHARE/$1")"; printf '%s\n' "$2" > "$C7SHELL_SHARE/$1"; }
local_is() { [[ $(cat "$XDG_CONFIG_HOME/$1") == "$2" ]] || fail "$1 should be '$2', is '$(cat "$XDG_CONFIG_HOME/$1")'"; }

# v1 ships, and c7shell-setup installs it and records the manifest
mkdir -p "$C7SHELL_SHARE"/{hypr,quickshell/c7shell}
ship hypr/hyprland.lua 'v1 entry'
ship hypr/keep.lua 'v1 keep'
ship hypr/gone.lua 'v1 gone'
ship quickshell/c7shell/shell.qml 'v1 shell'
ship hypr/xdph.conf 'custom_picker_binary = $HOME/.config/quickshell/c7shell/bin/x.sh'
"$setup" >/dev/null
[[ -f $C7SHELL_STATE/manifest ]] || fail 'c7shell-setup wrote no manifest'
grep -q 'hypr/hyprland.lua' "$C7SHELL_STATE/manifest" || fail 'the manifest is missing a file it installed'

# nothing changed anywhere: the upgrade is a no-op
out=$("$upgrade" --config-only --no-doctor)
grep -q 'already match' <<<"$out" || fail "a no-op upgrade reported work:\n$out"

# the $HOME placeholder rewrite must not read as a local edit, ever
grep -q 'xdph' <<<"$out" && fail "xdph.conf was treated as changed:\n$out"

# --- v2 ships: one file changed, one added, one dropped -------------------
ship hypr/hyprland.lua 'v2 entry'
ship hypr/new.lua 'v2 new'
rm "$C7SHELL_SHARE/hypr/gone.lua"

# the user edited keep.lua, and never touched the rest
printf 'mine\n' > "$XDG_CONFIG_HOME/hypr/keep.lua"
ship hypr/keep.lua 'v2 keep'

# --dry-run first: says everything, changes nothing
before=$(find "$XDG_CONFIG_HOME" -type f | sort | xargs sha256sum)
out=$("$upgrade" --config-only --no-doctor --dry-run)
[[ $(find "$XDG_CONFIG_HOME" -type f | sort | xargs sha256sum) == "$before" ]] \
  || fail '--dry-run changed the configs'
grep -q 'update  hypr/hyprland.lua' <<<"$out" || fail "--dry-run did not plan the update:\n$out"
grep -q 'add     hypr/new.lua'      <<<"$out" || fail "--dry-run did not plan the add:\n$out"
grep -q 'remove  hypr/gone.lua'     <<<"$out" || fail "--dry-run did not plan the removal:\n$out"
grep -q 'kept    hypr/keep.lua'     <<<"$out" || fail "--dry-run did not plan to keep the edit:\n$out"

# now for real. exit 4 == there is something to merge
rc=0; out=$("$upgrade" --config-only --no-doctor) || rc=$?
((rc == 4)) || fail "expected exit 4 when a file needs merging, got $rc:\n$out"

# a file the user never touched is brought forward
local_is hypr/hyprland.lua 'v2 entry'
# a file the user edited is untouched, and the new version is parked beside it
local_is hypr/keep.lua 'mine'
local_is hypr/keep.lua.new 'v2 keep'
# a new file arrives
local_is hypr/new.lua 'v2 new'
# a file dropped upstream that the user never touched goes away
[[ ! -e $XDG_CONFIG_HOME/hypr/gone.lua ]] || fail 'a file dropped upstream was kept'
grep -q "$XDG_CONFIG_HOME/hypr/keep.lua" <<<"$out" || fail "the conflict was not listed:\n$out"

# --- running it again is idempotent, and still reports the pending merge ---
rc=0; out=$("$upgrade" --config-only --no-doctor) || rc=$?
((rc == 4)) || fail "the pending merge should still be reported, got $rc:\n$out"
grep -q 'updated 0' <<<"$out" || fail "re-ran an update that was already applied:\n$out"
local_is hypr/keep.lua 'mine'
local_is hypr/keep.lua.new 'v2 keep'

# once merged, the conflict is gone and the upgrade is clean again
printf 'v2 keep\n' > "$XDG_CONFIG_HOME/hypr/keep.lua"
rm "$XDG_CONFIG_HOME/hypr/keep.lua.new"
rc=0; out=$("$upgrade" --config-only --no-doctor) || rc=$?
((rc == 0)) || fail "expected a clean exit after merging, got $rc:\n$out"

# --- a file dropped upstream that the user DID edit is left alone ---------
printf 'v3 entry\n' > "$C7SHELL_SHARE/hypr/hyprland.lua"
printf 'my own file\n' > "$XDG_CONFIG_HOME/hypr/mine.lua"
out=$("$upgrade" --config-only --no-doctor 2>&1)
[[ -f $XDG_CONFIG_HOME/hypr/mine.lua ]] || fail 'deleted a file the package never shipped'
grep -q 'no longer shipped but differs' <<<"$out" || fail "an unknown local file was not reported:\n$out"

# --- an install from before the manifest existed keeps every difference ---
rm -f "$C7SHELL_STATE/manifest"
printf 'v4 entry\n' > "$C7SHELL_SHARE/hypr/hyprland.lua"
printf 'local edit\n' > "$XDG_CONFIG_HOME/hypr/shell-of-theseus.lua"
rc=0; out=$("$upgrade" --config-only --no-doctor 2>&1) || rc=$?
grep -q 'no manifest' <<<"$out" || fail "no note about the missing manifest:\n$out"
((rc == 4)) || fail "without a manifest every difference should be kept, got $rc:\n$out"
local_is hypr/hyprland.lua 'v3 entry'
local_is hypr/hyprland.lua.new 'v4 entry'

# --- the greeter theme ----------------------------------------------------
# The theme QML rides along with the package, but the selection is a line in
# /etc/sddm.conf.d that no package may write -- so an install from before the
# theme existed has the files and not the selection. Closing that gap is what
# this step is for.
dropin=$tmp/root/etc/sddm.conf.d/10-c7shell.conf

# A machine with no sddm gets no drop-in at all
out=$("$upgrade" --config-only --no-doctor 2>&1) || true
grep -q 'sddm is not installed' <<<"$out" || fail "an sddm-less machine was not reported:\n$out"
[[ -e $dropin ]] && fail 'wrote a drop-in on a machine without sddm'

# From here on sddm is present but the theme is not
mkdir -p "$tmp/root/usr/bin" "$tmp/bin"
printf '#!/bin/sh\nexit 0\n' > "$tmp/root/usr/bin/sddm"; chmod +x "$tmp/root/usr/bin/sddm"

# Nothing to select while the theme is not installed
out=$("$upgrade" --config-only --no-doctor 2>&1) || true
grep -q 'nothing to select' <<<"$out" || fail "an absent theme was not reported:\n$out"
[[ -e $dropin ]] && fail 'wrote a drop-in for a theme that is not installed'

# With the theme installed and no selection anywhere, it gets selected
mkdir -p "$C7SHELL_SDDM_THEMES/c7shell"
touch "$C7SHELL_SDDM_THEMES/c7shell/Main.qml"
out=$("$upgrade" --config-only --no-doctor --dry-run 2>&1)
grep -q "would write $dropin" <<<"$out" || fail "--dry-run did not plan the drop-in:\n$out"
[[ -e $dropin ]] && fail '--dry-run wrote the drop-in'

# For real, with a stub in front of the real sudo: a test must never reach for
# root, and must never sit on a password prompt either.
printf '#!/bin/sh\nexec "$@"\n' > "$tmp/bin/sudo"; chmod +x "$tmp/bin/sudo"
export PATH="$tmp/bin:$PATH"
out=$("$upgrade" --config-only --no-doctor 2>&1) || true
grep -q 'selecting the c7shell theme' <<<"$out" || fail "the selection was not attempted:\n$out"
[[ -f $dropin ]] || fail "the drop-in was not written:\n$out"
grep -q '^Current=c7shell$' "$dropin" || fail "the drop-in does not select c7shell:\n$(cat "$dropin")"
grep -q 'GreeterEnvironment=QML_XHR_ALLOW_FILE_READ=1' "$dropin" \
  || fail "the drop-in does not let the greeter read /proc:\n$(cat "$dropin")"

# Somebody else's theme is left alone: an upgrade does not overrule a choice
mkdir -p "$tmp/root/etc/sddm.conf.d"
rm -f "$dropin"
printf '[Theme]\nCurrent=breeze\n' > "$tmp/root/etc/sddm.conf"
out=$("$upgrade" --config-only --no-doctor 2>&1) || true
grep -q 'leaving it alone' <<<"$out" || fail "another theme was not respected:\n$out"
[[ -e $dropin ]] && fail "overwrote somebody else's theme selection"

# Once ours is in place there is nothing to do, and --no-greeter says nothing
printf '[Theme]\nCurrent=c7shell\n' > "$dropin"
rm -f "$tmp/root/etc/sddm.conf"
out=$("$upgrade" --config-only --no-doctor 2>&1) || true
grep -q 'already uses the c7shell theme' <<<"$out" || fail "an applied theme was not recognised:\n$out"
out=$("$upgrade" --config-only --no-doctor --no-greeter 2>&1) || true
grep -q 'greeter theme' <<<"$out" && fail "--no-greeter still touched the greeter:\n$out"

echo 'PASS: c7shell-upgrade'
