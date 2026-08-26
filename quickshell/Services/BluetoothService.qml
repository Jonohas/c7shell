pragma Singleton
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import QtQuick

// BlueZ, wrapped so the popover never touches a process. Battery comes from
// org.bluez.Battery1, which quickshell surfaces as device.battery /
// device.batteryAvailable.
Singleton {
  id: root

  readonly property var adapter: Bluetooth.defaultAdapter
  readonly property bool enabled: root.adapter?.enabled ?? false
  readonly property bool discovering: root.adapter?.discovering ?? false

  readonly property var connectedDevices: Bluetooth.devices.values
    .filter(d => d.connected)
    .sort((a, b) => root.label(a).localeCompare(root.label(b)))

  // Everything else, best candidates first: devices already paired, then ones
  // that at least told us a name, then bare MAC addresses.
  readonly property var nearby: Bluetooth.devices.values
    .filter(d => !d.connected)
    .sort((a, b) => (root.knownScore(b) - root.knownScore(a))
      || root.label(a).localeCompare(root.label(b)))

  // The popover writes this on open/close: discovery left running keeps the
  // radio busy and fills the list with strangers' devices for nothing.
  property bool wantScan: false

  Binding {
    target: root.adapter
    property: "discovering"
    // Paused while pairing — an active scan makes BlueZ's pairing attempt flaky.
    value: root.wantScan && root.enabled && !pair.running
    when: root.adapter !== null
  }

  function knownScore(dev) {
    return (dev.paired || dev.bonded ? 2 : 0) + (root.named(dev) ? 1 : 0)
  }

  function named(dev) {
    return (dev?.name ?? "") !== "" || (dev?.deviceName ?? "") !== ""
  }

  function label(dev) {
    if (!dev) return ""
    return dev.name || dev.deviceName || `unknown ${dev.address.slice(0, 5)}…`
  }

  // BlueZ's icon name is the only profile hint on the device, and it is exactly
  // the distinction the mock draws: "a2dp sink" for audio, "hid" for input.
  function profile(dev) {
    const icon = dev?.icon ?? ""
    if (icon.startsWith("audio")) return "a2dp sink"
    if (icon.startsWith("input")) return "hid"
    if (icon === "phone") return "phone"
    if (icon === "computer") return "computer"
    return icon !== "" ? icon : "device"
  }

  function subtitle(dev) {
    switch (dev?.state) {
    case BluetoothDeviceState.Connecting: return "connecting…"
    case BluetoothDeviceState.Disconnecting: return "disconnecting…"
    case BluetoothDeviceState.Connected: return `connected · ${root.profile(dev)}`
    }
    if (dev?.pairing || dev === pair.device) return "pairing…"
    return dev?.paired || dev?.bonded ? "not connected" : "not paired"
  }

  // battery is a 0-1 fraction, like UPower's percentage. -1 means the device
  // exposes no Battery1 interface.
  function batteryPercent(dev) {
    return dev?.batteryAvailable ? Math.round(dev.battery * 100) : -1
  }

  function setEnabled(on) {
    if (root.adapter) root.adapter.enabled = on
  }

  function scan() {
    if (!root.enabled) return
    root.wantScan = false
    resume.restart()
  }

  Timer {
    id: resume
    interval: 80
    onTriggered: root.wantScan = true
  }

  // One click does the one obvious thing for the state the device is in.
  function activate(dev) {
    if (dev.paired || dev.bonded) {
      if (dev.connected) dev.disconnect()
      else dev.connect()
    } else {
      root.pairDevice(dev)
    }
  }

  // BlueZ refuses to pair unless some process has registered an agent to answer
  // the confirmation, and quickshell registers none — so device.pair() fails on
  // its own. bluetoothctl brings its own agent; NoInputNoOutput accepts
  // "just works" pairings unattended, which covers headsets, mice and
  // controllers. A device insisting on a typed PIN still needs a real agent.
  function pairDevice(dev) {
    if (pair.running) {
      root.pairErrorAddress = dev?.address ?? ""
      root.pairErrorText = "another pairing is running"
      return
    }
    root.pairErrorAddress = ""
    root.pairErrorText = ""
    pair.device = dev
    pair.address = dev?.address ?? ""
    pair.running = true
  }

  // One pairing runs at a time, so one error slot is enough: the address it
  // belongs to, and the text the row shows in place of "pair". A timeout, a
  // refused agent and a PIN-required device all look identical from the outside
  // otherwise -- the row just reverted to "pair" and said nothing.
  property string pairErrorAddress: ""
  property string pairErrorText: ""

  function pairError(dev) {
    return dev && dev.address === root.pairErrorAddress ? root.pairErrorText : ""
  }

  // bluetoothctl prints the reason on stdout and still exits 0 for a timeout, so
  // "not paired when it finished" is the verdict and the output is the reason.
  function pairFailure(text, code) {
    const line = String(text).split("\n").reverse().find(l => /Failed|Error/i.test(l)) ?? ""
    const bluez = line.match(/org\.bluez\.Error\.(\w+)/)
    if (bluez) return bluez[1].replace(/([a-z])([A-Z])/g, "$1 $2").toLowerCase()
    if (/timed? ?out/i.test(text)) return "pairing timed out"
    return code === 0 ? "pairing failed" : `pairing failed (${code})`
  }

  function forget(dev) {
    dev.forget()
  }

  Process {
    id: pair

    property var device: null
    // The device object can go away with the scan; the address is what the row
    // is matched on afterwards.
    property string address: ""

    command: [
      "bluetoothctl", "--agent", "NoInputNoOutput", "--timeout", "25",
      "pair", pair.device?.address ?? ""
    ]

    stdout: StdioCollector { id: pairOut }
    stderr: StdioCollector { id: pairErr }

    // Trusted so the device reconnects by itself later, the way pairing from a
    // desktop settings panel behaves.
    onExited: (code, status) => {
      const dev = pair.device
      pair.device = null

      if (dev?.paired) {
        dev.trusted = true
        dev.connect()
        return
      }

      root.pairErrorAddress = pair.address
      root.pairErrorText = status !== 0
        ? "pairing was killed"
        : root.pairFailure(`${pairOut.text}\n${pairErr.text}`, code)
      console.warn(`bluetooth: pair ${pair.address} failed: ${root.pairErrorText}`)
    }
  }
}
