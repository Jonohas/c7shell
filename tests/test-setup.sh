#!/usr/bin/env bash
# Self-check for bin/c7shell-setup. Run it directly: tests/test-setup.sh
set -euo pipefail

here=$(cd -- "$(dirname -- "$0")" && pwd)
setup=$here/../bin/c7shell-setup
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT

export C7SHELL_SHARE=$tmp/share
export XDG_CONFIG_HOME=$tmp/conf
# c7shell-setup records its manifest under $XDG_STATE_HOME, falling back to
# $HOME/.local/state. Without these two this test wrote its FIXTURE manifest
# -- five lines of "v1" hashes -- straight into the real ~/.local/state/c7shell
# of whoever ran it. The next c7shell-upgrade on that machine then found a
# manifest that knew nothing about any real file, concluded every shipped file
# had been locally edited, and parked a .new beside each one. That is a config
# half one version and half another, which for QML fails the whole load.
# HOME as well as the state dir, so nothing here can reach a real home at all.
export C7SHELL_STATE=$tmp/state
export XDG_STATE_HOME=$tmp/xdg-state
export XDG_DATA_HOME=$tmp/data
export HOME=$tmp/home
mkdir -p "$HOME"
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
[[ ! -e $XDG_DATA_HOME/c7shell/scripts ]] || fail '--dry-run created the script dir'

# fresh install copies both parts
"$setup" >/dev/null
[[ $(cat "$XDG_CONFIG_HOME/hypr/hyprland.lua") == v1 ]] || fail 'hypr not installed'
[[ $(cat "$XDG_CONFIG_HOME/quickshell/c7shell/shell.qml") == v1 ]] || fail 'quickshell not installed'
[[ $(cat "$XDG_CONFIG_HOME/xdg-desktop-portal/hyprland-portals.conf") == v1 ]] || fail 'portal config not installed'

# the launcher's action-script directory exists, so there is somewhere to drop
# one -- the provider shows nothing and says nothing when it is missing
[[ -d $XDG_DATA_HOME/c7shell/scripts ]] || fail 'the launcher script dir was not created'

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
echo mine > "$XDG_DATA_HOME/c7shell/scripts/mine.sh"
"$setup" --force >/dev/null
# the whole reason the scripts live outside the config tree: --force moves that
# tree aside, and a user's action scripts must not go with it
[[ $(cat "$XDG_DATA_HOME/c7shell/scripts/mine.sh") == mine ]] \
  || fail '--force lost a user action script'
[[ $(cat "$XDG_CONFIG_HOME/hypr/hyprland.lua") == v2 ]] || fail '--force did not update'
backup=$(echo "$XDG_CONFIG_HOME"/hypr.bak-*)
[[ -d $backup && $(cat "$backup/hyprland.lua") == mine ]] || fail 'backup missing or wrong'
[[ $(cat "$XDG_CONFIG_HOME/quickshell/notmine.qml") == other ]] \
  || fail '--force touched an unrelated quickshell config'

# missing share tree is an error, not a silent success
# (as a prefix on the command only -- `VAR=x rc=0` with no command to run is a
# plain assignment, and that line used to leave C7SHELL_SHARE pointing at a
# directory that does not exist for the whole rest of the file)
rc=0; C7SHELL_SHARE=$tmp/nope "$setup" >/dev/null 2>&1 || rc=$?
((rc == 1)) || fail "expected exit 1 for missing share dir, got $rc"


# --- an existing config still records a baseline --------------------------
# This is the case that broke a real machine. setup used to exit 3 the moment
# it skipped everything, BEFORE writing the manifest -- so the one situation
# that most needs a baseline (a config already there) was the only one that
# never got one. The next c7shell-upgrade then had nothing to compare against,
# treated every shipped file as locally edited, and parked a .new beside each
# one. That leaves a config half one version and half another, which for QML
# is not a cosmetic problem: imports resolve across the whole tree, so an old
# shell.qml next to a new module directory fails the entire load.
rm -rf "${C7SHELL_STATE:?}"
rc=0; out=$("$setup" 2>&1) || rc=$?
((rc == 3)) || fail "a second setup over an existing config should exit 3, got $rc:\n$out"
# Nothing was copied, so nothing may be claimed as ours -- guessing here is
# what would silently overwrite a real local edit on the next upgrade.
[[ -f $C7SHELL_STATE/manifest ]] \
  || fail "setup wrote no manifest at all when it skipped:\n$out"
[[ ! -s $C7SHELL_STATE/manifest ]] \
  || fail "setup claimed files it did not install:\n$(cat "$C7SHELL_STATE/manifest")"
# And it has to say what to do next, rather than one line on stderr that
# scrolls past.
grep -q -- '--force' <<<"$out" || fail "setup did not offer --force:\n$out"
grep -q 'c7shell-upgrade' <<<"$out" \
  || fail "setup did not point at the non-destructive way to update:\n$out"


# --- and none of the above escaped into a real home -----------------------
# The isolation above is the whole reason this file cannot damage the machine
# it runs on; assert it rather than trusting it.
[[ -d $tmp/state || -d $tmp/xdg-state ]] \
  || fail 'setup wrote no state anywhere -- the isolation may be pointing at a real home'
while read -r stray; do
  fail "a test artefact escaped the sandbox: $stray"
done < <(find "$HOME" -name manifest -newer "$tmp" 2>/dev/null | grep -v "^$tmp" || true)

echo 'PASS: c7shell-setup'
