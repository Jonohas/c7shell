#!/usr/bin/env bash
# Self-check for bin/c7shell-doctor. Run it directly: tests/test-doctor.sh
#
# The doctor inspects the live system, so the test builds a fake one: a stub
# PATH holding one dummy executable per required command, and a fake root tree
# (C7SHELL_ROOT) holding the files and QML module directories it looks for.
set -euo pipefail

here=$(cd -- "$(dirname -- "$0")" && pwd)
doctor=$here/../bin/c7shell-doctor
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT

bin=$tmp/bin
root=$tmp/root
conf=$tmp/conf
mkdir -p "$bin" "$root" "$conf"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

# The doctor itself needs these to run under a PATH with nothing else on it.
for helper in grep head; do ln -s "$(command -v "$helper")" "$bin/$helper"; done

stub() { printf '#!/bin/sh\nexit 0\n' > "$bin/$1"; chmod +x "$bin/$1"; }

required_cmds=(hyprctl qs hypridle hyprlock hyprpaper hyprpicker grim
               wf-recorder wl-copy notify-send wpctl bluetoothctl nmcli systemctl)
for cmd in "${required_cmds[@]}"; do stub "$cmd"; done
# Every python import the appmenu daemon needs is reported present.
stub python3

hyprland_version() {
  printf '#!/bin/sh\necho "Hyprland %s built from branch"\n' "$1" > "$bin/Hyprland"
  chmod +x "$bin/Hyprland"
}
hyprland_version 0.56.1

mkdir -p "$root/usr/lib/hyprpolkitagent" "$root/usr/lib" \
         "$root/usr/share/wayland-sessions" "$root/dev/dri"
: > "$root/usr/lib/hyprpolkitagent/hyprpolkitagent"
: > "$root/usr/lib/xdg-desktop-portal-hyprland"
: > "$root/usr/lib/pam_kwallet_init"
: > "$root/usr/share/wayland-sessions/c7shell.desktop"
: > "$root/dev/dri/card0"
: > "$root/dev/dri/renderD128"

for mod in Quickshell Quickshell/Hyprland Quickshell/Io Quickshell/Wayland \
           Quickshell/Bluetooth Quickshell/Networking \
           Quickshell/Services/Pipewire Quickshell/Services/UPower \
           Quickshell/Services/SystemTray Quickshell/Services/Notifications \
           QtQuick/Effects QtQuick/Shapes; do
  mkdir -p "$root/usr/lib/qt6/qml/$mod"
done

mkdir -p "$conf/hypr" "$conf/quickshell/c7shell" "$tmp/share"
: > "$conf/hypr/hyprland.lua"
: > "$conf/quickshell/c7shell/shell.qml"

run() {
  env -i PATH="$bin" HOME="$tmp" \
    C7SHELL_ROOT="$root" C7SHELL_SHARE="$tmp/share" XDG_CONFIG_HOME="$conf" \
    /usr/bin/bash "$doctor" "$@"
}

# a complete system passes
out=$(run 2>&1) || fail "a complete fake system did not pass:\n$out"
grep -q 'everything' <<<"$out" || fail "expected a clean summary, got:\n$out"

# an Hyprland older than the lua config requirement is a failure, by version
hyprland_version 0.55.0
rc=0; out=$(run 2>&1) || rc=$?
((rc == 1)) || fail "old Hyprland should fail, got exit $rc"
grep -q '0.55.0 is too old' <<<"$out" || fail "no version complaint:\n$out"
hyprland_version 0.56.1

# a quickshell built without a module the shell imports is a failure
mv "$root/usr/lib/qt6/qml/Quickshell/Bluetooth" "$tmp/gone"
rc=0; out=$(run 2>&1) || rc=$?
((rc == 1)) || fail "missing QML module should fail, got exit $rc"
grep -q 'Quickshell.Bluetooth not available' <<<"$out" || fail "no QML complaint:\n$out"
mv "$tmp/gone" "$root/usr/lib/qt6/qml/Quickshell/Bluetooth"

# no DRM device: the compositor cannot start, and that is the black-screen case
rm "$root/dev/dri/card0"
rc=0; out=$(run 2>&1) || rc=$?
((rc == 1)) || fail "missing /dev/dri/card* should fail, got exit $rc"
grep -q 'no GPU driver' <<<"$out" || fail "no GPU complaint:\n$out"
: > "$root/dev/dri/card0"

# configs still in /usr/share: a failure normally, the next step with --setup-pending
mv "$conf/hypr" "$tmp/hypr-gone"
rc=0; out=$(run 2>&1) || rc=$?
((rc == 1)) || fail "missing ~/.config/hypr should fail, got exit $rc"
grep -q 'c7shell-setup' <<<"$out" || fail "no setup hint:\n$out"
out=$(run --setup-pending 2>&1) || fail "--setup-pending should not fail on a fresh install:\n$out"
grep -q 'next  ' <<<"$out" || fail "--setup-pending did not report the next step:\n$out"
mv "$tmp/hypr-gone" "$conf/hypr"

# a missing required command names the package that provides it
rm "$bin/grim"
rc=0; out=$(run 2>&1) || rc=$?
((rc == 1)) || fail "missing grim should fail, got exit $rc"
grep -q 'package: grim' <<<"$out" || fail "no package name for grim:\n$out"
stub grim

# optional programs only warn
rc=0; out=$(run 2>&1) || rc=$?
((rc == 0)) || fail "optional programs should not fail the check, got exit $rc"
grep -q 'warn  kitty' <<<"$out" || fail "kitty should warn, not fail:\n$out"

# --quiet prints problems only
rm "$bin/grim"
out=$(run --quiet 2>&1 || true)
grep -q 'FAIL  grim' <<<"$out" || fail "--quiet dropped the failure:\n$out"
! grep -q '  ok    ' <<<"$out" || fail "--quiet printed passing checks:\n$out"

echo 'PASS: c7shell-doctor'
