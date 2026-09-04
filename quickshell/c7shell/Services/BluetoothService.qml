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

  // The popover writes this on open/close: discovery left running keeps the
  // radio busy and fills the list with strangers' devices for nothing.
  property bool wantScan: false

  // A pairing is in flight from the moment it is asked for -- including the
  // wait for the scan to stop -- until the process exits.
  readonly property bool pairing: root.pending !== null || pair.running

  Binding {
    target: root.adapter
    property: "discovering"
    // Paused for the whole pairing rather than just the process: an active scan
    // makes BlueZ's pairing attempt flaky, and asking for the stop is a D-Bus
    // round-trip the request has to wait out rather than race.
    value: root.wantScan && root.enabled && !root.pairing
    when: root.adapter !== null
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
    if (root.isPairing(dev)) return "pairing…"
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
    if (root.pairing) {
      root.pairErrorAddress = dev?.address ?? ""
      root.pairErrorText = "another pairing is running"
      return
    }
    root.pairErrorAddress = ""
    root.pairErrorText = ""
    pair.address = dev?.address ?? ""
    root.pending = dev
    settle.restart()
    // Already idle is the common case -- nothing to wait for.
    root.startPending()
  }

  // The device whose pairing is waiting on the scan, null the rest of the time.
  // Clearing the Binding above does not stop discovery by itself: BlueZ reports
  // it stopped a round-trip later, so the process starts from the property
  // actually going false rather than from having asked.
  property var pending: null

  function isPairing(dev) {
    return !!dev && (dev.pairing || dev === pair.device || dev === root.pending)
  }

  function startPending() {
    if (root.pending === null) return
    if (root.adapter?.discovering ?? false) return
    root.beginPair()
  }

  function beginPair() {
    settle.stop()
    pair.device = root.pending
    root.pending = null
    pair.running = true
  }

  Connections {
    target: root.adapter
    function onDiscoveringChanged() { root.startPending() }
  }

  Timer {
    id: settle
    interval: 1500
    // The scan never went idle, so something outside this shell holds a
    // discovery session. Pairing through one is flaky rather than impossible,
    // and silently never starting is worse than trying.
    onTriggered: if (root.pending !== null) root.beginPair()
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
        ?? Bluetooth.devices.values.find(d => d.address === pair.address)
        ?? null
      pair.device = null

      if (dev?.paired || dev?.bonded) {
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
