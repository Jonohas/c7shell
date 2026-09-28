#!/usr/bin/env bash
# The preamble every test script in tests/ opened with. Sourced, not executed.
#
#   . "$(dirname -- "$0")/fixtures/harness.sh"
#
# Sets `repo`, `here` and `src`, and defines fail/need_qml6/mktmp. Twenty-four
# scripts each carried their own copy of the four, and `fail` had already split
# into a %s spelling and a %b one -- so half of them printed a literal "\n" in
# the message that was written to break across lines. This is the one copy, and
# it is %b: the multi-line failures are the ones worth reading.
#
# What it deliberately does NOT cover is the Quickshell type stubs. Those look
# alike and are not: each test's Process stub records exactly what that test
# drives and carries the comment saying why, and folding them into one shared
# stub would mean a change made for one test silently reaching every other.
#
# Sourcing theme-stub.sh here rather than in each caller, because every script
# that wanted the Theme stand-in also wanted all of the above.

# The repository root, from this file rather than from $0: a test may be invoked
# by any path, and `$0`-relative breaks the moment one is run from elsewhere.
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
here=$repo/tests
src=$repo/quickshell/c7shell

# %b, so a message can lay out a diff or a QML log across lines. Every caller's
# message is a literal in the test, never anything read off the machine under
# test, so there is nothing here for %b's escapes to mangle.
fail() { printf 'FAIL: %b\n' "$1" >&2; exit 1; }

# A skip, not a failure: qt6-declarative is not a dependency of this package,
# and a machine without it still gets every non-QML check in the suite. Exits
# the calling script, which is the point -- there is nothing after it to run.
need_qml6() {
  command -v qml6 >/dev/null && return 0
  echo 'SKIP: qml6 not installed (package: qt6-declarative)'
  exit 0
}

# Sets `tmp` and arranges for it to go. Scripts that need to kill a process on
# the way out keep their own trap and do not call this.
mktmp() {
  tmp=$(mktemp -d)
  # shellcheck disable=SC2064  # $tmp is expanded now on purpose: the trap has
  # to name the directory this call made, not whatever $tmp holds at exit.
  trap "rm -rf -- '$tmp'" EXIT
}

# shellcheck source=theme-stub.sh
. "$repo/tests/fixtures/theme-stub.sh"
