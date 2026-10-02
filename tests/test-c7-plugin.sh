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
#   4. `cmake --install` puts the whole module, and nothing else, in
#      usr/lib/qt6/qml/C7, and tst_module loads it from there with the build
#      tree's copy gone -- what PKGBUILD's package() ships
#   5. tst_module fails, for the missing module, once the built C7 module is gone
# Checks 3 to 5 skip without cmake or qt6-declarative; 1 and 2 always run.
set -euo pipefail
shopt -s inherit_errexit
# The module test reads this; one inherited from the caller must not choose
# which copy of C7 the build-tree checks load.
unset C7_QML_IMPORT_PATH

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

# Not process substitution: errexit cannot see a failing find inside one.
files=$(cd "$repo" && find plugin -type f)
mapfile -t files <<<"$files"
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
    -e '[Qq][Tt]6?_[Aa][Dd][Dd]_[Qq][Mm][Ll]_([Mm][Oo][Dd][Uu][Ll][Ee]|[Pp][Ll][Uu][Gg][Ii][Nn])' \
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
  'QT_ADD_QML_MODULE(x URI X)'
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
# Configured as PKGBUILD's build() does: check 4 installs what package() would.
run_logged configure cmake -S "$plugin" -B "$build" "${gen[@]}" -DCMAKE_INSTALL_PREFIX=/usr
run_logged build cmake --build "$build"

# --no-tests=error only needs one test, so name each one that must run.
run_logged 'ctest -N' ctest --test-dir "$build" -N
for t in tst_version tst_module; do
  grep -qE "Test +#[0-9]+: $t\$" "$log" || { cat "$log" >&2; fail "ctest does not run $t"; }
done
run_logged ctest ctest --test-dir "$build" --output-on-failure --no-tests=error
# PKGBUILD's check() runs ctest in whatever environment makepkg inherited, so
# an import path set there must not choose the copy of C7 under test.
C7_QML_IMPORT_PATH=$tmp/no-such-dir run_logged 'ctest with a stray C7_QML_IMPORT_PATH' \
  ctest --test-dir "$build" -R '^tst_module$' --no-tests=error
echo "PASS: plugin builds and ctest passes"

# 4. the installed module ------------------------------------------------------
[[ -f $build/qml/C7/qmldir ]] || fail "the build left no C7 module at qml/C7"
[[ -x $build/tests/tst_module ]] || fail "the build left no tst_module binary"
dest=$tmp/dest
qmldest=$dest/usr/lib/qt6/qml
DESTDIR=$dest run_logged install cmake --install "$build"
for f in qmldir c7.qmltypes; do
  [[ -f $qmldest/C7/$f ]] || fail "cmake --install left no usr/lib/qt6/qml/C7/$f"
done
# One plugin library carrying the whole module: a second shared library would
# need its own place on the loader path, which the package does not give it.
libs=$(find "$qmldest/C7" -name '*.so*')
[[ $(wc -l <<<"$libs") -eq 1 && -n $libs ]] || fail "expected one plugin library in C7/, got:\n$libs"
stray=$(find "$dest" ! -type d ! -path "$qmldest/C7/*")
[[ -z $stray ]] || fail "cmake --install puts files outside usr/lib/qt6/qml/C7:\n$stray"
# The build tree's copy goes first, so only the installed one can satisfy this.
rm -rf "$build/qml/C7"
C7_QML_IMPORT_PATH=$qmldest run_logged 'tst_module against the installed module' \
  "$build/tests/tst_module"
echo "PASS: cmake --install ships the whole module to usr/lib/qt6/qml/C7"

# 5. the module test needs the module -----------------------------------------
# Run the binary itself: through ctest, "no such test" and "test failed" share
# an exit code.
rc=0
"$build/tests/tst_module" >"$log" 2>&1 || rc=$?
if ((rc != 1)) || ! grep -q 'module C7 is not installed' "$log"; then
  cat "$log" >&2
  fail "tst_module exited $rc without the C7 module; it must fail for the missing module"
fi
echo "PASS: tst_module fails without the C7 module"
