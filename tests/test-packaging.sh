#!/usr/bin/env bash
# Self-check for PKGBUILD's package(). Run it directly: tests/test-packaging.sh
#
# Every program in bin/ has to be named in package() or it is simply not in the
# package -- and nothing else notices. The scripts are found by name on PATH
# (hyprlock.conf calls c7shell-lock-info, binds.lua calls c7shell-lock), so a
# missing install line produces no error anywhere: the config asks for a command
# that does not exist and the caller gets silence. That is how the lock screen
# shipped once with its keybind pointing at a binary the package never
# installed, which meant nothing locked at all.
set -euo pipefail

# shellcheck source=fixtures/harness.sh
. "$(dirname -- "$0")/fixtures/harness.sh"
root=$repo
pkgbuild=$root/PKGBUILD

[[ -f $pkgbuild ]] || fail 'PKGBUILD is missing'

missing=()
for prog in "$root"/bin/*; do
  [[ -f $prog ]] || continue
  name=${prog##*/}
  # The literal install line, not just the name: a mention in a comment is not
  # a file in the package.
  grep -qF "install -Dm755 bin/$name " "$pkgbuild" || missing+=("$name")
done

if ((${#missing[@]})); then
  fail "package() never installs: ${missing[*]}
these are called by name on PATH, so the only symptom is the caller silently
doing nothing. Add an install -Dm755 line for each."
fi

# The reverse: a line naming a program that no longer exists fails the build
# outright, which is louder but still worth catching before makepkg does.
while read -r name; do
  [[ -f $root/bin/$name ]] || fail "package() installs bin/$name, which does not exist"
done < <(grep -oE 'install -Dm755 bin/[A-Za-z0-9._-]+' "$pkgbuild" | sed 's|.*bin/||')

# Executability travels into the package via install -m755, but a script that is
# not executable in the tree cannot be run from a checkout either -- and that is
# how the tests and c7shell-upgrade's own hooks invoke them.
for prog in "$root"/bin/*; do
  [[ -f $prog ]] || continue
  [[ -x $prog ]] || fail "bin/${prog##*/} is not executable"
done

# --------------------------------------------------------------------------
# A library a bin/ script sources is not a program, so the loop above does not
# see it -- and an uninstalled one is worse than a missing program: the source
# fails, `set -e` ends the run, and the user gets a line number instead of a
# reason. share/c7shell-sddm.sh is the first of these; the check is general so
# the second one cannot arrive unnoticed.
# --------------------------------------------------------------------------
while read -r lib; do
  grep -qE "install -Dm[0-9]+ share/$lib " "$pkgbuild" \
    || fail "bin/ sources share/$lib, which package() never installs.
An installed script would die on the source with no explanation of what is gone."
done < <(grep -hoE 'c7shell-[A-Za-z0-9._-]+\.sh' "$root"/bin/* | sort -u)

# And it has to land where the scripts look for it. The loader in each of them
# falls back to one hardcoded directory, so package() putting the file anywhere
# else is the same failure with an install line in front of it.
while read -r dir; do
  grep -qE "install -Dm[0-9]+ share/[A-Za-z0-9._-]+ \"\\\$pkgdir$dir/" "$pkgbuild" \
    || fail "the bin/ scripts fall back to $dir for their shared library, and
package() installs nothing there."
done < <(grep -hoE '_c7lib=/usr/lib/[A-Za-z0-9._-]+' "$root"/bin/* | sed 's/.*=//' | sort -u)

# --------------------------------------------------------------------------
# The C7 plugin. The shell imports C7, so a package without the module is a
# shell that fails to load, and a check() that lets a plugin test fail ships
# a module nobody tested. build() and check() run here as makepkg runs them
# (sourced, under errexit), against stub cmake, ctest and lua that record
# their arguments.
# --------------------------------------------------------------------------
mktmp
fake=$tmp/fake
mkdir -p "$fake/bin" "$fake/src/c7shell/tests" "$fake/src/c7shell/hypr"
for tool in cmake ctest lua; do
  printf '#!/bin/sh\necho "%s $*" >>"%s/calls"\nexit "${STUB_RC_%s:-0}"\n' \
    "$tool" "$fake" "$tool" >"$fake/bin/$tool"
  chmod +x "$fake/bin/$tool"
done
printf '#!/bin/sh\nexit 0\n' >"$fake/src/c7shell/tests/ok.sh"
chmod +x "$fake/src/c7shell/tests/ok.sh"

# run_fn FN [VAR=VALUE...] -- run PKGBUILD's FN in the fake tree; sets `rc`.
run_fn() {
  local fn=$1
  shift
  : >"$fake/calls"
  rc=0
  env "$@" PATH="$fake/bin:$PATH" srcdir="$fake/src" pkgdir="$fake/pkg" \
    bash -ec '. "$1"; "$2"' _ "$pkgbuild" "$fn" >/dev/null 2>&1 || rc=$?
}

(. "$pkgbuild"; [[ " ${arch[*]} " != *' any '* ]]) \
  || fail "PKGBUILD says arch=any, but the package carries a compiled C7 plugin"
(. "$pkgbuild"; [[ " ${makedepends[*]} " == *' cmake '* ]]) \
  || fail "makedepends lacks cmake, which build() needs for the C7 plugin"

run_fn build
((rc == 0)) || fail "build() failed against stub tools (exit $rc)"
grep -qE '^cmake .*-S plugin -B build( |$)' "$fake/calls" \
  || fail "build() does not configure plugin/ into build/:\n$(cat "$fake/calls")"
grep -qE '^cmake --build build( |$)' "$fake/calls" \
  || fail "build() does not build the plugin:\n$(cat "$fake/calls")"

run_fn check
((rc == 0)) || fail "check() failed with every stub passing (exit $rc)"
grep -qE '^ctest .*--test-dir build( |$)' "$fake/calls" \
  || fail "check() does not run the plugin's ctest suite:\n$(cat "$fake/calls")"
run_fn check STUB_RC_ctest=1
((rc != 0)) || fail "check() passed while a plugin test failed"

grep -qF 'DESTDIR="$pkgdir" cmake --install build' "$pkgbuild" \
  || fail "package() never installs the C7 plugin (DESTDIR=\"\$pkgdir\" cmake --install build)"

printf 'PASS: packaging (%s programs in bin/)\n' "$(find "$root/bin" -maxdepth 1 -type f | wc -l)"
