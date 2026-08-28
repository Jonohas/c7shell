#!/usr/bin/env bash
# Self-check for bin/c7up. Run it directly: tests/test-c7up.sh
#
# c7up's whole job is to turn six unstructured command-line tools into one
# NDJSON contract the shell can bind to, so the test builds a fake system out
# of stubs -- checkupdates, pacman, paru, pacdiff, flatpak -- and asserts on
# the JSON that comes out. Nothing here touches the real package manager, and
# nothing here needs root: `verdict`, the part with all the parsing in it, is
# unprivileged by design.
set -euo pipefail

here=$(cd -- "$(dirname -- "$0")" && pwd)
c7up=$here/../bin/c7up
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT

bin=$tmp/bin
mkdir -p "$bin" "$tmp/state" "$tmp/cache" "$tmp/config"

fail() { printf 'FAIL: %b\n' "$1" >&2; exit 1; }

command -v python3 >/dev/null || { echo 'SKIP: python3 not installed'; exit 0; }

# The real tools c7up leans on that are not worth stubbing.
for helper in bash sed awk grep tr cut wc date mktemp rm cat diff paste head tail \
              printf sort timeout dirname uname mkdir touch; do
  p=$(command -v "$helper" 2>/dev/null) && ln -sf "$p" "$bin/$helper"
done

stub() { printf '%s\n' "#!/bin/sh" "$2" > "$bin/$1"; chmod +x "$bin/$1"; }

run_verdict() {
  env -i PATH="$bin:/usr/bin:/bin" HOME="$tmp" \
      XDG_STATE_HOME="$tmp/state" XDG_CACHE_HOME="$tmp/cache" \
      XDG_CONFIG_HOME="$tmp/config" TMPDIR="$tmp" \
      bash "$c7up" verdict 2>"$tmp/err"
}

# A verdict is one line of JSON; this pulls one field out of it.
field() { python3 -c "import json,sys;print(json.load(sys.stdin)[sys.argv[1]])" "$1"; }
jq_py() { python3 -c "import json,sys;d=json.load(sys.stdin);print(eval(sys.argv[1],{'d':d}))" "$1"; }

# --------------------------------------------------------------------------
# 1. The clean path: four routine bumps, nothing that needs a decision.
# --------------------------------------------------------------------------
stub checkupdates 'cat <<EOF
mesa 25.1.2 -> 25.1.4
pipewire 1.4.1 -> 1.4.2
git 2.51.0 -> 2.51.1
curl 8.15.0 -> 8.16.0
EOF'
# %s is the download size in bytes; four packages, 100 MB total.
stub pacman 'case "$*" in
  *--print-format*) echo 25000000; echo 25000000; echo 25000000; echo 25000000 ;;
  *--print*) echo "https://mirror/extra/mesa.pkg.tar.zst" ;;
  *-Qoq*) echo filesystem ;;
  *-Qii*) echo "MODIFIED	/etc/pacman.conf" ;;
esac
exit 0'
stub paru 'exit 0'
stub pacdiff 'exit 0'
stub flatpak 'exit 0'

out=$(run_verdict) || fail "verdict exited non-zero:\n$(cat "$tmp/err")"
python3 -c 'import json,sys;json.loads(sys.stdin.read())' <<<"$out" \
  || fail "verdict is not valid JSON:\n$out"

[[ $(field clean <<<"$out") == True ]] \
  || fail "four routine bumps were not the clean path:\n$out"
[[ $(field size <<<"$out") == 100000000 ]] \
  || fail "download size was not summed from --print-format: $(field size <<<"$out")"
[[ $(jq_py "len(d['sources'][0]['items'])" <<<"$out") == 4 ]] \
  || fail "the pacman source did not carry four packages:\n$out"
# The versions are what the whole design's old -> new rendering is built on.
[[ $(jq_py "d['sources'][0]['items'][0]['old']" <<<"$out") == 25.1.2 ]] \
  || fail "old versions were dropped:\n$out"
[[ $(jq_py "d['sources'][0]['items'][0]['new']" <<<"$out") == 25.1.4 ]] \
  || fail "new versions were dropped:\n$out"

