pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Networking
import QtQuick

// Airplane mode: every radio off, the wire untouched.
//
// The switch is rfkill, not NetworkManager and BlueZ, because rfkill is what
// the laptop's own airplane key throws -- going through it means the Fn key and
// this shell mean the same thing, and it is also the only way back out of a
// block the Fn key made (BlueZ refuses Powered=true while rfkill holds the
// adapter, which is the error this used to leave in the log).
//
// The state is derived from the radios rather than stored: a flag of our own
// would sit next to a kernel block that anything can set or clear, and did --
// the two radios going down one at a time raced the flag and cleared it again.
// So "every radio this machine has is off" IS airplane mode, whichever tool
// switched them off, and the bar's plane slot is one click back out of it.
Singleton {
  id: root

  readonly property bool hasWifi: Networking.devices.values.some(d => d.type === DeviceType.Wifi)
  readonly property bool hasBt: Bluetooth.defaultAdapter !== null
  readonly property bool wifiOn: Networking.wifiEnabled
  readonly property bool btOn: Bluetooth.defaultAdapter?.enabled ?? false

  readonly property bool enabled: (root.hasWifi || root.hasBt)
    && (!root.hasWifi || !root.wifiOn)
    && (!root.hasBt || !root.btOn)

  // Blocking goes through the radio properties as well as rfkill: NetworkManager
  // and BlueZ follow a kernel block on their own, but not synchronously, and the
  // bar should switch on the click rather than a beat later.
  function setEnabled(on) {
    root.restoring = !on
    rf.exec(["rfkill", on ? "block" : "unblock", "all"])
    if (!on) return
    Networking.wifiEnabled = false
    if (Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.enabled = false
  }

  property bool restoring: false

  // So a keybind can throw the mode on a laptop whose Fn key does not, and so
  // the two paths above can be exercised without a mouse.
  IpcHandler {
    target: "airplane"

    function toggle(): void { root.setEnabled(!root.enabled) }
    function set(on: bool): void { root.setEnabled(on) }
    function state(): string { return root.enabled ? "on" : "off" }
  }

  Process {
    id: rf

    onExited: (code, status) => {
      if (code !== 0 || status !== 0) {
        console.warn(`airplane: rfkill exited ${code} (status ${status})`)
        return
      }
      // Unblocking only lifts the kernel block; NetworkManager keeps wi-fi
      // switched off and BlueZ leaves the adapter down. Both are switched back
      // on here, once the block is actually gone -- doing it any earlier is the
      // "blocked by rfkill" refusal.
      if (!root.restoring) return
      Networking.wifiEnabled = true
      if (Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.enabled = true
    }
  }
}
