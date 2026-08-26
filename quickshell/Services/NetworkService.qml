pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import QtQuick

// Everything the wifi popover needs to know, so the view stays a view. All the
// NetworkManager work is quickshell's own Networking module; only the IPv4
// address has to come from the kernel, because NetworkDevice.address is the MAC.
Singleton {
  id: root

  readonly property var device: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
  // 1i: the wire wins when both links are up; "none" drives the ✕ state.
  readonly property var ethDevice: Networking.devices.values.find(
    d => d.type === DeviceType.Ethernet && d.connected) ?? null
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
    return !net.known && root.secured(net)
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
  function pskCapable(net) {
    return net.security === WifiSecurityType.WpaPsk
      || net.security === WifiSecurityType.Wpa2Psk
      || net.security === WifiSecurityType.Sae
  }

  function secured(net) {
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

  // -- IPv4 address -------------------------------------------------------
  // Polled only while the popover is open; nothing here is worth a timer
  // behind a closed panel.
  property string ip: ""

  onPrimaryInterfaceChanged: root.ip = ""
  onWantScanChanged: if (!root.wantScan) root.ip = ""

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

  Timer {
    interval: 3000
    repeat: true
    triggeredOnStart: true
    running: root.wantScan && root.primaryInterface !== "" && (root.connected !== null || root.ethDevice !== null)

    // exec() rather than assigning command and running: setting those two
    // separately leaves the process never started. argv, not `sh -c`: no shell
    // means nothing to quote and no interface-name guard to get wrong.
    onTriggered: {
      if (probe.running) return
      probe.exec(["ip", "-4", "-o", "addr", "show", root.primaryInterface])
    }
  }
}
