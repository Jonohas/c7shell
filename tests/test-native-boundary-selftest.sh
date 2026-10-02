#!/usr/bin/env bash
# Proves tests/test-native-boundary.sh catches what it claims to. Run it
# directly: tests/test-native-boundary-selftest.sh
#
# Each case copies tests/ and the shell into a scratch tree, plants one thing,
# and runs the copied boundary test there. The harness derives the repository
# root from its own path, so the copy checks the copy and never the real tree.
#
# A failing case must exit non-zero, report the check it targets ("FAIL:
# <check>:"), and name what was planted, so a failure from some other check
# never counts as the targeted one catching it. Cases plant their own files, or
# their own entries in the copied test's tables, so paying off real debt never
# breaks this self-test.
set -euo pipefail
shopt -s inherit_errexit

# shellcheck source=fixtures/harness.sh
. "$(dirname -- "$0")/fixtures/harness.sh"

[[ -x $here/test-native-boundary.sh ]] || fail "tests/test-native-boundary.sh is missing"

mktmp

# fresh NAME -- set `r` to a pristine copy of the tree under $tmp/NAME.
fresh() {
  r=$tmp/$1
  mkdir -p "$r/quickshell" && cp -r "$here" "$r/tests" && cp -r "$src" "$r/quickshell/c7shell" \
    || fail "could not build the scratch tree $r"
}

# plant FILE TEXT -- write TEXT to FILE (relative to the copied shell).
plant() { printf '%b' "$2" >"$r/quickshell/c7shell/$1" || fail "could not plant $1"; }

# add_entry TABLE ENTRY -- add ENTRY as the first row of TABLE in the copied test.
add_entry() {
  local t=$r/tests/test-native-boundary.sh
  grep -q "^$1=($" "$t" || fail "the copied test has no '$1=(' table"
  sed -i "/^$1=($/a\\  '$2'" "$t"
}

# run_copy -- run the copied boundary test; sets `out` and `rc`.
run_copy() { rc=0; out=$("$r/tests/test-native-boundary.sh" 2>&1) || rc=$?; }

# expect_fail CHECK NEEDLE -- the copied test fails in CHECK and names NEEDLE.
expect_fail() {
  run_copy
  [[ $rc -ne 0 ]] || fail "boundary test passed but $1 should have caught: $2\n$out"
  grep -q "^FAIL: $1:" <<<"$out" || fail "expected a FAIL from '$1' for $2, got:\n$out"
  grep -qF -- "$2" <<<"$out" || fail "'$1' failed without naming $2:\n$out"
}

# expect_pass -- the copied test passes with all three checks reporting.
expect_pass() {
  run_copy
  [[ $rc -eq 0 ]] || fail "boundary test failed but should pass:\n$out"
  [[ $(grep -c '^PASS: ' <<<"$out") -eq 3 ]] || fail "expected three PASS lines:\n$out"
}

n=0
case_() { n=$((n + 1)); fresh "case$n"; }

# The clean tree passes.
case_; expect_pass

# The tree under test must exist and contain QML; an empty check is no check.
case_; rm -rf "$r/quickshell/c7shell"
run_copy; [[ $rc -ne 0 ]] && grep -q 'shell source tree' <<<"$out" \
  || fail "a missing shell tree did not fail:\n$out"
case_; find "$r/quickshell/c7shell" -name '*.qml' -delete
run_copy; [[ $rc -ne 0 ]] && grep -q 'no QML files' <<<"$out" \
  || fail "a tree without QML did not fail:\n$out"

# A grep error is a failure, not "no matches" (a dangling symlink cannot be read).
case_; ln -s does-not-exist "$r/quickshell/c7shell/Modules/Bar/Dangling.qml"
run_copy; [[ $rc -ne 0 ]] || fail "a grep error passed as no matches:\n$out"

# --- imports ---------------------------------------------------------------
case_; plant Modules/Bar/PlantedImport.qml 'import Quickshell.Services.Pipewire\nimport QtQuick\nItem {}\n'
expect_fail imports "Modules/Bar/PlantedImport.qml Quickshell.Services.Pipewire"
case_; plant Modules/Bar/PlantedImport.qml '  import Quickshell.Hyprland 0.1 as H\nimport QtQuick\nItem {}\n'
expect_fail imports "Modules/Bar/PlantedImport.qml Quickshell.Hyprland"

# --- spawners --------------------------------------------------------------
# grim is not on the plumbing list, so only the spawners check can see it.
case_; plant Modules/Bar/PlantedSpawn.qml 'import Quickshell.Io\nimport QtQuick\nItem { Process { command: ["grim"] } }\n'
expect_fail spawners "Modules/Bar/PlantedSpawn.qml"
case_; plant Modules/Bar/PlantedSpawn.qml 'import Quickshell.Io\nimport QtQuick\nItem {\n  Process\n  {\n    command: ["grim"]\n  }\n}\n'
expect_fail spawners "Modules/Bar/PlantedSpawn.qml"
case_; plant Modules/Bar/PlantedSpawn.qml 'import Quickshell\nimport QtQuick\nItem { Component.onCompleted: Quickshell.execDetached(["grim"]) }\n'
expect_fail spawners "Modules/Bar/PlantedSpawn.qml"

# --- plumbing --------------------------------------------------------------
# `p.exec(` is not a spawner pattern, so these isolate the plumbing check.
for argv in '["nmcli", "radio"]' "['nmcli', 'radio']" '["/usr/bin/nmcli"]' '[\n    "nmcli",\n    "radio"\n  ]'; do
  case_; plant Modules/Bar/PlantedCall.qml "import QtQuick\nItem { Component.onCompleted: p.exec($argv) }\n"
  expect_fail plumbing "Modules/Bar/PlantedCall.qml nmcli"
done
# An allowed pair does not cover another program in the same file.
case_; printf '\nItem { Component.onCompleted: p.exec(["rfkill", "list"]) }\n' \
  >>"$r/quickshell/c7shell/Modules/Launcher/providers/AppsProvider.qml"
expect_fail plumbing "Modules/Launcher/providers/AppsProvider.qml rfkill"
# Program names are matched whole: "shell" is not sh, "lsblk" is not ls.
case_; plant Modules/Bar/PlantedCall.qml 'import QtQuick\nItem { Component.onCompleted: p.exec(["shell"]); property var x: ["lsblk"] }\n'
expect_pass

# --- stale entries, one per table ------------------------------------------
case_; add_entry debt 'Services/NoSuchFile.qml nmcli'
expect_fail plumbing "Services/NoSuchFile.qml nmcli"
case_; add_entry allowed 'Services/NoSuchFile.qml sh'
expect_fail plumbing "Services/NoSuchFile.qml sh"
case_; add_entry import_debt 'Services/NoSuchFile.qml Quickshell.Hyprland'
expect_fail imports "Services/NoSuchFile.qml Quickshell.Hyprland"
case_; add_entry spawn_debt 'Services/NoSuchFile.qml'
expect_fail spawners "Services/NoSuchFile.qml"

echo "PASS: native boundary self-test ($n cases)"
