#!/usr/bin/env bash
# Self-check for bin/c7shell-setup. Run it directly: tests/test-setup.sh
set -euo pipefail

here=$(cd -- "$(dirname -- "$0")" && pwd)
setup=$here/../bin/c7shell-setup
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT

export C7SHELL_SHARE=$tmp/share
export XDG_CONFIG_HOME=$tmp/conf
mkdir -p "$C7SHELL_SHARE"/{hypr,quickshell/c7shell,xdg-desktop-portal}
echo v1 > "$C7SHELL_SHARE/hypr/hyprland.lua"
echo v1 > "$C7SHELL_SHARE/quickshell/c7shell/shell.qml"
echo v1 > "$C7SHELL_SHARE/xdg-desktop-portal/hyprland-portals.conf"
printf 'custom_picker_binary = $HOME/.config/quickshell/c7shell/bin/x.sh\n' \
  > "$C7SHELL_SHARE/hypr/xdph.conf"
# stands in for scripts/c7shell-theme-export.py: writes kdeglobals where the
# real one does, from the same env var
mkdir -p "$C7SHELL_SHARE/quickshell/c7shell/scripts"
cat > "$C7SHELL_SHARE/quickshell/c7shell/scripts/c7shell-theme-export.py" <<'PYEOF'
import os
conf = os.environ["XDG_CONFIG_HOME"]
open(f"{conf}/kdeglobals", "w").write("[General]\nColorScheme=C7Shell\n")
PYEOF

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

# dry-run changes nothing
"$setup" --dry-run >/dev/null
[[ ! -e $XDG_CONFIG_HOME/kdeglobals ]] || fail '--dry-run exported the palette'
[[ ! -e $XDG_CONFIG_HOME/hypr ]] || fail '--dry-run created files'

# fresh install copies both parts
"$setup" >/dev/null
[[ $(cat "$XDG_CONFIG_HOME/hypr/hyprland.lua") == v1 ]] || fail 'hypr not installed'
[[ $(cat "$XDG_CONFIG_HOME/quickshell/c7shell/shell.qml") == v1 ]] || fail 'quickshell not installed'
[[ $(cat "$XDG_CONFIG_HOME/xdg-desktop-portal/hyprland-portals.conf") == v1 ]] || fail 'portal config not installed'

# the palette is seeded, so Qt apps match without touching a setting first
grep -q 'ColorScheme=C7Shell' "$XDG_CONFIG_HOME/kdeglobals" \
  || fail 'kdeglobals was not seeded from the shipped exporter'

# the shell lands in its own named subfolder, never over a sibling config
echo other > "$XDG_CONFIG_HOME/quickshell/notmine.qml"

# the $HOME placeholder in xdph.conf is rewritten to the real config path
grep -qF "$XDG_CONFIG_HOME/quickshell/c7shell/bin/x.sh" "$XDG_CONFIG_HOME/hypr/xdph.conf" \
  || fail 'xdph picker path not rewritten'

# second run without --force refuses, exit 3, leaves local edits alone
echo mine > "$XDG_CONFIG_HOME/hypr/hyprland.lua"
echo v2 > "$C7SHELL_SHARE/hypr/hyprland.lua"
rc=0; "$setup" >/dev/null 2>&1 || rc=$?
((rc == 3)) || fail "expected exit 3 on existing target, got $rc"
[[ $(cat "$XDG_CONFIG_HOME/hypr/hyprland.lua") == mine ]] || fail 'clobbered an existing config without --force'

# --force replaces and keeps a backup holding the old content
"$setup" --force >/dev/null
[[ $(cat "$XDG_CONFIG_HOME/hypr/hyprland.lua") == v2 ]] || fail '--force did not update'
backup=$(echo "$XDG_CONFIG_HOME"/hypr.bak-*)
[[ -d $backup && $(cat "$backup/hyprland.lua") == mine ]] || fail 'backup missing or wrong'
[[ $(cat "$XDG_CONFIG_HOME/quickshell/notmine.qml") == other ]] \
  || fail '--force touched an unrelated quickshell config'

# missing share tree is an error, not a silent success
C7SHELL_SHARE=$tmp/nope rc=0
rc=0; C7SHELL_SHARE=$tmp/nope "$setup" >/dev/null 2>&1 || rc=$?
((rc == 1)) || fail "expected exit 1 for missing share dir, got $rc"

echo 'PASS: c7shell-setup'
