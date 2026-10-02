#!/usr/bin/env bash
# Enforces docs/architecture.md. Run it directly: tests/test-native-boundary.sh
#
# Three checks, each with a `debt` table for code that predates the rule:
#   1. plumbing  -- system plumbing belongs to the C7 C++ plugin, not to QML
#   2. imports   -- no QML file imports a Quickshell integration module
#   3. spawners  -- no QML file starts a process
# A debt entry that no longer matches fails too, so every table only shrinks:
# delete the line in the same change that removes the use.
#
# Check 1 looks for a JS array literal that starts with one of the plumbing programs
# below -- the shape of every Process command, exec() and execDetached() argv in
# this tree. An argv assembled some other way slips past; review catches those.
#
# A hit passes only if its "file program" pair is in `allowed` (permanent, with
# the reason) or in `debt`.
set -euo pipefail

# shellcheck source=fixtures/harness.sh
. "$(dirname -- "$0")/fixtures/harness.sh"

plumbing='gdbus|busctl|dbus-send|nmcli|ip|systemctl|loginctl|rfkill|sh|bash|grep|ls|cat|find|mkdir|rm|gio|notify-send|python3|pacman|fprintd-[a-z]+|hyprctl|ddcutil|playerctl|pactl|wpctl|upower|c7-authd'

allowed=(
  # A shell inside the terminal the person opened: the process is the product.
  'Modules/Launcher/providers/AppsProvider.qml sh'
  'Modules/Launcher/providers/FilesProvider.qml sh'
  # A list of update sources, not a command.
  'Modules/Updates/RunView.qml pacman'
)

debt=(
  'Modules/Launcher/providers/ActionsProvider.qml sh'
  'Modules/SharePicker/PickerApp.qml sh'
  'Services/AirplaneService.qml rfkill'
  'Services/AppearanceStore.qml hyprctl'
  'Services/AppearanceStore.qml python3'
  'Services/AuthService.qml c7-authd'
  'Services/BrightnessService.qml busctl'
  'Services/BrightnessService.qml ddcutil'
  'Services/BrightnessService.qml ls'
  'Services/BrightnessService.qml sh'
  'Services/CaptureService.qml gio'
  'Services/CaptureService.qml mkdir'
  'Services/CaptureService.qml python3'
  'Services/CaptureService.qml rm'
  'Services/CaptureService.qml sh'
  'Services/DisplayService.qml hyprctl'
  'Services/EyeSaverService.qml hyprctl'
  'Services/EyeSaverService.qml sh'
  'Services/FingerprintService.qml busctl'
  'Services/FingerprintService.qml fprintd-delete'
  'Services/FingerprintService.qml fprintd-enroll'
  'Services/FingerprintService.qml fprintd-list'
  'Services/FingerprintService.qml grep'
  'Services/NetworkService.qml ip'
  'Services/NetworkService.qml nmcli'
  'Services/NotifServer.qml notify-send'
  'Services/PowerActions.qml systemctl'
  'Services/PowerService.qml sh'
  'Services/RecordingService.qml mkdir'
  'Services/ScreenshareService.qml systemctl'
  'Services/TunedService.qml gdbus'
  'Services/TunedService.qml pacman'
)

# ratchet NAME HITS ALLOWED DEBT MESSAGE -- fail on a hit in neither table, and
# on a debt entry that matches nothing.
ratchet() {
  local name=$1 hits=$2 allowed=$3 debt=$4 msg=$5 new stale
  new=$(comm -23 <(sort -u <<<"$hits") <(printf '%s\n%s\n' "$allowed" "$debt" | sort -u) | sed '/^$/d')
  [[ -z $new ]] || fail "$name: $msg:\n$new"
  stale=$(comm -13 <(sort -u <<<"$hits") <(sort -u <<<"$debt") | sed '/^$/d')
  [[ -z $stale ]] || fail "$name: these debt entries no longer match anything;
  delete them from tests/test-native-boundary.sh:\n$stale"
  echo "PASS: $name ($(sed '/^$/d' <<<"$debt" | wc -l) debt entries left)"
}

# 1. plumbing ----------------------------------------------------------------
hits=$(cd "$src" && grep -rnoE --include='*.qml' "\[[[:space:]]*\"($plumbing)\"" . \
  | sed -E 's|^\./||; s|:[0-9]+:\[[[:space:]]*"| |; s|"$||' || true)