# arch-update's state files are the contract with arch-update itself: its timer
# and its tray applet read these, and a run that did not write them would leave
# the two halves disagreeing about what is pending.
[[ -s $tmp/state/arch-update/last_updates_check_packages ]] \
  || fail "arch-update's package state file was not written"
grep -q '^mesa 25.1.2 -> 25.1.4$' "$tmp/state/arch-update/last_updates_check_packages" \
  || fail "the state file is not in arch-update's format:\n$(cat "$tmp/state/arch-update/last_updates_check_packages")"
[[ -s $tmp/state/arch-update/last_updates_check_time ]] \
  || fail "the check timestamp was not written"

# --------------------------------------------------------------------------
# 2. A kernel in the set escalates, and predicts a reboot.
# --------------------------------------------------------------------------
stub checkupdates 'cat <<EOF
mesa 25.1.2 -> 25.1.4
linux 6.15.4 -> 6.16.1
EOF'
out=$(run_verdict) || fail "verdict exited non-zero on the kernel case"
[[ $(field clean <<<"$out") == False ]] || fail "a kernel update did not escalate:\n$out"
[[ $(field reboot <<<"$out") == True ]] || fail "a kernel update did not predict a reboot:\n$out"
[[ $(jq_py "[x['kind'] for x in d['decisions']]" <<<"$out") == "['kernel']" ]] \
  || fail "the kernel was not the only decision:\n$out"
[[ $(jq_py "d['decisions'][0]['detail']" <<<"$out") == "6.15.4 → 6.16.1" ]] \
  || fail "the kernel decision lost its versions:\n$out"

# mesa is in most weeks' updates. Treating a graphics package as a decision
# would mean the clean path never happens, which is the one thing the merged
# design cannot afford -- so it must NOT be a driver match.
stub checkupdates 'echo "mesa 25.1.2 -> 25.1.4"'
out=$(run_verdict)
[[ $(field clean <<<"$out") == True ]] || fail "mesa alone escalated:\n$out"

# An out-of-tree module built against the running kernel is a different story.
stub checkupdates 'echo "nvidia-dkms 570.1 -> 575.0"'
out=$(run_verdict)
[[ $(field clean <<<"$out") == False ]] || fail "a dkms module did not escalate:\n$out"
[[ $(jq_py "d['decisions'][0]['kind']" <<<"$out") == driver ]] \
  || fail "a dkms module was not classified as a driver:\n$out"

# --------------------------------------------------------------------------
# 3. A replacement is read out of pacman's own transaction, not guessed.
# --------------------------------------------------------------------------
stub checkupdates 'echo "mesa 25.1.2 -> 25.1.4"'
stub pacman 'case "$*" in
  *--print-format*) echo 1000 ;;
  *--print*) echo ":: Replace jack2 with extra/pipewire-jack?" ;;
esac
exit 0'
out=$(run_verdict)
[[ $(field clean <<<"$out") == False ]] || fail "a replacement did not escalate:\n$out"
[[ $(jq_py "d['decisions'][0]['kind']" <<<"$out") == replace ]] \
  || fail "the replacement was not classified:\n$out"
[[ $(jq_py "d['decisions'][0]['title']" <<<"$out") == "jack2 → pipewire-jack" ]] \
  || fail "the replacement lost its two package names:\n$out"

# --------------------------------------------------------------------------
# 4. A failed transaction is a decision, not a surprise halfway through a run.
# --------------------------------------------------------------------------
stub pacman 'case "$*" in
  *--print-format*) echo 1000 ;;
  *--print*) echo "error: failed to prepare transaction (could not satisfy dependencies)" ;;
esac
exit 0'
out=$(run_verdict)
[[ $(jq_py "any(x['kind']=='conflict' for x in d['decisions'])" <<<"$out") == True ]] \
  || fail "an unpreparable transaction was not surfaced:\n$out"

# --------------------------------------------------------------------------
# 5. A pacnew waiting from an earlier run is a decision too.
# --------------------------------------------------------------------------
stub pacman 'case "$*" in
  *--print-format*) echo 1000 ;;
  *-Qoq*) echo filesystem ;;
  *-Qii*) printf "MODIFIED\t/etc/pacman.conf\n" ;;
