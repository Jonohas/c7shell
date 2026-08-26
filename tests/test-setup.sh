#!/usr/bin/env bash
# Self-check for bin/gambleland-setup. Run it directly: tests/test-setup.sh
set -euo pipefail

here=$(cd -- "$(dirname -- "$0")" && pwd)
setup=$here/../bin/gambleland-setup
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT

export GAMBLELAND_SHARE=$tmp/share
export XDG_CONFIG_HOME=$tmp/conf
mkdir -p "$GAMBLELAND_SHARE"/{hypr,quickshell}
echo v1 > "$GAMBLELAND_SHARE/hypr/hyprland.lua"
echo v1 > "$GAMBLELAND_SHARE/quickshell/shell.qml"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

# dry-run changes nothing
"$setup" --dry-run >/dev/null
[[ ! -e $XDG_CONFIG_HOME/hypr ]] || fail '--dry-run created files'

# fresh install copies both parts
"$setup" >/dev/null
[[ $(cat "$XDG_CONFIG_HOME/hypr/hyprland.lua") == v1 ]] || fail 'hypr not installed'
[[ $(cat "$XDG_CONFIG_HOME/quickshell/shell.qml") == v1 ]] || fail 'quickshell not installed'

# second run without --force refuses, exit 3, leaves local edits alone
echo mine > "$XDG_CONFIG_HOME/hypr/hyprland.lua"
echo v2 > "$GAMBLELAND_SHARE/hypr/hyprland.lua"
rc=0; "$setup" >/dev/null 2>&1 || rc=$?
((rc == 3)) || fail "expected exit 3 on existing target, got $rc"
[[ $(cat "$XDG_CONFIG_HOME/hypr/hyprland.lua") == mine ]] || fail 'clobbered an existing config without --force'

# --force replaces and keeps a backup holding the old content
"$setup" --force >/dev/null
[[ $(cat "$XDG_CONFIG_HOME/hypr/hyprland.lua") == v2 ]] || fail '--force did not update'
backup=$(echo "$XDG_CONFIG_HOME"/hypr.bak-*)
[[ -d $backup && $(cat "$backup/hyprland.lua") == mine ]] || fail 'backup missing or wrong'

# missing share tree is an error, not a silent success
GAMBLELAND_SHARE=$tmp/nope rc=0
rc=0; GAMBLELAND_SHARE=$tmp/nope "$setup" >/dev/null 2>&1 || rc=$?
((rc == 1)) || fail "expected exit 1 for missing share dir, got $rc"

echo 'PASS: gambleland-setup'
