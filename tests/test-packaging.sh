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

here=$(cd -- "$(dirname -- "$0")" && pwd)
root=$here/..
pkgbuild=$root/PKGBUILD

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

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

printf 'PASS: packaging (%s programs in bin/)\n' "$(find "$root/bin" -maxdepth 1 -type f | wc -l)"
