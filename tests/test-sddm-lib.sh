#!/usr/bin/env bash
# Self-check for share/c7shell-sddm.sh. Run it directly: tests/test-sddm-lib.sh
#
# The parse in here used to be three hand-kept copies, one per script, and they
# had drifted: only c7shell-bootstrap's stripped the CR off a CRLF sddm.conf.
# On such a file c7shell-upgrade and c7shell-doctor read the theme name as
# "c7shell\r", decided another greeter owned the machine, and refused to touch
# the drop-in -- c7shell-upgrade with a warning naming a theme that is not
# installed. One copy, and the CR case pinned here.
set -euo pipefail

# shellcheck source=fixtures/harness.sh
. "$(dirname -- "$0")/fixtures/harness.sh"
mktmp

# shellcheck source=../share/c7shell-sddm.sh
. "$here/../share/c7shell-sddm.sh"

mkdir -p "$tmp/etc/sddm.conf.d"

# --------------------------------------------------------------------------
# 1. Nothing selects a theme.
# --------------------------------------------------------------------------
got=$(sddm_theme_current "$tmp")
[[ -z $got ]] || fail "an empty tree named a theme: \"$got\""

# --------------------------------------------------------------------------
# 2. sddm.conf alone.
# --------------------------------------------------------------------------
printf '[Theme]\nCurrent=breeze\n' > "$tmp/etc/sddm.conf"
got=$(sddm_theme_current "$tmp")
[[ $got == breeze ]] || fail "sddm.conf was not read: \"$got\""

# --------------------------------------------------------------------------
# 3. A drop-in wins over sddm.conf, and the later drop-in wins over the
#    earlier one -- that is the order sddm itself reads them in.
# --------------------------------------------------------------------------
printf '[Theme]\nCurrent=c7shell\n' > "$tmp/etc/sddm.conf.d/10-c7shell.conf"
got=$(sddm_theme_current "$tmp")
[[ $got == c7shell ]] || fail "the drop-in did not win over sddm.conf: \"$got\""

printf '[Theme]\nCurrent=maldives\n' > "$tmp/etc/sddm.conf.d/90-mine.conf"
got=$(sddm_theme_current "$tmp")
[[ $got == maldives ]] || fail "the later drop-in did not win: \"$got\""
rm "$tmp/etc/sddm.conf.d/90-mine.conf"

# --------------------------------------------------------------------------
# 4. The drift this file exists for: a CRLF config still names c7shell, and
#    surrounding whitespace is not part of the name either.
# --------------------------------------------------------------------------
printf '[Theme]\r\nCurrent=c7shell\r\n' > "$tmp/etc/sddm.conf.d/10-c7shell.conf"
got=$(sddm_theme_current "$tmp")
[[ $got == c7shell ]] || fail "a CRLF drop-in read as \"$got\", not c7shell"

printf '[Theme]\n  Current =  c7shell  \n' > "$tmp/etc/sddm.conf.d/10-c7shell.conf"
got=$(sddm_theme_current "$tmp")
[[ $got == c7shell ]] || fail "a spaced Current= read as \"$got\", not c7shell"

# --------------------------------------------------------------------------
# 5. The drop-in body names the script writing it, and carries both of the
#    lines the greeter needs.
# --------------------------------------------------------------------------
body=$(sddm_dropin_body)
grep -q '^Current=c7shell$' <<<"$body" \
  || fail "the drop-in body does not select c7shell:\n$body"
grep -q '^GreeterEnvironment=QML_XHR_ALLOW_FILE_READ=1$' <<<"$body" \
  || fail "the drop-in body does not allow the greeter's file:// reads:\n$body"
grep -q "Written by ${0##*/}\." <<<"$body" \
  || fail "the drop-in body does not name its writer:\n$body"

# The body a script writes must be a config this same parse reads back as
# c7shell -- the two halves of the file are only useful together.
printf '%s\n' "$body" > "$tmp/etc/sddm.conf.d/10-c7shell.conf"
got=$(sddm_theme_current "$tmp")
[[ $got == c7shell ]] || fail "the body we write reads back as \"$got\""

echo 'PASS: share/c7shell-sddm.sh'
