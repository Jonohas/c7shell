#!/usr/bin/env bash
# Self-check for bin/c7shell-bootstrap. Run it directly: tests/test-bootstrap.sh
#
# The bootstrap decides what to install from what it finds on the machine, so
# the test fakes the machine: stub pacman/lspci/systemctl on a PATH with
# nothing else on it, and read the plan back out of --dry-run. Every mutating
# command is logged by the stubs, so "changed nothing" is checked, not assumed.
set -euo pipefail

here=$(cd -- "$(dirname -- "$0")" && pwd)
bootstrap=$here/../bin/c7shell-bootstrap
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT

bin=$tmp/bin
log=$tmp/ran.log
mkdir -p "$bin"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

for helper in grep uname getent id sed cat; do ln -s "$(command -v "$helper")" "$bin/$helper"; done

cat > "$bin/pacman" <<'STUB'
#!/bin/sh
case $1 in
  -Qq)
    [ -n "$2" ] || { printf '%s\n' $STUB_INSTALLED; exit 0; }
    for p in $STUB_INSTALLED; do [ "$p" = "$2" ] && exit 0; done
    exit 1 ;;
  -Si)
    for p in $STUB_UNKNOWN; do [ "$p" = "$2" ] && exit 1; done
    exit 0 ;;
  *) echo "pacman $*" >> "$STUB_LOG"; exit 0 ;;
esac
STUB

cat > "$bin/systemctl" <<'STUB'
#!/bin/sh
if [ "$1" = is-enabled ]; then
  for u in $STUB_ENABLED; do [ "$u" = "$2" ] && { echo enabled; exit 0; }; done
  echo disabled; exit 1
fi
echo "systemctl $*" >> "$STUB_LOG"
STUB

cat > "$bin/lspci" <<'STUB'
#!/bin/sh
printf '%s\n' "$STUB_LSPCI"
STUB

for s in pacman systemctl lspci; do chmod +x "$bin/$s"; done
# Present, so the bootstrap never tries to build an AUR helper in a test.
printf '#!/bin/sh\necho "paru $*" >> "$STUB_LOG"\n' > "$bin/paru"; chmod +x "$bin/paru"
# root wrapper, so run_root has something to find in a non-dry run
printf '#!/bin/sh\necho "sudo $*" >> "$STUB_LOG"\n' > "$bin/sudo"; chmod +x "$bin/sudo"

# plan <lspci line> [args...] -> the dry-run plan
plan() {
  local pci=$1; shift
  : > "$log"
  env -i PATH="$bin" HOME="$tmp" USER=tester \
    STUB_LOG="$log" STUB_LSPCI="$pci" \
    STUB_INSTALLED="${STUB_INSTALLED:-linux}" \
    STUB_UNKNOWN="${STUB_UNKNOWN:-}" STUB_ENABLED="${STUB_ENABLED:-}" \
    /usr/bin/bash "$bootstrap" --dry-run "$@" 2>&1
}

AMD='01:00.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Raphael [1002:164e]'
INTEL='00:02.0 VGA compatible controller [0300]: Intel Corporation Alder Lake-P GT2 [8086:46a6]'
NVIDIA='01:00.0 VGA compatible controller [0300]: NVIDIA Corporation AD107M [GeForce RTX 4060 Max-Q] [10de:28e0]'
OLD_NVIDIA='01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GP104 [GeForce GTX 1080] [10de:1b80]'
QEMU='00:01.0 VGA compatible controller [0300]: Red Hat, Inc. Virtio GPU [1af4:1050]'

# --- the things every machine needs ---------------------------------------
out=$(plan "$AMD")
for pkg in qt6-wayland xdg-utils polkit pipewire pipewire-pulse wireplumber \
           ttf-jetbrains-mono noto-fonts hicolor-icon-theme breeze-icons \
           sddm networkmanager bluez kitty dolphin ddcutil brightnessctl playerctl; do
  grep -q "\b$pkg\b" <<<"$out" || fail "$pkg is not in the plan:\n$out"
done
grep -q 'pipewire.socket' <<<"$out" || fail "the pipewire user units are not enabled:\n$out"
grep -q 'enable: .*sddm.service' <<<"$out" || fail "sddm.service is not enabled:\n$out"
grep -q 'enable: .*NetworkManager.service' <<<"$out" || fail "NetworkManager is not enabled:\n$out"
grep -q 'enable: .*bluetooth.service' <<<"$out" || fail "bluetooth is not enabled:\n$out"

# --dry-run really does nothing: no stub was asked to change anything
[[ ! -s $log ]] || fail "--dry-run ran something:\n$(cat "$log")"

# --- per-vendor drivers ----------------------------------------------------
out=$(plan "$AMD")
grep -q 'GPU: amd' <<<"$out" || fail "amd not detected:\n$out"
grep -q '\bvulkan-radeon\b' <<<"$out" || fail "no radeon vulkan driver:\n$out"
grep -q 'nvidia' <<<"$out" && fail "amd plan pulled in nvidia:\n$out"

out=$(plan "$INTEL")
grep -q 'GPU: intel' <<<"$out" || fail "intel not detected:\n$out"
grep -q '\bvulkan-intel\b' <<<"$out" || fail "no intel vulkan driver:\n$out"

