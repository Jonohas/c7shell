#!/usr/bin/env bash
# Self-check for the shared tuned-missing card.
# Run it directly: tests/test-tuned-notice.sh
#
# Same trick as tests/test-toasts.sh: the card is plain QtQuick over two
# singletons, so the singletons are shimmed and the card itself is real. No
# compositor and no tuned.
#
# What it defends: the battery popover and the settings page each carried their
# own copy of this card, and the copies had drifted. Neither caller can be
# loaded here -- one is a GlassPopover and the other a SettingsPage, both of
# which need quickshell proper -- so the card is driven directly, and the two
# callers are checked against its declared properties by name below.
set -euo pipefail

# shellcheck source=fixtures/harness.sh
. "$(dirname -- "$0")/fixtures/harness.sh"
mktmp
need_qml6

mkdir -p "$tmp/qs/Common" "$tmp/qs/Services" "$tmp/qs/Theme" "$tmp/qs/Modules/Power"

cp "$src/Modules/Power/TunedNotice.qml" "$tmp/qs/Modules/Power/"
printf 'module qs.Modules.Power\nTunedNotice 1.0 TunedNotice.qml\n' \
  > "$tmp/qs/Modules/Power/qmldir"

# The real Icon: the card names "alert-triangle", and an icon nobody drew is
# not an error anywhere -- Image fails to load and the glyph is simply absent.
cp "$src/Common/Icon.qml" "$tmp/qs/Common/"
printf 'module qs.Common\nIcon 1.0 Icon.qml\n' > "$tmp/qs/Common/qmldir"

# The Theme stand-in, from tests/fixtures/theme-stub.sh -- one copy, with its
# colours read from the same palette.json the real Theme reads.
write_theme_stub "$tmp/qs" "$src"

# -- the two singletons the card reads ---------------------------------------
# `installed` is the whole state model as far as this card is concerned: it
# picks the headline and decides whether the button exists. Writable here,
# where the real one is driven off tuned's D-Bus name.
cat > "$tmp/qs/Services/TunedService.qml" <<'QML'
pragma Singleton
import QtQuick
QtObject {
  property bool installed: false
  property bool available: false
}
QML
# The card's only side effect. Counted rather than performed: the real one goes
# through pkexec and a root helper.
cat > "$tmp/qs/Services/PowerService.qml" <<'QML'
pragma Singleton
import QtQuick
QtObject {
  property int enableCalls: 0
  function enableTuned() { enableCalls++ }
}
QML
printf 'module qs.Services\nsingleton TunedService 1.0 TunedService.qml\nsingleton PowerService 1.0 PowerService.qml\n' \
  > "$tmp/qs/Services/qmldir"

log=$tmp/tuned-notice.log
# QT_FORCE_STDERR_LOGGING: without a tty Qt sends its messages to journald,
# where this test cannot see them.
QT_QPA_PLATFORM=offscreen \
QT_FORCE_STDERR_LOGGING=1 \
timeout 30 qml6 -I "$tmp" "$here/tuned-notice-qml-test.qml" >"$log" 2>&1 \
  || fail "qml6 exited non-zero:\n$(cat "$log")"

grep -q 'TUNED-NOTICE-TEST-PASS' "$log" || fail "the test never reached its end:\n$(cat "$log")"
# Any line naming a .qml file is a warning, an error or a type failure.
if grep -q '\.qml:' "$log"; then
  fail "QML diagnostics:\n$(grep '\.qml:' "$log")"
fi

# --------------------------------------------------------------------------
# The two callers, which nothing above can instantiate. Setting a property the
# card does not declare is not a load failure -- quickshell logs a binding
# warning and carries on, so the shell comes up looking right and the card
# quietly renders with a default in place of what the caller asked for.
# --------------------------------------------------------------------------
declared=$(grep -oE '^  property [A-Za-z0-9_<>]+ [A-Za-z_][A-Za-z0-9_]*' \
  "$src/Modules/Power/TunedNotice.qml" | awk '{print $3}')

for caller in "$src/Modules/Popovers/PowerPopover.qml" \
              "$src/Modules/Settings/pages/PowerPage.qml"; do
  grep -q '^import qs.Modules.Power$' "$caller" \
    || fail "$(basename "$caller") uses TunedNotice without importing qs.Modules.Power,
which resolves at call time rather than at load time."

  # The properties it sets inside its TunedNotice block, up to the closing
  # brace at the block's own indentation.
  while read -r prop; do
    case $prop in visible) continue ;; esac   # Item's own, not the card's
    grep -qx "$prop" <<<"$declared" \
      || fail "$(basename "$caller") sets TunedNotice.$prop, which TunedNotice does
not declare. That is a binding warning, not an error: the card loads and
silently ignores it."
  done < <(awk '
    /TunedNotice[[:space:]]*\{/ { indent = match($0, /[^ ]/); inBlock = 1; next }
    inBlock && /^[[:space:]]*\}/ && match($0, /[^ ]/) == indent { inBlock = 0 }
    inBlock && match($0, /^[[:space:]]*[a-z][A-Za-z0-9_]*:/) {
      p = $0
      sub(/^[[:space:]]*/, "", p)
      sub(/:.*/, "", p)
      print p
    }' "$caller")
done

echo 'PASS: the shared tuned-missing card'
