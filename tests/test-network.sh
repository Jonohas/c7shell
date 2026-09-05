#!/usr/bin/env bash
# Self-check for the network service singleton. Run it directly: tests/test-network.sh
#
# Same shape as test-bluetooth.sh: NetworkService.qml is plain QML over two
# Quickshell modules, so it runs under qml6 offscreen with no compositor, no
# D-Bus and no NetworkManager. The Quickshell types are the usual stubs; Process
# records the argv it was handed, because the exact nmcli invocation is half of
# what this pins down.
#
# The other half is what NetworkManager says back. `nmcli -g GENERAL.METERED`
# answers with five different strings, and "yes (guessed)" means the opposite of
# "yes" as far as the picker is concerned -- it is NM deciding for itself
# because the saved profile said nothing, so the picker has to sit on "auto"
# rather than on "metered". Getting that backwards would silently write a
# setting the user never asked for onto every network they connect to.
set -euo pipefail

here=$(cd -- "$(dirname -- "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT

fail() { printf 'FAIL: %b\n' "$1" >&2; exit 1; }

command -v qml6 >/dev/null || {
  echo 'SKIP: qml6 not installed (package: qt6-declarative)'
  exit 0
}

mkdir -p "$tmp/nettest" "$tmp/Quickshell/Io" "$tmp/Quickshell/Networking"
cp "$here/../quickshell/c7shell/Services/NetworkService.qml" "$tmp/nettest/"
printf 'module nettest\nsingleton NetworkService 1.0 NetworkService.qml\n' > "$tmp/nettest/qmldir"

printf 'import QtQuick\nItem {}\n' > "$tmp/Quickshell/Singleton.qml"
printf 'module Quickshell\nSingleton 1.0 Singleton.qml\n' > "$tmp/Quickshell/qmldir"

# test-bluetooth.sh's Process stub. exec() is the only way in: the service never
# assigns `command` and `running` itself, so recording them here is enough, and
# leaving `running` true is what the real one does until the process exits --
# which is what stops the 3s poll from launching a second `ip` over the first.
cat > "$tmp/Quickshell/Io/Process.qml" <<'PROC'
import QtQuick
Item {
  property var command: []
  property bool running: false
  property var stdout: null
  property var stderr: null
  property int launches: 0
  property var launchedCommand: []
  signal exited(int code, int status)
  function exec(argv) { command = argv; launchedCommand = argv; launches++; running = true }
  function signal(sig) {}
  // What the collectors do when the stream closes, then what the process does
  // when it goes: the service reads both, and in that order.
  function say(text) { stdout.text = text; stdout.streamFinished() }
  function finish(code, status) { running = false; exited(code, status) }
}
PROC
printf 'import QtQuick\nItem { property string text: ""\n  signal streamFinished() }\n' \
  > "$tmp/Quickshell/Io/StdioCollector.qml"
printf 'module Quickshell.Io\nProcess 1.0 Process.qml\nStdioCollector 1.0 StdioCollector.qml\n' \
  > "$tmp/Quickshell/Io/qmldir"

cat > "$tmp/Quickshell/Networking/Networking.qml" <<'QML'
pragma Singleton
import QtQuick
QtObject {
  property bool wifiEnabled: true
  property bool wifiHardwareEnabled: true
  property QtObject devices: QtObject { property var values: [] }
}
QML
# Not singletons with int properties: a QML property name may not begin with an
# upper case letter, so the values have to be a real enum on the type -- which
# is how DeviceType.Wifi reads in the service either way.
cat > "$tmp/Quickshell/Networking/DeviceType.qml" <<'QML'
import QtQuick
QtObject {
  enum Type { Unknown = 0, Wired = 1, Wifi = 2 }
}
QML
cat > "$tmp/Quickshell/Networking/WifiSecurityType.qml" <<'QML'
import QtQuick
QtObject {
  enum Type {
    Unknown = 0, Open = 1, StaticWep = 2, DynamicWep = 3, Leap = 4,
    Owe = 5, WpaPsk = 6, WpaEap = 7, Wpa2Psk = 8, Wpa2Eap = 9,
    Sae = 10, Wpa3SuiteB192 = 11
  }
}
QML
printf 'module Quickshell.Networking\nsingleton Networking 1.0 Networking.qml\nDeviceType 1.0 DeviceType.qml\nWifiSecurityType 1.0 WifiSecurityType.qml\n' \
  > "$tmp/Quickshell/Networking/qmldir"

cat > "$tmp/case.qml" <<'QML'
import QtQuick
import Quickshell.Networking
import nettest

Item {
  id: t

  property int failures: 0
  function check(name, ok) {
    console.log((ok ? "  ok   " : "  FAIL ") + name)
    if (!ok) t.failures++
  }

  // The smallest thing the service reads off a wifi device and its networks.
  component Net: QtObject {
    property string name: "ConnectoPatronum"
    property bool connected: true
    property bool known: true
    property bool stateChanging: false
    property real signalStrength: 0.8
    property int security: WifiSecurityType.Wpa2Psk
  }
  component Dev: QtObject {
    property int type: DeviceType.Wifi
    property string name: "wlan0"
    property bool connected: true
    property bool scannerEnabled: false
    property QtObject networks: QtObject { property var values: [] }
  }

  Net { id: net }
  Dev { id: dev }

  // Found by what they were launched with, because ids are not reachable from
  // out here and child order is not a contract.
  function procBy(marker) {
    const kids = NetworkService.children
    for (var i = 0; i < kids.length; i++) {
      const c = kids[i]
      if (c.launchedCommand === undefined) continue
      if (c.launchedCommand.join(" ").indexOf(marker) !== -1) return c
    }
    return null
  }
  // The write process has not been launched yet when the test first needs it,
  // so it is picked out by the property only it carries.
  function applyProc() {
    const kids = NetworkService.children
    for (var i = 0; i < kids.length; i++)
      if (kids[i].choice !== undefined) return kids[i]
    return null
  }

  Component.onCompleted: {
    dev.networks.values = [net]
    Networking.devices.values = [dev]
    t.check("the wifi device is found", NetworkService.interfaceName === "wlan0")
    t.check("the connected network is found", NetworkService.connected === net)

    // triggeredOnStart posts its first tick rather than running it inline, so
    // everything that depends on the poll waits one turn of the event loop.
    NetworkService.wantScan = true
    tick.start()
  }

  Timer {
    id: tick
    interval: 80
    onTriggered: {
      // -- what the poll asks, and of which interface ----------------------
      const addr = t.procBy("addr show")
      const gw = t.procBy("IP4.GATEWAY")
      const met = t.procBy("GENERAL.METERED")
      t.check("the address is read from the kernel", addr !== null
        && addr.launchedCommand.join(" ") === "ip -4 -o addr show wlan0")
      // The wifi link's own, not the primary one: with a wire up as well the
      // primary is the wire, and this page would be showing its gateway.
      t.check("the gateway is read from the wifi device", gw !== null
        && gw.launchedCommand.join(" ") === "nmcli -g IP4.GATEWAY device show wlan0")
      t.check("metered is read from the wifi device", met !== null
        && met.launchedCommand.join(" ") === "nmcli -g GENERAL.METERED device show wlan0")
      if (addr === null || gw === null || met === null) return t.done()

      // -- what NetworkManager says back -----------------------------------
      gw.say("10.0.0.1\n")
      t.check("the gateway is taken as printed", NetworkService.gateway === "10.0.0.1")
      gw.say("\n")
      t.check("a link with no gateway reports none", NetworkService.gateway === "")
      gw.say("10.0.0.1\n")
      gw.finish(10, 0)
      t.check("a failed read drops the gateway", NetworkService.gateway === "")
      gw.say("10.0.0.1\n")

      // "guessed" is NetworkManager deciding for itself because the profile
      // said nothing: metered for now, but not a setting, so the picker sits on
      // auto rather than claiming the user asked for it.
      met.say("yes (guessed)\n")
      t.check("a guessed yes is metered", NetworkService.metered === true)
      t.check("a guessed yes is not a saved choice",
              NetworkService.meteredChoice === "unknown")
      met.say("no (guessed)\n")
      t.check("a guessed no is not metered", NetworkService.metered === false)
      t.check("a guessed no is not a saved choice",
              NetworkService.meteredChoice === "unknown")
      met.say("unknown\n")
      t.check("unknown is auto", NetworkService.meteredChoice === "unknown")
      met.say("no\n")
      t.check("a bare no is the saved choice", NetworkService.meteredChoice === "no")
      met.say("yes\n")
      t.check("a bare yes is the saved choice", NetworkService.meteredChoice === "yes")
      met.say("no\n")

      // -- writing the profile ---------------------------------------------
      NetworkService.setMetered("yes")
      const uuid = t.procBy("connection show --active")
      t.check("the active profiles are listed", uuid !== null
        && uuid.launchedCommand.join(" ")
           === "nmcli -t -f UUID,DEVICE connection show --active")
      if (uuid === null) return t.done()

      // A read already in flight when the picker was used must not put the old
      // value back underneath the write.
      met.say("no\n")
      t.check("a read in flight during a write is ignored",
              NetworkService.meteredChoice === "no")

      // The device picks the profile, not the SSID: "not-wlan0" and "vwlan0"
      // are here because endsWith() on a bare name would take either of them.
      uuid.say("aaa:eth0\nbbb:not-wlan0\nccc:vwlan0\nddd:wlan0\neee:docker0\n")
      const app = t.applyProc()
      t.check("the write goes to the profile on this device", app !== null
        && app.launchedCommand.join(" ")
           === "nmcli connection modify ddd connection.metered yes")
      if (app === null) return t.done()

      t.check("nothing is claimed before it lands",
              NetworkService.meteredChoice === "no")
      app.finish(0, 0)
      t.check("a landed write moves the picker", NetworkService.meteredChoice === "yes")

      // A polkit refusal leaves the profile alone, so the picker must not move.
      NetworkService.setMetered("no")
      uuid.say("ddd:wlan0\n")
      app.finish(4, 0)
      t.check("a refused write leaves the picker where it was",
              NetworkService.meteredChoice === "yes")

      // An SSID that is up on no profile of ours is not something to guess at.
      const before = app.launches
      NetworkService.setMetered("unknown")
      uuid.say("aaa:eth0\n")
      t.check("no profile on this device writes nothing", app.launches === before)

      // -- what is left on screen when the link goes -------------------------
      net.connected = false
      t.check("the connection is gone", NetworkService.connected === null)
      t.check("a dropped link drops the gateway", NetworkService.gateway === "")
      t.check("a dropped link drops metered", NetworkService.meteredState === "")
      t.check("a dropped link cannot be written to",
              NetworkService.setMetered("yes") === undefined && app.launches === before)

      net.connected = true
      NetworkService.wantScan = false
      t.check("a closed panel drops the address too", NetworkService.ip === "")

      t.done()
    }
  }

  function done() {
    console.log(t.failures === 0 ? "ALL PASS" : "FAILURES: " + t.failures)
    Qt.exit(t.failures === 0 ? 0 : 1)
  }
}
QML

# QT_FORCE_STDERR_LOGGING: without a tty Qt sends its messages to journald, and
# every assertion in the case file is a console.log. Same as test-bluetooth.sh.
log=$tmp/out.log
QT_QPA_PLATFORM=offscreen \
QT_FORCE_STDERR_LOGGING=1 \
timeout 30 qml6 -I "$tmp" "$tmp/case.qml" >"$log" 2>&1 \
  || fail "qml6 exited non-zero:\n$(cat "$log")"
sed 's/^qml: //' "$log"
grep -q 'ALL PASS' "$log" || fail "network service checks did not pass"
echo 'test-network.sh: all checks passed'
