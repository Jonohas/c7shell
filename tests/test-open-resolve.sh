#!/usr/bin/env bash
# Self-check for the capture toast's open/folder handler resolution. Run it
# directly: tests/test-open-resolve.sh
#
# The rule (issue #56): a handler configured in shell.json wins; else the first
# of a few common apps that is actually installed; else xdg-open. This runs the
# exact shell snippet CaptureService hands to sh -- extracted from the file, so
# a change to the logic that breaks a case shows up here rather than the next
# time someone screenshots and lands in the browser.
set -euo pipefail

here=$(cd -- "$(dirname -- "$0")" && pwd)
svc=$here/../quickshell/c7shell/Services/CaptureService.qml
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT

fail() { printf 'FAIL: %b\n' "$1" >&2; exit 1; }

# Pull the concatenated openScript literal out of the service. The block sits
# between `openScript:` and `function openArgv`, and only its four parts are
# single-quoted there (the candidate lists use double quotes).
script=$(python3 - "$svc" <<'PY'
import re, sys
t = open(sys.argv[1]).read()
i = t.index("openScript:")
seg = t[i:t.index("function openArgv")]
print("".join(re.findall(r"'([^']*)'", seg)), end="")
PY
)
[[ -n $script ]] || fail "could not extract openScript from CaptureService.qml"

# A stub that just announces which handler ran and on what target.
stub=$tmp/bin
mkdir -p "$stub"
mkstub() { printf '#!/bin/sh\necho "RAN %s %s"\n' "$1" '$1' > "$stub/$1"; chmod +x "$stub/$1"; }

# openArgv builds: sh -c SCRIPT sh <target> <configured> <candidates...>. Stub
# dir goes first on PATH so our fakes win; real sh/command stay reachable. The
# candidate names are deliberately not real apps, so a handler that happens to
# be installed on the test box cannot change the outcome.
run() { PATH="$stub:$PATH" sh -c "$script" sh "$@"; }

# 1. Configured handler wins over an installed candidate.
mkstub my-viewer; mkstub cand-a
out=$(run /shot.png my-viewer cand-a cand-b)
[[ $out == "RAN my-viewer /shot.png" ]] \
  || fail "configured handler ignored: got '$out'"

# 2. No config: first *installed* candidate in order, not first listed.
rm -f "$stub"/*
mkstub cand-b   # cand-a is listed first but absent
out=$(run /shot.png "" cand-a cand-b cand-c)
[[ $out == "RAN cand-b /shot.png" ]] \
  || fail "detection did not pick the first installed candidate: got '$out'"

# 3. No config, nothing installed: xdg-open is the last resort.
rm -f "$stub"/*
mkstub xdg-open
out=$(run /shot.png "" cand-a cand-b)
[[ $out == "RAN xdg-open /shot.png" ]] \
  || fail "fallback to xdg-open did not happen: got '$out'"

# --- static wiring: both toast buttons must route through the kinded queue ---
grep -q 'queueOpen(path, "file")' "$svc" \
  || fail "openFile no longer tags its queue entry as a file"
grep -q 'queueOpen(path.substring(0, path.lastIndexOf("/")), "folder")' "$svc" \
  || fail "openFolder no longer tags its queue entry as a folder"

store=$here/../quickshell/c7shell/Services/ShellStore.qml
grep -q 'property string fileManager' "$store" \
  && grep -q 'property string imageViewer' "$store" \
  || fail "ShellStore no longer declares the fileManager/imageViewer keys"

echo 'test-open-resolve.sh: all checks passed'
