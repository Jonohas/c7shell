#!/usr/bin/env bash
# Self-check for the Bluetooth service singleton. Run it directly: tests/test-bluetooth.sh
#
# Same shape as test-mpris.sh and test-auth.sh: BluetoothService.qml is plain QML
# over two Quickshell modules, so it runs under qml6 offscreen with no
# compositor, no D-Bus and no bluetoothd. The Quickshell types are the same
# stubs test-auth.sh uses; Process gains a launch counter because *when* it is
# launched is the whole subject here.
#
# What this pins down is the pairing/discovery ordering. BlueZ will not reliably
# complete a pairing while the adapter is scanning -- the request goes out, the
# device never answers, and bluetoothctl exits 0 having done nothing at all, so
# the row silently reverts to "pair". Clearing the discovery binding is only a
# *request* to stop: the adapter reports the stop a D-Bus round-trip later. So
# the stub adapter deliberately does not go idle on demand, and the test asserts
# bluetoothctl has not been launched until it does.
set -euo pipefail

here=$(cd -- "$(dirname -- "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT

fail() { printf 'FAIL: %b\n' "$1" >&2; exit 1; }

command -v qml6 >/dev/null || {
  echo 'SKIP: qml6 not installed (package: qt6-declarative)'
  exit 0
}

mkdir -p "$tmp/bttest" "$tmp/Quickshell/Io" "$tmp/Quickshell/Bluetooth"
cp "$here/../quickshell/c7shell/Services/BluetoothService.qml" "$tmp/bttest/"
printf 'module bttest\nsingleton BluetoothService 1.0 BluetoothService.qml\n' > "$tmp/bttest/qmldir"

printf 'import QtQuick\nItem {}\n' > "$tmp/Quickshell/Singleton.qml"
printf 'module Quickshell\nSingleton 1.0 Singleton.qml\n' > "$tmp/Quickshell/qmldir"

# test-auth.sh's Process stub, plus `launches`. The service's Process is
# internal, and an Item stub lands in BluetoothService.children where the test
# can find it -- the Timers and the Binding are QtObjects and do not.
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
  function exec(argv) {}
  function signal(sig) {}
  // What the real Process does on `running = true`, minus the fork.
  onRunningChanged: if (running) { launches++; launchedCommand = command }
  // The real one clears `running` before reporting; the service reads both.
  function finish(code, status) { running = false; exited(code, status) }
}
PROC
printf 'import QtQuick\nItem { property string text: ""\n  signal streamFinished() }\n' \
  > "$tmp/Quickshell/Io/StdioCollector.qml"
printf 'module Quickshell.Io\nProcess 1.0 Process.qml\nStdioCollector 1.0 StdioCollector.qml\n' \
  > "$tmp/Quickshell/Io/qmldir"

# `discovering` does not follow a stop request: honorStop stays false until the
# test decides BlueZ has confirmed it, so a requested stop bounces straight
# back. That is the asynchrony the ordering exists for.
cat > "$tmp/Quickshell/Bluetooth/Bluetooth.qml" <<'QML'
pragma Singleton
import QtQuick
QtObject {
  property QtObject defaultAdapter: QtObject {
    property bool enabled: true
    property bool discovering: false
    property bool honorStop: false
    onDiscoveringChanged: if (!discovering && !honorStop) discovering = true
  }
  property QtObject devices: QtObject { property var values: [] }
}
QML
# Not a singleton with int properties: a QML property name may not begin with
# an upper case letter, so the states have to be a real enum on the type, which
# is how BluetoothDeviceState.Connected reads in the service either way.
cat > "$tmp/Quickshell/Bluetooth/BluetoothDeviceState.qml" <<'QML'
import QtQuick
QtObject {
  enum State { Disconnected = 0, Connecting = 1, Disconnecting = 2, Connected = 3 }
}
QML
printf 'module Quickshell.Bluetooth\nsingleton Bluetooth 1.0 Bluetooth.qml\nBluetoothDeviceState 1.0 BluetoothDeviceState.qml\n' \
  > "$tmp/Quickshell/Bluetooth/qmldir"

cat > "$tmp/case.qml" <<'QML'
import QtQuick
import Quickshell.Bluetooth
import bttest

