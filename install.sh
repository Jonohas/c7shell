#!/usr/bin/env bash
# Build and install the c7shell package.
#
# makepkg refuses to start when the base-devel build tools are absent
# ("Cannot find the fakeroot binary", "Cannot find the debugedit binary"),
# and it aborts before the PKGBUILD is ever read -- so the PKGBUILD itself
# cannot pull them in. This wrapper installs them first, then runs makepkg.
set -euo pipefail

# One representative command per base-devel package makepkg insists on.
# debugedit only ships in its own package, which is why a machine that has
# an older base-devel installed can still be missing it.
declare -A tools=(
  [fakeroot]=fakeroot
  [debugedit]=debugedit
  [make]=make
  [gcc]=gcc
  [patch]=patch
  [bsdtar]=libarchive
  [pkg-config]=pkgconf
)

usage() {
  cat <<USAGE
usage: ./install.sh [makepkg options...]

Installs the base-devel tools makepkg needs (fakeroot, debugedit, ...) if any
are missing, then runs: makepkg -si <makepkg options>

env: C7SHELL_SKIP_DEPS=1  don't touch base-devel, just run makepkg
USAGE
}

case ${1:-} in -h|--help) usage; exit 0 ;; esac

command -v makepkg >/dev/null || {
  echo "install.sh: no makepkg found -- this package builds on Arch-based systems only" >&2
  exit 1
}

if ((EUID == 0)); then
  echo "install.sh: run this as your own user; makepkg refuses to run as root" >&2
  exit 2
fi

as_root() {
  if command -v sudo >/dev/null; then sudo "$@"
  elif command -v doas >/dev/null; then doas "$@"
  else
    printf 'install.sh: need root to install %s, but neither sudo nor doas is present.\n' "$*" >&2
    printf '           run as root:  pacman -S --needed base-devel\n' >&2
    exit 1
  fi
}

if [[ -z ${C7SHELL_SKIP_DEPS:-} ]]; then
  missing=()
  for cmd in "${!tools[@]}"; do
    command -v "$cmd" >/dev/null || missing+=("${tools[$cmd]}")
  done

  if ((${#missing[@]})); then
    printf 'missing build tools: %s\n' "${missing[*]}"
    echo 'installing base-devel (makepkg needs it before it will run)...'
    as_root pacman -S --needed base-devel
    # base-devel is a package group; on an incomplete install pacman may have
    # left the specific packages out, so name them explicitly as well.
    as_root pacman -S --needed -- "${missing[@]}"
  fi

  for cmd in "${!tools[@]}"; do
    command -v "$cmd" >/dev/null || {
      printf 'install.sh: %s is still missing after installing base-devel\n' "$cmd" >&2
      exit 1
    }
  done
fi

exec makepkg -si "$@"
