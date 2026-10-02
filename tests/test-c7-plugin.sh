#!/usr/bin/env bash
# The C7 plugin builds, its tests pass, and its layout holds. Run it directly:
# tests/test-c7-plugin.sh
#
# Four checks, in order of what needs the least:
#   1. git ignores no file under plugin/ (makepkg's unanchored `src/` once did),
#      so a clean clone has every file this build reads; and it ignores /build/
#   2. no file under plugin/lib/ includes a QML, Quick or Quickshell header,
#      links a QML or Quick target, or declares a QML module -- the libraries
#      are plain Qt clients
#   3. a clean configure, build and ctest of plugin/ passes, and ctest runs
#      every test this script names
#   4. tst_module fails, for the missing module, once the built C7 module is gone
# Checks 3 and 4 skip without cmake or qt6-declarative; 1 and 2 always run.
set -euo pipefail
shopt -s inherit_errexit

# shellcheck source=fixtures/harness.sh
. "$(dirname -- "$0")/fixtures/harness.sh"

plugin=$repo/plugin
[[ -f $plugin/CMakeLists.txt ]] || fail "plugin/CMakeLists.txt is missing"
[[ -d $plugin/lib ]] || fail "plugin/lib is missing"

# 1. ignore rules --------------------------------------------------------------
# ignored PATH... -- print the paths the repository's own rules ignore. Host git
# config is shut out, so a personal excludesFile cannot fail or pass this.
ignored() {
  local rc=0
  printf '%s\n' "$@" \
    | GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
      git -C "$repo" check-ignore --no-index --stdin || rc=$?
  ((rc <= 1)) || fail "git check-ignore exited $rc in $repo"
}

mapfile -t files < <(cd "$repo" && find plugin -type f)
hits=$(ignored "${files[@]}" plugin/src/x.cpp plugin/lib/x/x.cpp plugin/tests/x.cpp)
[[ -z $hits ]] || fail "git ignores plugin sources, so a clean clone lacks them:\n$hits"
[[ -n $(ignored build/CMakeCache.txt) ]] || fail "git does not ignore /build/, the documented build directory"
echo "PASS: plugin sources are not ignored, /build/ is"

# 2. plain libraries -----------------------------------------------------------
# lib_violations DIR -- print every QML, Quick or Quickshell dependency in DIR.
lib_violations() {
  local rc=0
  grep -RnE \
    -e '^[[:space:]]*#[[:space:]]*include[[:space:]]*[<"](private/)?(QtQml|QtQuick|Quickshell|quickshell|QQml|QQuick|qqml|qquick|QJSEngine|QJSValue|qjs)' \
    -e 'Qt6?::(Qml|Quick)' \
    -e 'qt6?_add_qml_(module|plugin)' \
    "$1" || rc=$?
  ((rc <= 1)) || fail "grep exited $rc while scanning $1"
}

# The check must see each thing it forbids, or an empty result proves nothing.
mktmp
planted=(
  '#include <QtQml/QQmlEngine>'
  '#include <QtQuick/QQuickItem>'
  '  # include "qqmlengine.h"'
  '#include <QQuickWindow>'
  '#include <QJSValue>'
  '#include <private/qqmlengine_p.h>'
  '#include <Quickshell/x.hpp>'
  'target_link_libraries(x PRIVATE Qt6::Quick)'
  'target_link_libraries(x PRIVATE Qt::Qml)'
  'qt_add_qml_module(x URI X)'
  'qt6_add_qml_plugin(x)'
)
for line in "${planted[@]}"; do
  rm -rf "$tmp/lib" && mkdir -p "$tmp/lib/x"
  printf '%s\n' "$line" >"$tmp/lib/x/CMakeLists.txt"
  [[ -n $(lib_violations "$tmp/lib") ]] || fail "the plugin/lib check missed: $line"
done

hits=$(lib_violations "$plugin/lib")
[[ -z $hits ]] || fail "plugin/lib must not depend on QML, Quick or Quickshell:\n$hits"
echo "PASS: plugin/lib is plain C++"

# 3. build and test ------------------------------------------------------------
if ! command -v cmake >/dev/null; then
  echo 'SKIP: cmake not installed (package: cmake); build and ctest not run'
  exit 0
fi
need_qml6

gen=()
if command -v ninja >/dev/null; then gen=(-G Ninja); fi
build=$tmp/build
log=$tmp/log
# run_logged WHAT CMD... -- run CMD into $log; on failure show the log, then fail.
run_logged() {
  local what=$1
  shift
  "$@" >"$log" 2>&1 && return 0
  cat "$log" >&2
  fail "$what failed (log above)"
}
run_logged configure cmake -S "$plugin" -B "$build" "${gen[@]}"
run_logged build cmake --build "$build"

# --no-tests=error only needs one test, so name each one that must run.
run_logged 'ctest -N' ctest --test-dir "$build" -N
for t in tst_version tst_module; do
  grep -qE "Test +#[0-9]+: $t\$" "$log" || { cat "$log" >&2; fail "ctest does not run $t"; }
done
run_logged ctest ctest --test-dir "$build" --output-on-failure --no-tests=error
echo "PASS: plugin builds and ctest passes"

# 4. the module test needs the module -----------------------------------------
# Run the binary itself: through ctest, "no such test" and "test failed" share
# an exit code.
[[ -f $build/qml/C7/qmldir ]] || fail "the build left no C7 module at qml/C7"
[[ -x $build/tests/tst_module ]] || fail "the build left no tst_module binary"
rm -rf "$build/qml/C7"
rc=0
"$build/tests/tst_module" >"$log" 2>&1 || rc=$?
if ((rc != 1)) || ! grep -q 'module "C7" is not installed' "$log"; then
  cat "$log" >&2
  fail "tst_module exited $rc without the C7 module; it must fail for the missing module"
fi
echo "PASS: tst_module fails without the C7 module"