ratchet plumbing "$hits" "$(printf '%s\n' "${allowed[@]}")" "$(printf '%s\n' "${debt[@]}")" \
  "QML runs system plumbing that the C7 plugin owns. Add the capability to a
  C7 backend and bind to it. \`allowed\` is only for argv a backend receives
  as data, never for a QML-started process"

# 2. imports -----------------------------------------------------------------
# A Quickshell integration module, imported anywhere in the shell. Qt and
# Quickshell's core (Quickshell, .Io, .Wayland, .Widgets) are the framework,
# not an integration, and are not listed.
external='Services\.[A-Za-z]+|Bluetooth|Networking|Hyprland|DBusMenu|I3|X11'
import_debt=(
  'Common/PopupSurface.qml Quickshell.Hyprland'
  'Common/PskField.qml Quickshell.Networking'
  'Modules/Auth/AuthWindow.qml Quickshell.Hyprland'
  'Modules/Bar/Bar.qml Quickshell.Hyprland'
  'Modules/Bar/StatusPill.qml Quickshell.Bluetooth'
  'Modules/Bar/StatusPill.qml Quickshell.Networking'
  'Modules/Bar/StatusPill.qml Quickshell.Services.Pipewire'
  'Modules/Bar/TrayPill.qml Quickshell.Hyprland'
  'Modules/Bar/TrayPill.qml Quickshell.Services.SystemTray'
  'Modules/Bar/WorkspacePips.qml Quickshell.Hyprland'
  'Modules/Capture/CaptureOverlay.qml Quickshell.Hyprland'
  'Modules/Capture/CountdownPill.qml Quickshell.Hyprland'
  'Modules/Capture/FinishedToast.qml Quickshell.Hyprland'
  'Modules/Launcher/CommandWindow.qml Quickshell.Hyprland'
  'Modules/Launcher/providers/WindowsProvider.qml Quickshell.Hyprland'
  'Modules/Osd/OsdPill.qml Quickshell.Hyprland'
  'Modules/Popovers/AudioPopover.qml Quickshell.Services.Pipewire'
  'Modules/Popovers/BluetoothPopover.qml Quickshell.Bluetooth'
  'Modules/Popovers/NotificationToasts.qml Quickshell.Hyprland'
  'Modules/Settings/ArrangeCanvas.qml Quickshell.Hyprland'
  'Modules/Settings/pages/AudioPage.qml Quickshell.Services.Pipewire'
  'Modules/Settings/pages/BluetoothPage.qml Quickshell.Bluetooth'
  'Modules/Settings/pages/DisplaysPage.qml Quickshell.Hyprland'
  'Modules/Updates/UpdateToast.qml Quickshell.Hyprland'
  'Services/AirplaneService.qml Quickshell.Bluetooth'
  'Services/AirplaneService.qml Quickshell.Networking'
  'Services/AppMenuService.qml Quickshell.Hyprland'
  'Services/AudioService.qml Quickshell.Services.Pipewire'
  'Services/BatteryService.qml Quickshell.Services.UPower'
  'Services/BluetoothService.qml Quickshell.Bluetooth'
  'Services/BrightnessService.qml Quickshell.Hyprland'
  'Services/DisplayService.qml Quickshell.Hyprland'
  'Services/MprisService.qml Quickshell.Services.Mpris'
  'Services/NetworkService.qml Quickshell.Networking'
  'Services/NotifServer.qml Quickshell.Services.Notifications'
  'Services/OsdSources.qml Quickshell.Hyprland'
  'Services/OsdSources.qml Quickshell.Services.Pipewire'
  'Services/PowerActions.qml Quickshell.Hyprland'
  'Services/RecordingService.qml Quickshell.Hyprland'
  'Services/ScreenshareService.qml Quickshell.Hyprland'
)
hits=$(cd "$src" && grep -rnoE --include='*.qml' "^import Quickshell\.($external)" . \
  | sed -E 's|^\./||; s|:[0-9]+:import | |' || true)
ratchet imports "$hits" "" "$(printf '%s\n' "${import_debt[@]}")" \
  "QML imports a Quickshell integration module. Integrations are C7
  backends behind a contract (docs/architecture.md); bind to the C7 singleton"

# 3. spawners ----------------------------------------------------------------
# A QML file that starts a process at all.
spawn_debt=(
  'Modules/Launcher/providers/ActionsProvider.qml'
  'Modules/Launcher/providers/FilesProvider.qml'
  'Modules/SharePicker/PickerApp.qml'
  'Services/AirplaneService.qml'
  'Services/AppearanceStore.qml'
  'Services/AuthService.qml'
  'Services/BluetoothService.qml'
  'Services/BrightnessService.qml'
  'Services/CaptureService.qml'
  'Services/DisplayService.qml'
  'Services/EyeSaverService.qml'
  'Services/FingerprintService.qml'
  'Services/NetworkService.qml'
  'Services/NotifServer.qml'
  'Services/PowerActions.qml'
  'Services/PowerService.qml'
  'Services/RecordingService.qml'
  'Services/ScreenshareService.qml'
  'Services/Terminal.qml'
  'Services/TunedService.qml'
  'Services/UpdatesService.qml'
)
hits=$(cd "$src" && grep -rlE --include='*.qml' 'Process[[:space:]]*\{|execDetached\(' . \
  | sed 's|^\./||' || true)
ratchet spawners "$hits" "" "$(printf '%s\n' "${spawn_debt[@]}")" \
  "QML starts a process. External programs are integrations: a C7 backend
  starts them with an async QProcess, and QML calls its action"
