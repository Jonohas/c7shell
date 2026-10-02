#!/usr/bin/env bash
# Proves tests/test-native-boundary.sh catches what it claims to. Run it
# directly: tests/test-native-boundary-selftest.sh
#
# Each case copies tests/ and the shell into a scratch tree, plants one
# violation, and runs the copied boundary test there. The harness derives the
# repository root from its own path, so the copy checks the copy and never the
# real tree. A case passes only if the boundary test exits non-zero AND names
# the planted file, so a test that fails for some unrelated reason does not
# count as catching it.
set -euo pipefail

# shellcheck source=fixtures/harness.sh
. "$(dirname -- "$0")/fixtures/harness.sh"

[[ -x $here/test-native-boundary.sh ]] || fail "tests/test-native-boundary.sh is missing"

mktmp

# fresh -- a pristine copy of the tree under $tmp/<name>; prints its root.
fresh() {
  local root=$tmp/$1
  mkdir -p "$root/quickshell"
  cp -r "$here" "$root/tests"
  cp -r "$src" "$root/quickshell/c7shell"
  printf '%s' "$root"
}

# expect_fail ROOT NEEDLE -- the boundary test in ROOT fails and mentions NEEDLE.
expect_fail() {
  local root=$1 needle=$2 out
  if out=$("$root/tests/test-native-boundary.sh" 2>&1); then
    fail "boundary test passed but should have caught: $needle\n$out"
  fi
  grep -qF -- "$needle" <<<"$out" \
    || fail "boundary test failed without naming $needle:\n$out"
}

# The clean tree passes, with all three checks reporting.
out=$("$here/test-native-boundary.sh" 2>&1) || fail "boundary test fails on the clean tree:\n$out"
[[ $(grep -c '^PASS: ' <<<"$out") -eq 3 ]] || fail "expected three PASS lines:\n$out"

# 1. A new Quickshell integration import.
r=$(fresh imports)
printf 'import Quickshell.Services.Pipewire\nimport QtQuick\nItem {}\n' \
  >"$r/quickshell/c7shell/Modules/Bar/PlantedImport.qml"
expect_fail "$r" "Modules/Bar/PlantedImport.qml Quickshell.Services.Pipewire"

# 2. A new process-spawning QML file (a program that is not on the plumbing list).
r=$(fresh spawners)
printf 'import Quickshell.Io\nimport QtQuick\nItem { Process { command: ["grim"] } }\n' \
  >"$r/quickshell/c7shell/Modules/Bar/PlantedSpawn.qml"
expect_fail "$r" "Modules/Bar/PlantedSpawn.qml"

# 3. A new plumbing call, in a file that already starts processes, so only the
#    plumbing check can catch it.
r=$(fresh plumbing)
printf '\n// planted\nItem { Component.onCompleted: p.exec(["nmcli", "radio"]) }\n' \
  >>"$r/quickshell/c7shell/Services/UpdatesService.qml"
expect_fail "$r" "Services/UpdatesService.qml nmcli"

# 4. A stale debt entry: remove a debt use without deleting its line.
r=$(fresh stale)
sed -i 's/"notify-send", "-a"/"not-a-plumbing-call", "-a"/' \
  "$r/quickshell/c7shell/Services/NotifServer.qml"
grep -q 'not-a-plumbing-call' "$r/quickshell/c7shell/Services/NotifServer.qml" \
  || fail "the stale-entry case no longer plants anything; update the sed above"
expect_fail "$r" "Services/NotifServer.qml notify-send"

echo "PASS: native boundary self-test (clean tree + 4 planted violations)"
