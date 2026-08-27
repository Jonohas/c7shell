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

required_cmds=(hyprctl start-hyprland qs hypridle hyprlock hyprpaper hyprpicker grim
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
# The Settings-portal backend, plus a gsettings that reports a preference
# already exported -- what a set-up machine looks like.
: > "$root/usr/lib/xdg-desktop-portal-gtk"
gsettings_scheme() {
  printf '#!/bin/sh\necho "%s"\n' "$1" > "$bin/gsettings"
  chmod +x "$bin/gsettings"
}
gsettings_scheme "'prefer-dark'"
: > "$root/usr/lib/pam_kwallet_init"
printf '[Desktop Entry]\nName=c7shell\nExec=start-hyprland\n' \
  > "$root/usr/share/wayland-sessions/c7shell.desktop"
: > "$root/dev/dri/card0"
: > "$root/dev/dri/renderD128"

mkdir -p "$root/usr/lib/qt6/plugins/platformthemes" "$root/usr/lib/qt6/plugins/styles"
: > "$root/usr/lib/qt6/plugins/platformthemes/KDEPlasmaPlatformTheme6.so"
: > "$root/usr/lib/qt6/plugins/styles/breeze6.so"
printf '[General]\nColorScheme=C7Shell\n' > "$conf/kdeglobals"

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

stub grim     # the --quiet case above removed it; these cases want a clean pass
stub dolphin  # an app that benefits, which is what turns the theming checks on

# now that a Qt/KDE app is installed, the theming section reports
out=$(run 2>&1) || fail "the theming section should not be fatal:\n$out"
grep -q 'Qt/KDE apps present: dolphin' <<<"$out" || fail "dolphin did not turn the checks on:\n$out"

# no platform theme plugin: QT_QPA_PLATFORMTHEME=kde is inert and Qt apps look
# stock, which is a warning (the shell itself still runs) naming the package
mv "$root/usr/lib/qt6/plugins/platformthemes/KDEPlasmaPlatformTheme6.so" "$tmp/theme-gone"
out=$(run 2>&1) || fail "a missing platform theme plugin should not be fatal:\n$out"
grep -q 'KDEPlasmaPlatformTheme6.so missing' <<<"$out" || fail "the missing plugin was not reported:\n$out"
grep -q 'plasma-integration' <<<"$out" || fail "plasma-integration was not named:\n$out"
mv "$tmp/theme-gone" "$root/usr/lib/qt6/plugins/platformthemes/KDEPlasmaPlatformTheme6.so"

# kdeglobals without the exported scheme is reported with the command to seed it
mv "$conf/kdeglobals" "$tmp/kdeglobals-gone"
mkdir -p "$conf/quickshell/c7shell/scripts"
: > "$conf/quickshell/c7shell/scripts/c7shell-theme-export.py"
out=$(run 2>&1) || fail "an unexported palette should not be fatal:\n$out"
grep -q 'no C7Shell scheme yet' <<<"$out" || fail "the unexported palette was not reported:\n$out"
grep -q 'c7shell-theme-export.py' <<<"$out" || fail "no seed command given:\n$out"
mv "$tmp/kdeglobals-gone" "$conf/kdeglobals"

# without the gtk backend nothing answers the Settings portal, so every app that
# detects a theme picks light -- required, not cosmetic
mv "$root/usr/lib/xdg-desktop-portal-gtk" "$tmp/portal-gtk-gone"
rc=0; out=$(run 2>&1) || rc=$?
((rc == 1)) || fail "a missing Settings portal backend should fail, got exit $rc"
grep -q 'xdg-desktop-portal-gtk missing' <<<"$out" || fail "the missing backend was not reported:\n$out"
mv "$tmp/portal-gtk-gone" "$root/usr/lib/xdg-desktop-portal-gtk"

# the backend can only report what GSettings holds: unset is the state that left
# apps light, and it names how to set it
gsettings_scheme "'default'"
out=$(run 2>&1) || fail "an unset color-scheme should warn, not fail:\n$out"
grep -q 'no color-scheme preference set' <<<"$out" || fail "the unset preference was not reported:\n$out"
grep -q 'c7shell-theme-export.py' <<<"$out" || fail "no way to set it given:\n$out"
gsettings_scheme "'prefer-dark'"

# an install from before the launcher fix is spotted, and names the repair
printf '[Desktop Entry]\nName=c7shell\nExec=Hyprland\n' \
  > "$root/usr/share/wayland-sessions/c7shell.desktop"
out=$(run 2>&1) || fail "an old session entry should warn, not fail:\n$out"
grep -q 'execs Hyprland directly' <<<"$out" || fail "the old launcher was not noticed:\n$out"
grep -q 'c7shell-upgrade' <<<"$out" || fail "no repair command named:\n$out"
printf '[Desktop Entry]\nName=c7shell\nExec=start-hyprland\n' \
  > "$root/usr/share/wayland-sessions/c7shell.desktop"
out=$(run --quiet 2>&1 || true)
grep -q 'execs Hyprland directly' <<<"$out" && fail "a current session entry still warned:\n$out"

# --- the greeter theme -----------------------------------------------------
# The theme QML comes with the package; the selection is a drop-in in
# /etc/sddm.conf.d that c7shell-bootstrap or c7shell-upgrade writes. Every
# state here is a warning: a machine may run another display manager and the
# session works regardless.
out=$(run 2>&1) || fail "an sddm-less machine should not fail:\n$out"
grep -q 'sddm is not installed' <<<"$out" || fail "no note about the unused theme:\n$out"

stub sddm   # sddm here, theme not: the package needs rebuilding
out=$(run 2>&1) || fail "a missing theme should not fail:\n$out"
grep -q 'themes/c7shell is not' <<<"$out" || fail "the missing theme was not reported:\n$out"
grep -q 'c7shell-upgrade' <<<"$out" || fail "no repair command for the missing theme:\n$out"

mkdir -p "$root/usr/share/sddm/themes/c7shell" "$root/etc/sddm.conf.d" "$root/usr/bin"
: > "$root/usr/share/sddm/themes/c7shell/Main.qml"
theme_meta=$root/usr/share/sddm/themes/c7shell/metadata.desktop
printf '[SddmGreeterTheme]\nName=c7shell\nQtVersion=6\nMainScript=Main.qml\n' > "$theme_meta"
# The binary sddm derives from QtVersion, and an ldd that reports its libraries
# resolve -- what a machine that will actually show a login screen looks like.
: > "$root/usr/bin/sddm-greeter-qt6"; chmod +x "$root/usr/bin/sddm-greeter-qt6"
printf '#!/bin/sh\nexit 0\n' > "$bin/ldd"; chmod +x "$bin/ldd"
out=$(run 2>&1) || fail "an unselected theme should not fail:\n$out"
grep -q 'no sddm theme is selected' <<<"$out" || fail "the unselected theme was not reported:\n$out"

printf '[Theme]\nCurrent=breeze\n' > "$root/etc/sddm.conf"
out=$(run 2>&1) || fail "another theme should not fail:\n$out"
grep -q 'set to the "breeze" theme' <<<"$out" || fail "another theme was not reported:\n$out"

# Selected, but without the greeter environment the kernel and battery readouts
# are silently empty -- worth saying, since nothing else shows it.
printf '[Theme]\nCurrent=c7shell\n' > "$root/etc/sddm.conf.d/10-c7shell.conf"
rm -f "$root/etc/sddm.conf"
out=$(run 2>&1) || fail "a selected theme should not fail:\n$out"
grep -q 'uses the c7shell greeter theme' <<<"$out" || fail "the selection was not recognised:\n$out"
grep -q 'QML_XHR_ALLOW_FILE_READ' <<<"$out" || fail "the missing greeter env was not reported:\n$out"

printf '[Theme]\nCurrent=c7shell\n\n[General]\nGreeterEnvironment=QML_XHR_ALLOW_FILE_READ=1\n' \
  > "$root/etc/sddm.conf.d/10-c7shell.conf"
out=$(run 2>&1) || fail "a fully configured greeter should not fail:\n$out"
grep -q 'may read /proc' <<<"$out" || fail "the greeter env was not recognised:\n$out"
grep -q 'greeter binary sddm-greeter-qt6 runs' <<<"$out" || fail "the greeter binary was not checked:\n$out"

# The black-screen case, and the reason this is checked at all: sddm builds the
# greeter path as sddm-greeter + (QtVersion ? "-qt<n>" : ""), so a theme that
# declares nothing gets handed to the Qt5 greeter -- present on Arch, but its
# Qt5 libraries are only an optdepend of sddm. It exits 127 and the login screen
# is black, with the reason only in sddm's journal. A failure, not a warning:
# this machine will not let anyone in.
printf '[SddmGreeterTheme]\nName=c7shell\nMainScript=Main.qml\n' > "$theme_meta"
rc=0; out=$(run 2>&1) || rc=$?
((rc == 1)) || fail "a greeter binary that is not installed should fail, got exit $rc:\n$out"
grep -q 'black screen' <<<"$out" || fail "the black screen was not predicted:\n$out"

# Same, for a binary that is there but cannot load its libraries
: > "$root/usr/bin/sddm-greeter"; chmod +x "$root/usr/bin/sddm-greeter"
printf '#!/bin/sh\necho "\tlibQt5Quick.so.5 => not found"\n' > "$bin/ldd"; chmod +x "$bin/ldd"
rc=0; out=$(run 2>&1) || rc=$?
((rc == 1)) || fail "an unloadable greeter binary should fail, got exit $rc:\n$out"
grep -q 'cannot start' <<<"$out" || fail "the unloadable binary was not reported:\n$out"
grep -q 'declares no QtVersion' <<<"$out" || fail "the missing QtVersion was not named:\n$out"

printf '[SddmGreeterTheme]\nName=c7shell\nQtVersion=6\nMainScript=Main.qml\n' > "$theme_meta"
printf '#!/bin/sh\nexit 0\n' > "$bin/ldd"; chmod +x "$bin/ldd"

# --- the optional-package picker -------------------------------------------
# It needs a terminal to prompt on, so drive it through a pty with `script`.
# pacman is a stub that records what it was asked to install.
log=$tmp/pacman.log
printf '#!/bin/sh\necho "$@" >> "%s"\n' "$log" > "$bin/pacman"
chmod +x "$bin/pacman"
printf '#!/bin/sh\nexec "$@"\n' > "$bin/sudo"   # run the command as ourselves
chmod +x "$bin/sudo"
for helper in script sed; do ln -s "$(command -v "$helper")" "$bin/$helper"; done

# Pin the offer list: dolphin present, kitty absent so 1) is kitty, and
# pam_kwallet_init removed so the one file-kind entry is offered too (last).
stub dolphin
rm "$root/usr/lib/pam_kwallet_init"

# pick <answer> -> what the picker asked pacman to install
pick() {
  : > "$log"
  env -i PATH="$bin" HOME="$tmp" TERM=dumb \
    C7SHELL_ROOT="$root" C7SHELL_SHARE="$tmp/share" XDG_CONFIG_HOME="$conf" \
    /usr/bin/script -qec "/usr/bin/bash $doctor --optional --quiet" /dev/null <<<"$1" \
    > "$tmp/pick.out" 2>&1 || true
  tr -d '\r' < "$log"
}

out=$(pick '')
[[ -z $out ]] || fail "an empty answer installed something: $out"
grep -q 'nothing selected' "$tmp/pick.out" || fail "empty answer not acknowledged:\n$(cat "$tmp/pick.out")"

out=$(pick 1)
[[ $out == '-S --needed -- kitty' ]] || fail "picking 1 should install kitty, got: $out"

out=$(pick '1 3')
[[ $out == '-S --needed -- kitty ddcutil' ]] || fail "picking '1 3' installed: $out"

out=$(pick '1-3')
[[ $out == '-S --needed -- kitty hyprlauncher ddcutil' ]] || fail "the range 1-3 installed: $out"

# a number covered twice is not an error and is not installed twice
out=$(pick '1 1-2')
[[ $out == '-S --needed -- kitty hyprlauncher' ]] || fail "duplicate selection installed: $out"

# dolphin alone would ignore the palette, so its companions come with it
rm "$bin/dolphin"
: > "$log"
out=$(pick 2)   # 1 = kitty, 2 = dolphin now that it is absent again
[[ $out == *dolphin* ]] || fail "picking dolphin did not install it: $out"
[[ $out == *plasma-integration*breeze*breeze-icons* ]] \
  || fail "dolphin's companions were not installed with it: $out"
grep -q 'plasma-integration breeze breeze-icons' "$tmp/pick.out" \
  || fail "the offer did not mention the companions:\n$(cat "$tmp/pick.out")"
# and they are not offered as entries of their own
grep -qE '^ +[0-9]+\) plasma-integration' "$tmp/pick.out" \
  && fail "plasma-integration was offered as its own entry:\n$(cat "$tmp/pick.out")"
stub dolphin

out=$(pick a)
[[ $out == *kitty*kwallet* ]] || fail "'a' should install every offered package, got: $out"

out=$(pick 99)
[[ -z $out ]] || fail "an out-of-range answer installed something: $out"
grep -q 'out of range' "$tmp/pick.out" || fail "no out-of-range complaint:\n$(cat "$tmp/pick.out")"

out=$(pick 'nope')
[[ -z $out ]] || fail "a non-numeric answer installed something: $out"
grep -q 'not a number' "$tmp/pick.out" || fail "no complaint about garbage input:\n$(cat "$tmp/pick.out")"

# A plugin missing while the app that needs it is installed has to be offered on
# its own: the companion route through the dolphin entry can never fire, because
# dolphin is not in the offer list at all. Kept last -- an extra entry here would
# renumber the picks asserted above.
mv "$root/usr/lib/qt6/plugins/platformthemes/KDEPlasmaPlatformTheme6.so" "$tmp/theme-gone2"
out=$(pick a)
[[ $out == *plasma-integration* ]] \
  || fail "a missing plugin was not offered where the app is already installed: $out"
grep -q 'plasma-integration' "$tmp/pick.out" \
  || fail "the offer did not list plasma-integration:\n$(cat "$tmp/pick.out")"
mv "$tmp/theme-gone2" "$root/usr/lib/qt6/plugins/platformthemes/KDEPlasmaPlatformTheme6.so"
: > "$log"   # the cases below assert on an empty log

# without a terminal the picker says so instead of hanging on a read
out=$(run --optional 2>&1 </dev/null || true)
grep -q 'no terminal to ask on' <<<"$out" || fail "no tty: expected a note, got:\n$out"
[[ ! -s $log ]] || fail "the picker installed something with no terminal: $(cat "$log")"

# and it never runs unless asked
: > "$log"
run --quiet >/dev/null 2>&1 || true
[[ ! -s $log ]] || fail "the picker ran without --optional: $(cat "$log")"

# --- a broken AUR helper is named, with the reason -------------------------
# `paru: libalpm.so.15 missing` names a library, never the pacman upgrade that
# removed it, so the fix (rebuild the source package) is not guessable from the
# error. An unusable helper is a warning, not a failure: the session runs fine.
printf '#!/bin/sh\necho "paru: error while loading shared libraries: libalpm.so.15: cannot open shared object file: No such file or directory" >&2\nexit 127\n' > "$bin/paru"
chmod +x "$bin/paru"
out=$(run 2>&1 || true)
grep -q 'paru is broken' <<<"$out" || fail "a broken paru was not reported:\n$out"
grep -q 'libalpm.so.15' <<<"$out" || fail "the reported error lost the library name:\n$out"
grep -q 'aur.archlinux.org/paru.git' <<<"$out" || fail "no fix was given for a broken paru:\n$out"
run >/dev/null 2>&1 || fail 'a broken AUR helper failed the doctor instead of warning'

printf '#!/bin/sh\ncase $1 in --version) echo "paru v2.1.0"; exit 0 ;; esac\n' > "$bin/paru"
out=$(run 2>&1 || true)
grep -q 'paru runs' <<<"$out" || fail "a working paru was not reported ok:\n$out"
rm -f "$bin/paru"

echo 'PASS: c7shell-doctor'