esac
exit 0'
stub pacdiff 'echo /etc/pacman.conf.pacnew'
out=$(run_verdict)
[[ $(jq_py "any(x['kind']=='pacnew' for x in d['decisions'])" <<<"$out") == True ]] \
  || fail "a parked pacnew did not escalate:\n$out"

# --------------------------------------------------------------------------
# 6. Every string that reaches the shell must survive JSON. pacman's output is
#    full of ANSI and control bytes, and one raw byte invalidates the line for
#    the parser on the other side -- which is a silently empty dropdown.
# --------------------------------------------------------------------------
stub checkupdates 'printf "we\x1b[31mird\"pkg\x07 1.0 -> 2.0\n"'
stub pacdiff 'exit 0'
out=$(run_verdict)
python3 -c 'import json,sys;json.loads(sys.stdin.read())' <<<"$out" \
  || fail "a package name with ANSI and a quote in it broke the JSON:\n$out"

# --------------------------------------------------------------------------
# 7. No network: the dropdown must be told, not left showing a stale count as
#    though it were fresh.
# --------------------------------------------------------------------------
stub checkupdates 'exit 1'
out=$(run_verdict) && fail "a failed sync exited zero"
[[ $(jq_py "'error' in d" <<<"$out") == True ]] \
  || fail "a failed sync did not report an error:\n$out"

# --------------------------------------------------------------------------
# 8. c7up-root is the trust boundary: it takes a verb, never a command line.
# --------------------------------------------------------------------------
root=$here/../bin/c7up-root
out=$(bash "$root" 'sync; rm -rf /' 2>&1 || true)
[[ $out == *"unknown verb"* ]] || fail "c7up-root accepted a compound verb: $out"
out=$(bash "$root" sync 'evil;name' 2>&1 || true)
[[ $out == *"implausible package name"* ]] \
  || fail "c7up-root accepted a package name with a semicolon in it: $out"
out=$(bash "$root" pacnew-take /etc/../root/.ssh/authorized_keys 2>&1 || true)
[[ $out == *"path traversal"* || $out == *"not a config path"* ]] \
  || fail "c7up-root accepted a traversal path: $out"
out=$(bash "$root" restart-services 'foo.service; reboot' 2>&1 || true)
[[ $out == *"not a service unit"* ]] || fail "c7up-root accepted a crafted unit name: $out"

# --------------------------------------------------------------------------
# 9. The run's streaming contract. This is the half that cannot be exercised
#    against a real system in a test -- it installs packages -- so the stubs
#    stand in for pkexec and the root helper, and the assertions are on the
#    event stream the wizard's progress bar and log are bound to.
# --------------------------------------------------------------------------
mkdir -p "$tmp/lib"
# pkexec's only job here is to run what it is handed; the authorisation it
# normally performs has no analogue in a test.
stub pkexec 'exec "$@"'
cat > "$tmp/lib/c7up-root" <<'EOF'
#!/bin/sh
# Stands in for pacman under pkexec: the (n/m) lines are the only progress
# either half of a real run emits, and the whole bar is driven off them.
echo "(1/3) upgrading mesa... done"
echo "(2/3) upgrading pipewire... done"
printf ':: [1mrunning post-transaction hooks[0m
'
echo "(3/3) upgrading systemd... done"
EOF
chmod +x "$tmp/lib/c7up-root"

state=$tmp/state/arch-update
mkdir -p "$state"
printf 'mesa 1 -> 2
pipewire 1 -> 2
systemd 1 -> 2
' > "$state/last_updates_check_packages"
: > "$state/last_updates_check_aur"
: > "$state/last_updates_check_flatpak"
stub pacdiff 'exit 0'
stub checkservices 'exit 0'

out=$(env -i PATH="$bin:/usr/bin:/bin" HOME="$tmp"       XDG_STATE_HOME="$tmp/state" XDG_CACHE_HOME="$tmp/cache"       XDG_CONFIG_HOME="$tmp/config" TMPDIR="$tmp" C7UP_LIBDIR="$tmp/lib"       bash "$c7up" run 2>"$tmp/err") || fail "run exited non-zero:\n$(cat "$tmp/err")"

