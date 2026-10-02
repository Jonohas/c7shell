#!/usr/bin/env bash
# The C7 plugin builds, its tests pass, and its layout holds. Run it directly:
# tests/test-c7-plugin.sh
#
# Four checks, in order of what needs the least:
#   1. git does not ignore plugin sources (makepkg's unanchored `src/` would)
#   2. no file under plugin/lib/ includes a QML, Quick or Quickshell header, or
#      links a QML or Quick target -- the libraries are plain Qt clients
#   3. a clean configure, build and ctest of plugin/ passes
#   4. the module test fails once the built C7 module is gone, so it cannot
#      pass without loading the module
# Checks 3 and 4 skip without cmake; 1 and 2 always run.
set -euo pipefail
shopt -s inherit_errexit

# shellcheck source=fixtures/harness.sh
. "$(dirname -- "$0")/fixtures/harness.sh"

plugin=$repo/plugin
[[ -f $plugin/CMakeLists.txt ]] || fail "plugin/CMakeLists.txt is missing"
[[ -d $plugin/lib ]] || fail "plugin/lib is missing"

# 1. ignore rules --------------------------------------------------------------
for p in plugin/src/x.cpp plugin/lib/x/x.cpp plugin/tests/x.cpp; do
  if git -C "$repo" check-ignore -q --no-index "$p"; then
    fail "git ignores $p: $(git -C "$repo" check-ignore -v --no-index "$p")"
  fi
done
echo "PASS: plugin sources are not ignored"

# 2. plain libraries -----------------------------------------------------------
# lib_violations DIR -- print every QML, Quick or Quickshell include or link in DIR.
lib_violations() {
  local rc=0
  grep -RnE \
    -e '^[[:space:]]*#[[:space:]]*include[[:space:]]*[<"](QtQml|QtQuick|Quickshell|quickshell|QQml|QQuick|qqml|qquick|QJSEngine|QJSValue|qjs)' \
    -e 'Qt6?::(Qml|Quick)' \
    "$1" || rc=$?
  ((rc <= 1)) || fail "grep exited $rc while scanning $1"
}

# The check must see what it forbids, or an empty result proves nothing.
mktmp
mkdir -p "$tmp/lib/x"
printf '#include <QtQml/QQmlEngine>\n' >"$tmp/lib/x/a.h"
printf '  # include "qqmlengine.h"\n' >"$tmp/lib/x/b.cpp"
printf 'target_link_libraries(x PRIVATE Qt6::Quick)\n' >"$tmp/lib/x/CMakeLists.txt"
[[ $(lib_violations "$tmp/lib" | wc -l) -eq 3 ]] \
  || fail "the plugin/lib check missed a planted include or link:\n$(lib_violations "$tmp/lib")"

hits=$(lib_violations "$plugin/lib")
[[ -z $hits ]] || fail "plugin/lib must not depend on QML, Quick or Quickshell:\n$hits"
echo "PASS: plugin/lib is plain C++"

# 3. build and test ------------------------------------------------------------
if ! command -v cmake >/dev/null; then
  echo 'SKIP: cmake not installed (package: cmake); build and ctest not run'
  exit 0
fi
gen=()
if command -v ninja >/dev/null; then gen=(-G Ninja); fi
build=$tmp/build
log=$tmp/log
cmake -S "$plugin" -B "$build" "${gen[@]}" >"$log" 2>&1 || fail "configure failed:\n$(cat "$log")"
cmake --build "$build" >"$log" 2>&1 || fail "build failed:\n$(cat "$log")"
ctest --test-dir "$build" --output-on-failure --no-tests=error >"$log" 2>&1 \
  || fail "ctest failed:\n$(cat "$log")"
echo "PASS: plugin builds and ctest passes"

# 4. the module test needs the module -----------------------------------------
[[ -f $build/qml/C7/qmldir ]] || fail "the build left no C7 module at qml/C7"
rm -rf "$build/qml/C7"
if ctest --test-dir "$build" -R '^tst_module$' --no-tests=error >"$log" 2>&1; then
  fail "tst_module passed with the C7 module deleted:\n$(cat "$log")"
fi
echo "PASS: tst_module fails without the C7 module"
