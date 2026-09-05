pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import QtQuick

// Everything the wifi popover needs to know, so the view stays a view. All the
// NetworkManager work is quickshell's own Networking module; only the IPv4
// address has to come from the kernel, because NetworkDevice.address is the MAC,
// and the gateway and the metered flag have to come from nmcli, because the
// module exports neither -- Network.nmSettings is a list of a type it does not
// export, so it is an opaque pointer from QML.
Singleton {
  id: root

  readonly property var device: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
  // 1i: the wire wins when both links are up; "none" drives the ✕ state.
  readonly property var ethDevice: Networking.devices.values.find(
    d => d.type === DeviceType.Wired && d.connected) ?? null
  readonly property string primary: root.ethDevice ? "ethernet"
    : root.connected ? "wifi" : "none"
  readonly property string primaryInterface: root.ethDevice?.name ?? root.device?.name ?? ""
  readonly property string interfaceName: root.device?.name ?? ""
  readonly property bool enabled: Networking.wifiEnabled
  readonly property bool hardwareEnabled: Networking.wifiHardwareEnabled
  readonly property bool scanning: root.device?.scannerEnabled ?? false

  readonly property var connected: root.device?.networks?.values?.find(n => n.connected) ?? null

  // Hidden SSIDs come through nameless and would render as blank rows. Saved
  // networks float to the top of the rest, then strongest signal first.
  readonly property var others: (root.device?.networks?.values ?? [])
    .filter(n => n.name !== "" && !n.connected)
    .slice()
    .sort((a, b) => (b.known - a.known) || (b.signalStrength - a.signalStrength))

  // What the views hand a Repeater, because the objects themselves cannot be:
  // a rebuilt JS array of WifiNetworks as `model` segfaults when one of them is
  // destroyed between a rescan and the next regenerate, and the ObjectModel
  // that is safe to pass comes in NetworkManager's own order, which is not
  // signal order at all. SSIDs are copies, so they can be sorted and the row
  // looks its network back up. Deduplicated: one row per name is what byName()
  // can resolve.
  //
  // Published deliberately rather than bound, because a Repeater handed a JS
  // array does not diff it -- it destroys and rebuilds every delegate, and the
  // password field a row grows underneath itself is delegate-local state. A
  // bound `otherNames` produced a fresh array on every signal-strength update
  // NetworkManager pushes, which is continuous while scanning, so a password
  // being typed was thrown away several times a second. Two guards, below.
  property var otherNames: []

  // First guard: republish only when the list content actually changed. Rows
  // bind to their network object directly, so bars and dBm still update live.
  // Second guard: while a row is asking for a key, do not republish at all --
  // a genuine reorder must not destroy the field being typed into.
  function refreshNames() {
    if (root.pskTarget !== "") return
    const next = root.others
      .map(n => n.name)
      .filter((name, i, all) => all.indexOf(name) === i)
    if (next.length === root.otherNames.length
      && next.every((name, i) => name === root.otherNames[i])) return
    root.otherNames = next
  }

  onOthersChanged: root.refreshNames()
  // The first evaluation of a binding does not necessarily emit its change
  // signal, and an empty list is not something to wait for a rescan to fix.
  Component.onCompleted: root.refreshNames()

  // SSID of the network currently being asked for a key, "" when none is.
  // PskField owns both ends of this; the list stays frozen until it clears.
  property string pskTarget: ""

  onPskTargetChanged: if (root.pskTarget === "") root.refreshNames()

  // Null once the network is gone, so the row unloads with it rather than
  // holding bindings onto a destroyed object.
  function byName(name) {
    return root.device?.networks?.values?.find(
      n => n.name === name && !n.connected) ?? null
  }

  // The popover writes this on open/close. Scanning left on keeps the radio
  // busy and the list churning behind a panel nobody is looking at.
  property bool wantScan: false

  Binding {
    target: root.device
    property: "scannerEnabled"
    value: root.wantScan && Networking.wifiEnabled
    when: root.device !== null
  }

  function setEnabled(on) {
    Networking.wifiEnabled = on
  }

  // NetworkManager rescans by itself while the scanner is on; dropping it for a
  // beat and turning it back on is what makes the button do something visible.
  function rescan() {
    if (!root.wantScan) return
    root.wantScan = false
    resume.restart()
  }

  Timer {
    id: resume
    interval: 80
    onTriggered: root.wantScan = true
  }

  // Whether this network can be joined without asking for a key first. Asking
  // NetworkManager to connect to a secured network it has no key for tears down
  // the association you are on and leaves a saved autoconnect profile behind
  // when it fails, so callers must collect the key and use connectWithPsk().
  function needsKey(net) {
    return net !== null && !net.known && root.secured(net)
  }

  // Refuses a network that needsKey() rather than trusting every caller to
  // check: this guard lived in one of the two wifi views, and the other one
  // shipped the teardown. Returns false when it refused, so a view can grow its
  // password field off the same call.
  function connect(net) {
    if (root.needsKey(net)) return false
    if (net.connected) net.disconnect()
    else net.connect()
    return true
  }

  function connectWithPsk(net, psk) {
    if (psk !== "") net.connectWithPsk(psk)
  }

  function forget(net) {
    net.forget()
  }

  // Only a bare PSK can be collected from a row; enterprise and WEP need
  // certificates or per-user credentials this popover cannot ask for.
  //
  // Null-safe, like securityLabel() next to it: a row's `network` binding can
  // go null a beat before the Loader holding it deactivates, and these are
  // read from bindings, so the gap is a TypeError in the log rather than
  // anything a caller can catch.
  function pskCapable(net) {
    return net?.security === WifiSecurityType.WpaPsk
      || net?.security === WifiSecurityType.Wpa2Psk
      || net?.security === WifiSecurityType.Sae
  }

  function secured(net) {
    if (!net) return false
    return net.security !== WifiSecurityType.Open && net.security !== WifiSecurityType.Unknown
  }

  // Lowercase, the way every other label in the shell is.
  function securityLabel(net) {
    switch (net?.security) {
    case WifiSecurityType.Sae:
    case WifiSecurityType.Wpa3SuiteB192: return "wpa3"
    case WifiSecurityType.Wpa2Psk:
    case WifiSecurityType.Wpa2Eap: return "wpa2"
    case WifiSecurityType.WpaPsk:
    case WifiSecurityType.WpaEap: return "wpa"
    case WifiSecurityType.StaticWep:
    case WifiSecurityType.DynamicWep:
    case WifiSecurityType.Leap: return "wep"
    case WifiSecurityType.Owe: return "owe"
    case WifiSecurityType.Open: return "open"
    }
    return "secured"
  }

  // NetworkManager reports a 0-1 quality, the mock shows dBm. NM derives that
  // quality as clamp(2 * (dBm + 100)) over -100..-50, so this is its inverse.
  function dbm(strength) {
    return Math.round(strength * 50 - 100)
  }

  // -- link details -------------------------------------------------------
  // Polled only while the popover or the wi-fi page is open; nothing here is
  // worth a timer behind a closed panel.
  property string ip: ""

  // The wi-fi link's own gateway, not the primary one: this is what the wi-fi
  // page shows, and it would be the wire's address half the time otherwise.
  property string gateway: ""

  // NetworkManager's own words for the wi-fi device: "yes", "no", "unknown", or
  // "yes (guessed)" / "no (guessed)" when the profile leaves it to NM and NM has
  // decided for itself.
  property string meteredState: ""

  readonly property bool metered: root.meteredState.startsWith("yes")

  // What the saved profile holds, which is the only one of the three a picker
  // can write: a guess means the profile says "unknown".
  readonly property string meteredChoice:
    root.meteredState === "" || root.meteredState === "unknown"
      || root.meteredState.includes("guessed") ? "unknown"
    : root.metered ? "yes" : "no"

  function clearDetails() {
    root.ip = ""
    root.gateway = ""
    root.meteredState = ""
  }

  onPrimaryInterfaceChanged: root.clearDetails()
  onInterfaceNameChanged: root.clearDetails()
  onWantScanChanged: if (!root.wantScan) root.clearDetails()

  // The poll stops when the association drops rather than reading back empty,
  // so the last gateway and metered flag would otherwise stay on screen.
  onConnectedChanged: if (root.connected === null) {
    root.gateway = ""
    root.meteredState = ""
  }

  // Metered is a property of the saved connection, so it is written to the
  // profile rather than the device. NetworkManager applies the change to a
  // currently activated connection immediately -- nothing is reactivated, and
  // the association is not dropped.
  function setMetered(choice) {
    if (root.interfaceName === "" || root.connected === null) return
    apply.choice = choice
    uuidRead.exec(["nmcli", "-t", "-f", "UUID,DEVICE", "connection", "show", "--active"])
  }

  Process {
    id: probe

    stdout: StdioCollector {
      // "2: wlan0    inet 10.0.0.5/24 brd 10.0.0.255 scope global wlan0"
      onStreamFinished: root.ip = text.match(/\binet (\d+(?:\.\d+){3})/)?.[1] ?? ""
    }

    // No `ip`, no such link, no permission: the card would otherwise just drop
    // the address with nothing anywhere saying why.
    onExited: (code, status) => {
      if (code === 0 && status === 0) return
      root.ip = ""
      console.warn(`network: ip addr show ${root.primaryInterface} exited ${code} (status ${status})`)
    }
  }

  // One field per call: -g prints the value alone, so there is nothing to parse
  // and an empty line is simply "no gateway on this link".
  Process {
    id: gwProbe

    stdout: StdioCollector { onStreamFinished: root.gateway = text.trim() }
    stderr: StdioCollector {}

    onExited: code => {
      if (code === 0) return
      root.gateway = ""
      console.warn(`network: nmcli gateway for ${root.interfaceName} exited ${code}`)
    }
  }

  Process {
    id: meteredProbe

    // A read that was already in flight when the picker was used would put the
    // old value back for a tick; the write's own readback is the newer truth.
    stdout: StdioCollector {
      onStreamFinished: if (!uuidRead.running && !apply.running) root.meteredState = text.trim()
    }
    stderr: StdioCollector {}

    onExited: code => {
      if (code === 0) return
      root.meteredState = ""
      console.warn(`network: nmcli metered for ${root.interfaceName} exited ${code}`)
    }
  }

  // The device names the profile that owns it, rather than the SSID naming it:
  // several saved profiles can carry the same name, and only one of them is up.
  Process {
    id: uuidRead

    stdout: StdioCollector {
      // One "<uuid>:<device>" a line. Neither field can hold a colon, so the
      // split needs no unescaping.
      onStreamFinished: {
        const uuid = text.split("\n")
          .find(l => l.endsWith(`:${root.interfaceName}`))
          ?.split(":")[0] ?? ""
        if (uuid === "") {
          console.warn(`network: no active profile on ${root.interfaceName}`)
          return
        }
        apply.exec(["nmcli", "connection", "modify", uuid, "connection.metered", apply.choice])
      }
    }
    stderr: StdioCollector {}
  }

  Process {
    id: apply

    // "yes", "no", or "unknown" to hand it back to NetworkManager's heuristics.
    property string choice: ""

    stderr: StdioCollector {
      onStreamFinished: if (text.trim() !== "") console.warn(`network: ${text.trim()}`)
    }

    // Only on success: a polkit refusal leaves the profile alone, and the poll
    // below would otherwise have three seconds to contradict the picker.
    onExited: code => { if (code === 0) root.meteredState = apply.choice }
  }

  Timer {
    interval: 3000
    repeat: true
    triggeredOnStart: true
    running: root.wantScan && root.primaryInterface !== "" && (root.connected !== null || root.ethDevice !== null)

    // exec() rather than assigning command and running: setting those two
    // separately leaves the process never started. argv, not `sh -c`: no shell
    // means nothing to quote and no interface-name guard to get wrong.
    onTriggered: {
      if (!probe.running)
        probe.exec(["ip", "-4", "-o", "addr", "show", root.primaryInterface])

      // Both are the wi-fi link's, and neither means anything without one.
      if (root.interfaceName === "" || root.connected === null) return
      if (!gwProbe.running)
        gwProbe.exec(["nmcli", "-g", "IP4.GATEWAY", "device", "show", root.interfaceName])
      if (!meteredProbe.running && !apply.running)
        meteredProbe.exec(["nmcli", "-g", "GENERAL.METERED", "device", "show", root.interfaceName])
    }
  }
}