# Every line the shell receives has to parse on its own -- the QML side reads
# this with a SplitParser and one bad line is a dropped event, not an error.
while IFS= read -r line; do
  [[ -n $line ]] || continue
  python3 -c 'import json,sys;json.loads(sys.stdin.read())' <<<"$line" \
    || fail "a run event is not valid JSON: $line"
done <<<"$out"

ev() { python3 -c "
import json,sys
for l in sys.stdin:
    l=l.strip()
    if not l: continue
    d=json.loads(l)
    if d.get('ev')==sys.argv[1]: print(json.dumps(d))
" "$1"; }

[[ $(ev start <<<"$out" | wc -l) == 1 ]] || fail "the run did not announce a start:\n$out"
[[ $(ev start <<<"$out" | field total) == 3 ]] \
  || fail "the run's total did not come from the state files:\n$out"

# The progress bar and the "11 of 18" headline are both bound to these.
[[ $(ev progress <<<"$out" | wc -l) == 3 ]] \
  || fail "the (n/m) lines did not become progress events:\n$(ev progress <<<"$out")"
[[ $(ev progress <<<"$out" | tail -1 | field done) == 3 ]] \
  || fail "progress did not reach the end:\n$(ev progress <<<"$out")"

# One authorisation event pair, so the wizard can say what it is waiting for
# rather than looking hung while the polkit dialog is up.
[[ $(ev auth <<<"$out" | head -1 | field state) == waiting ]] \
  || fail "the run did not announce that it was waiting on authorisation:\n$out"
[[ $(ev auth <<<"$out" | tail -1 | field state) == granted ]] \
  || fail "the run never cleared its waiting-on-authorisation state:\n$out"

[[ $(ev done <<<"$out" | field ok) == True ]] || fail "the run did not report success:\n$out"
# A run that leaves the counts it started from in place would have the bar
# still advertising updates that are now installed.
[[ ! -s $state/last_updates_check_packages ]] \
  || fail "a successful run left arch-update's pending list populated"

# The log the wizard's "view log" opens.
log=$(ev done <<<"$out" | field log)
[[ -s $log ]] || fail "the run wrote no log at $log"
grep -q 'upgrading mesa' "$log" || fail "the log did not capture the run's output"
# ANSI belongs in a terminal, not in a file the shell renders -- and not in the
# JSON either, where an escape byte would take the whole line down with it.
if grep -q $'\033' "$log"; then fail "escape sequences reached the log"; fi
if grep -q $'\033' <<<"$out"; then fail "escape sequences reached the event stream"; fi
if ! grep -q 'post-transaction hooks' "$log"; then
  fail "the coloured line was dropped instead of being stripped:\n$(cat "$log")"
fi

# --------------------------------------------------------------------------
# 10. A failed run says so, and says the transaction was rolled back rather
#     than leaving the user to guess what state the machine is in.
# --------------------------------------------------------------------------
printf 'mesa 1 -> 2\n' > "$state/last_updates_check_packages"
cat > "$tmp/lib/c7up-root" <<'EOF'
#!/bin/sh
echo "(1/1) upgrading mesa..."
echo "error: failed to commit transaction (conflicting files)" >&2
exit 1
EOF
chmod +x "$tmp/lib/c7up-root"

out=$(env -i PATH="$bin:/usr/bin:/bin" HOME="$tmp" \
      XDG_STATE_HOME="$tmp/state" XDG_CACHE_HOME="$tmp/cache" \
      XDG_CONFIG_HOME="$tmp/config" TMPDIR="$tmp" C7UP_LIBDIR="$tmp/lib" \
      bash "$c7up" run 2>/dev/null) && fail "a failed run exited zero"
[[ $(ev done <<<"$out" | field ok) == False ]] || fail "a failed run reported success:\n$out"
[[ $(ev done <<<"$out" | field failed) == pacman ]] \
  || fail "the failed run did not name the source that failed:\n$out"
[[ $(ev done <<<"$out" | jq_py "'error' in d and d['error']") != "" ]] \
  || fail "the failed run carried no error text for the wizard to show:\n$out"
# The pending list must survive a failure: those packages really are still
# pending, and clearing it would blank the badge over a machine that did not
# update.
[[ -s $state/last_updates_check_packages ]] \
  || fail "a failed run cleared arch-update's pending list"

echo 'test-c7up.sh: all checks passed'