out=$(plan "$NVIDIA")
grep -q 'GPU: nvidia' <<<"$out" || fail "nvidia not detected:\n$out"
grep -q '\bnvidia-open-dkms\b' <<<"$out" || fail "no nvidia-open-dkms:\n$out"
grep -q '\bnvidia-utils\b' <<<"$out" || fail "no nvidia-utils:\n$out"
# DKMS with no headers builds nothing and the next boot has no driver at all
grep -q '\blinux-headers\b' <<<"$out" || fail "no kernel headers for dkms:\n$out"
grep -q 'modprobe.d/c7shell-nvidia.conf' <<<"$out" || fail "no nvidia modeset file:\n$out"
grep -q 'modeset=1' <<<"$out" || fail "the nvidia file does not set modeset:\n$out"

# headers follow the kernels that are actually installed
STUB_INSTALLED='linux linux-lts' out=$(plan "$NVIDIA")
grep -q '\blinux-lts-headers\b' <<<"$out" || fail "no headers for linux-lts:\n$out"

# a pre-Turing card cannot use the open module, and silence there means a
# black screen after the next reboot
out=$(plan "$OLD_NVIDIA")
grep -q 'pre-Turing' <<<"$out" || fail "no warning for a pre-Turing nvidia card:\n$out"

out=$(plan "$QEMU")
grep -q 'GPU: virtual' <<<"$out" || fail "a virtual GPU was not recognised:\n$out"
grep -q '\bmesa\b' <<<"$out" || fail "no mesa for a virtual GPU:\n$out"

out=$(plan '')
grep -q 'no GPU was detected' <<<"$out" || fail "an empty lspci was not reported:\n$out"

out=$(plan "$NVIDIA" --no-drivers)
grep -q 'nvidia-open-dkms' <<<"$out" && fail "--no-drivers still installed a driver:\n$out"

# --- conflicts, which are the difference between working and no login -----
STUB_ENABLED='gdm.service' out=$(plan "$AMD")
grep -q 'gdm.service is already enabled' <<<"$out" || fail "an enabled gdm was not noticed:\n$out"
grep -q 'enable: .*sddm.service' <<<"$out" && fail "sddm was enabled alongside gdm:\n$out"

STUB_ENABLED='systemd-networkd.service' out=$(plan "$AMD")
grep -q 'not enabling NetworkManager' <<<"$out" || fail "systemd-networkd was not noticed:\n$out"
grep -q 'enable: .*NetworkManager.service' <<<"$out" && fail "NetworkManager enabled over systemd-networkd:\n$out"

# already-enabled units are not enabled again
STUB_ENABLED='sddm.service NetworkManager.service bluetooth.service' out=$(plan "$AMD")
grep -q 'no system units to enable' <<<"$out" || fail "re-enabled units that were already enabled:\n$out"

# --- opting out ------------------------------------------------------------
out=$(plan "$AMD" --no-greeter)
grep -q '\bsddm\b' <<<"$out" && fail "--no-greeter still installed sddm:\n$out"
out=$(plan "$AMD" --no-extras)
grep -q '\bkitty\b' <<<"$out" && fail "--no-extras still installed kitty:\n$out"
out=$(plan "$AMD" --no-aur)
grep -q 'from the AUR' <<<"$out" && fail "--no-aur still planned AUR packages:\n$out"
out=$(plan "$AMD" --no-upgrade)
grep -q 'pacman -Syu' <<<"$out" && fail "--no-upgrade still upgraded:\n$out"
grep -q 'pacman -Sy\b' <<<"$out" || fail "--no-upgrade did not refresh the databases:\n$out"

# --- packages that are already there are not reinstalled ------------------
STUB_INSTALLED='linux kitty dolphin pipewire' out=$(plan "$AMD")
grep -qE 'pacman -S --needed .*\bkitty\b' <<<"$out" && fail "reinstalled a package that is present:\n$out"

# --- a package that no longer exists must not abort the whole install -----
STUB_UNKNOWN='breeze-icons' out=$(plan "$AMD")
grep -q 'not in the repos, skipping: breeze-icons' <<<"$out" || fail "an unknown package was not reported:\n$out"
grep -qE 'pacman -S --needed .*breeze-icons' <<<"$out" && fail "an unknown package was still passed to pacman:\n$out"

# --- without --yes, an answer of no changes nothing -----------------------
: > "$log"
out=$(env -i PATH="$bin" HOME="$tmp" USER=tester STUB_LOG="$log" STUB_LSPCI="$AMD" \
        STUB_INSTALLED=linux STUB_UNKNOWN= STUB_ENABLED= \
        /usr/bin/bash "$bootstrap" <<<'n' 2>&1)
grep -q 'aborted' <<<"$out" || fail "answering no did not abort:\n$out"
[[ ! -s $log ]] || fail "answering no still changed something:\n$(cat "$log")"

# --- and with --yes it goes ahead without asking --------------------------
: > "$log"
env -i PATH="$bin" HOME="$tmp" USER=tester STUB_LOG="$log" STUB_LSPCI="$AMD" \
  STUB_INSTALLED=linux STUB_UNKNOWN= STUB_ENABLED= \
  /usr/bin/bash "$bootstrap" --yes --no-aur </dev/null >/dev/null 2>&1 || true
grep -q 'pacman -Syu' "$log" || fail "--yes did not upgrade:\n$(cat "$log")"
grep -q 'systemctl enable' "$log" || fail "--yes did not enable the system units:\n$(cat "$log")"

echo 'PASS: c7shell-bootstrap'