Item {
  id: t

  property int failures: 0
  function check(name, ok) {
    console.log((ok ? "  ok   " : "  FAIL ") + name)
    if (!ok) t.failures++
  }

  // The smallest thing the service reads off a device.
  component Dev: QtObject {
    property string address: "28:FE:65:FD:1A:1C"
    property string name: "JVC HA-A9T"
    property string icon: "audio-headset"
    property bool paired: false
    property bool bonded: false
    property bool trusted: false
    property bool connected: false
    property bool pairing: false
    property int state: 0
    property int connects: 0
    function connect() { connects++ }
    function disconnect() {}
    function forget() {}
  }

  Dev { id: dev }

  readonly property var ad: Bluetooth.defaultAdapter
  property var proc: null

  function findProcess() {
    const kids = BluetoothService.children
    for (var i = 0; i < kids.length; i++)
      if (kids[i].launches !== undefined) return kids[i]
    return null
  }

  Component.onCompleted: {
    t.proc = t.findProcess()
    t.check("the service's process was found", t.proc !== null)
    if (t.proc === null) { console.log("FAILURES: 1"); Qt.exit(1) }

    // -- a pairing asked for mid-scan waits for the scan to actually stop ----
    BluetoothService.wantScan = true
    t.check("scan is running", t.ad.discovering === true)

    BluetoothService.pairDevice(dev)
    t.check("pairing is in flight", BluetoothService.pairing === true)
    t.check("row reads as pairing", BluetoothService.isPairing(dev) === true)
    t.check("subtitle reads as pairing", BluetoothService.subtitle(dev) === "pairing…")
    t.check("adapter has not gone idle yet", t.ad.discovering === true)
    t.check("bluetoothctl NOT launched while scanning", t.proc.launches === 0)

    // -- BlueZ confirms the stop; only now does the request go out ----------
    t.ad.honorStop = true
    t.ad.discovering = false
    t.check("bluetoothctl launched once idle", t.proc.launches === 1)
    t.check("pairs the right address",
            t.proc.launchedCommand.indexOf("28:FE:65:FD:1A:1C") !== -1)
    t.check("brings its own agent",
            t.proc.launchedCommand.indexOf("NoInputNoOutput") !== -1)

    // -- a successful pair is trusted and connected -------------------------
    dev.paired = true
    t.proc.finish(0, 0)
    t.check("paired device is trusted", dev.trusted === true)
    t.check("paired device is connected", dev.connects === 1)
    t.check("no error reported", BluetoothService.pairError(dev) === "")
    t.check("pairing is over", BluetoothService.pairing === false)

    stuck.start()
  }

  // -- an adapter that never goes idle must not strand the pairing ----------
  // Something outside this shell can hold a discovery session that our stop
  // does not clear. Pairing through one is flaky rather than impossible, so it
  // has to be attempted rather than silently never started.
  Timer {
    id: stuck
    interval: 50
    onTriggered: {
      t.ad.honorStop = false
      t.ad.discovering = true
      dev.paired = false
      dev.trusted = false
      BluetoothService.wantScan = true
      BluetoothService.pairDevice(dev)
      t.check("still not launched while stuck scanning", t.proc.launches === 1)
      deadline.start()
    }
  }

  Timer {
    id: deadline
    interval: 2200
    onTriggered: {
      t.check("launched anyway after the deadline", t.proc.launches === 2)
      console.log(t.failures === 0 ? "ALL PASS" : "FAILURES: " + t.failures)
      Qt.exit(t.failures === 0 ? 0 : 1)
    }
  }
}
QML

# QT_FORCE_STDERR_LOGGING: without a tty Qt sends its messages to journald,
# and every assertion in the case file is a console.log. Same as test-updates.sh.
log=$tmp/out.log
QT_QPA_PLATFORM=offscreen \
QT_FORCE_STDERR_LOGGING=1 \
timeout 30 qml6 -I "$tmp" "$tmp/case.qml" >"$log" 2>&1 \
  || fail "qml6 exited non-zero:\n$(cat "$log")"
sed 's/^qml: //' "$log"
grep -q 'ALL PASS' "$log" || fail "bluetooth service checks did not pass"
echo 'test-bluetooth.sh: all checks passed'
