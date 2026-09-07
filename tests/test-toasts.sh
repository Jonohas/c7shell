#!/usr/bin/env bash
# Self-check for the shared toast scaffold. Run it directly: tests/test-toasts.sh
#
# Same trick as tests/test-updates.sh: the pieces under test are plain QtQuick,
# so the handful of Quickshell-flavoured things around them are shimmed and the
# lifetime rules -- when a card hides itself, when it refuses to, what a kick()
# does to a card that is already up -- are real. No compositor.
set -euo pipefail

here=$(cd -- "$(dirname -- "$0")" && pwd)
src=$here/../quickshell/c7shell
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT

fail() { printf 'FAIL: %b\n' "$1" >&2; exit 1; }

command -v qml6 >/dev/null || {
  echo 'SKIP: qml6 not installed (package: qt6-declarative)'
  exit 0
}

mkdir -p "$tmp/qs/Common" "$tmp/qs/Theme"

for f in ToastCard ToastAction ToastSeparator GlassPanel; do
  cp "$src/Common/$f.qml" "$tmp/qs/Common/"
done
{
  printf 'module qs.Common\n'
  for f in ToastCard ToastAction ToastSeparator GlassPanel; do
    printf '%s 1.0 %s.qml\n' "$f" "$f"
  done
} > "$tmp/qs/Common/qmldir"

# The Theme stand-in, from tests/fixtures/theme-stub.sh -- one copy, with its
# colours read from the same palette.json the real Theme reads.
# shellcheck source=fixtures/theme-stub.sh
. "$here/fixtures/theme-stub.sh"
write_theme_stub "$tmp/qs" "$src"

log=$tmp/toasts.log
# QT_FORCE_STDERR_LOGGING: without a tty Qt sends its messages to journald,
# where this test cannot see them.
QT_QPA_PLATFORM=offscreen \
QT_FORCE_STDERR_LOGGING=1 \
timeout 30 qml6 -I "$tmp" "$here/toastcard-qml-test.qml" >"$log" 2>&1 \
  || fail "qml6 exited non-zero:\n$(cat "$log")"

grep -q 'TOASTS-TEST-PASS' "$log" || fail "the test never reached its end:\n$(cat "$log")"
# Any line naming a .qml file is a warning, an error or a type failure.
if grep -q '\.qml:' "$log"; then
  fail "QML diagnostics:\n$(grep '\.qml:' "$log")"
fi

echo 'test-toasts.sh: all checks passed'
