import QtQuick
import Quickshell.Networking
import qs.Common
import qs.Services

// Driven by tests/test-wifi.sh, which shims the Quickshell types this pulls
// in. The subject is NetworkService.otherNames: the SSID list both wifi views
// hand a Repeater, and therefore the thing whose every republish destroys and
// rebuilds every row -- including the password field a row grows underneath
// itself, with whatever has been typed into it so far.
Item {
  id: root

  // Throws rather than exiting: Qt.exit() only schedules the exit, so the rest
  // of the block ran on and the Qt.exit(0) at the end of it won.
  function check(ok, what) {
    if (!ok) throw new Error(what)
  }

  // Only what NetworkService reads off a network. Real properties, so the
  // service's bindings see the same change notifications they see from
  // NetworkManager.
  component FakeNet: QtObject {
    property string name: ""
    property bool known: false
    property bool connected: false
    property real signalStrength: 0
    property int security: WifiSecurityType.Wpa2Psk
    // PskField binds Connections to both of these; without them the file
    // loads with a "non-existent signal" warning instead of being tested.
    signal connectionFailed(int reason)
  }

  FakeNet { id: alpha; name: "alpha"; signalStrength: 0.9 }
  FakeNet { id: bravo; name: "bravo"; signalStrength: 0.5 }
  FakeNet { id: charlie; name: "charlie"; signalStrength: 0.3 }

  QtObject {
    id: device
    property int type: DeviceType.Wifi
    property string name: "wlan0"
    property bool connected: false
    property bool scannerEnabled: false
    readonly property var networks: ({ values: [alpha, bravo, charlie] })
  }

  // destroy() is deferred to the event loop, so the teardown check cannot be
  // made in the same block as the destroy that sets it up. Two phases, and
  // only the second one may declare a pass.
  function attempt(phase) {
    try {
      phase()
    } catch (e) {
      console.log(`WIFI-TEST-FAIL: ${e.message}`)
      Qt.exit(1)
      return false
    }
    return true
  }

  Component.onCompleted: if (root.attempt(root.run)) settle.start()

  Timer {
    id: settle
    interval: 1
    onTriggered: {
      if (!root.attempt(root.runAfterTeardown)) return
      console.log("WIFI-TEST-PASS")
      Qt.exit(0)
    }
  }

  function run() {
    Networking.deviceList = [device]

    // Sorted strongest first, which is the order the views draw.
    root.check(NetworkService.otherNames.join(",") === "alpha,bravo,charlie",
      `initial order was ${NetworkService.otherNames}`)

    // -- the bug ------------------------------------------------------------
    // A signal-strength update that does not change the order must not
    // republish the list. This is the one that fired several times a second
    // while scanning and took the password field with it every time.
    const before = NetworkService.otherNames
    alpha.signalStrength = 0.95
    bravo.signalStrength = 0.55
    root.check(NetworkService.otherNames === before,
      "a signal-strength update with no reorder republished the list")

    // A real reorder still reaches the views: nothing is being typed yet.
    charlie.signalStrength = 0.99
    root.check(NetworkService.otherNames.join(",") === "charlie,alpha,bravo",
      `a reorder did not reach the views: ${NetworkService.otherNames}`)

    // -- the freeze ---------------------------------------------------------
    // A row asking for a key claims pskTarget, and from then on even a real
    // reorder is held back, because republishing would destroy that row.
    NetworkService.pskTarget = "alpha"
    const frozen = NetworkService.otherNames
    bravo.signalStrength = 1.0
    root.check(NetworkService.otherNames === frozen,
      "the list reordered while a row was asking for a key")

    // Saved networks float to the top, and that reorder is held back too.
    charlie.known = true
    root.check(NetworkService.otherNames === frozen,
      "a network becoming known reordered the list mid-password")

    // Releasing publishes everything that accumulated, in one go.
    NetworkService.pskTarget = ""
    root.check(NetworkService.otherNames.join(",") === "charlie,bravo,alpha",
      `the list did not catch up after the field closed: ${NetworkService.otherNames}`)

    // -- rows still resolve -------------------------------------------------
    // byName() is how a row looks its network back up, and returns null once
    // it is gone so the row unloads rather than binding to a dead object.
    root.check(NetworkService.byName("bravo") === bravo, "byName lost a network")
    root.check(NetworkService.byName("nothing") === null,
      "byName invented a network that is not there")

    root.fieldClaimsAndReleases()
    root.fieldRefreezesOnAWrongPassword()
    root.fieldReleasesWhenTornDown()
  }

  // -- the other end of the freeze -----------------------------------------
  // PskField is what sets and clears pskTarget, and either half getting it
  // wrong is invisible: a leaked freeze means the list silently stops
  // updating for the rest of the session.
  Component {
    id: fieldComponent
    PskField { }
  }

  function makeField(net) {
    return fieldComponent.createObject(root, { network: net })
  }

  function fieldClaimsAndReleases() {
    const field = root.makeField(alpha)
    root.check(NetworkService.pskTarget === "", "a field froze the list before it asked")

    field.ask()
    root.check(NetworkService.pskTarget === "alpha",
      `ask() did not freeze the list: pskTarget is "${NetworkService.pskTarget}"`)

    field.collapse()
    root.check(NetworkService.pskTarget === "",
      "collapse() left the list frozen")
    field.destroy()
  }

  // A row can be destroyed with its network already gone, which is why the
  // field remembers the name it claimed rather than reading it back.
  function fieldReleasesWhenTornDown() {
    const field = root.makeField(bravo)
    field.ask()
    root.check(NetworkService.pskTarget === "bravo", "ask() did not freeze the list")

    // Null first: a row whose network is gone is exactly the case the field
    // remembers the claimed name for.
    field.network = null
    field.destroy()
  }

  // Phase two, once the destroy above has actually been processed.
  function runAfterTeardown() {
    root.check(NetworkService.pskTarget === "",
      "a torn-down row left the list frozen for good")
  }

  // NetworkManager answering NoSecrets re-asks without going through ask(),
  // which is why the claim hangs off `asking` rather than that function.
  function fieldRefreezesOnAWrongPassword() {
    const field = root.makeField(charlie)
    charlie.connectionFailed(ConnectionFailReason.NoSecrets)
    root.check(field.asking, "a NoSecrets failure did not re-open the field")
    root.check(NetworkService.pskTarget === "charlie",
      `a re-ask did not freeze the list: pskTarget is "${NetworkService.pskTarget}"`)

    // Connecting is what normally ends it, and it must unfreeze.
    charlie.connected = true
    root.check(NetworkService.pskTarget === "",
      "connecting left the list frozen")
    field.destroy()
  }
}
