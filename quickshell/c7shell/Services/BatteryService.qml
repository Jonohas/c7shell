pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import QtQuick
import qs.Services

// Everything the battery widget knows, in one place: the bar's indicator, its
// hover tooltip and the settings page's live preview are three views onto this
// singleton rather than three copies of the same UPower arithmetic.
//
// The one piece of real work here is the draw figure. UPower's EnergyRate is
// already in watts, but the raw value jitters by whole watts between reads --
// unreadable in a bar. Sample it on a fixed 2s tick and show the mean of the
// last five, which settles it without making a real change take longer than
// ten seconds to show.
Singleton {
  id: root

  readonly property var device: UPower.displayDevice

  // A desktop's display device is not a laptop battery, so the widget and the
  // settings section both go away rather than drawing an empty pill. Only
  // isLaptopBattery is consulted: UPower's composite display device does not
  // always populate IsPresent, and a false there would hide a real battery.
  readonly property bool present: root.device?.isLaptopBattery ?? false

  // 0..1, as UPower hands it over.
  readonly property real fraction: root.device?.percentage ?? 0
  readonly property int percent: Math.round(root.fraction * 100)

  readonly property int state: root.device?.state ?? 0
  readonly property bool charging: root.state === UPowerDeviceState.Charging
  readonly property bool full: root.state === UPowerDeviceState.FullyCharged
  // UPower's global "is the machine running off the pack", which is the honest
  // answer for a machine whose battery is idle on AC but not reported full.
  readonly property bool onAc: !UPower.onBattery

  // Direction comes from State, never from the sign of the rate: some firmware
  // reports EnergyRate unsigned while discharging, and inferring from it there
  // draws a charging arrow into a dying laptop.
  readonly property bool discharging: !root.charging && !root.onAc

  // Smoothed magnitude in watts. Never signed -- the sign is a display choice
  // made from `charging`.
  readonly property real watts: {
    if (root.samples.length === 0) return Math.abs(root.device?.changeRate ?? 0)
    return root.samples.reduce((a, b) => a + b, 0) / root.samples.length
  }

  // Sitting on AC with nothing meaningful moving. Reads as the words "on power"
  // rather than as "0.0 W", which looks like a broken sensor.
  readonly property bool idleOnPower: root.full || (root.onAc && root.watts < 0.5)

  readonly property bool warn: root.discharging
    && root.percent < ShellStore.batteryWarnBelow

  readonly property real energyWh: root.device?.energy ?? 0

  // quickshell reports health as a percentage on some versions and a fraction
  // on others; normalise rather than draw "0%" on a healthy pack.
  readonly property int health: {
    if (!(root.device?.healthSupported ?? false)) return -1
    const h = root.device.healthPercentage
    return Math.round(h <= 1 ? h * 100 : h)
  }

  // Seconds, or 0 when UPower has not worked out an estimate yet.
  readonly property real secondsLeft: root.charging
    ? (root.device?.timeToFull ?? 0)
    : (root.device?.timeToEmpty ?? 0)

  // -- formatting ------------------------------------------------------------

  // The signed draw as the bar shows it. `on power` when there is nothing to
  // report; otherwise sign, figure, unit -- never a bare unsigned number.
  readonly property string wattText: {
    if (root.idleOnPower) return "on power"
    const sign = root.charging ? "+" : "−"
    return `${sign}${root.watts.toFixed(ShellStore.batteryWattagePrecision)} W`
  }

  // What the pill reserves room for, so the bar never shifts as the draw
  // fluctuates. Measured from the widest string the field can ever hold, not
  // from the value currently in it.
  readonly property string widestWattText: {
    const n = (100).toFixed(ShellStore.batteryWattagePrecision)
    return `−${n} W`
  }

  // Whether the draw belongs in the bar at all right now.
  readonly property bool showWatts: ShellStore.batteryWattage
    && !(ShellStore.batteryWattageOnlyOnBattery && !root.discharging)

  function duration(seconds) {
    if (seconds <= 0) return "—"
    const total = Math.round(seconds / 60)
    const h = Math.floor(total / 60)
    const m = total % 60
    return h > 0 ? `${h} h ${m} m` : `${m} m`
  }

  // -- warn toast ------------------------------------------------------------
  // One toast per crossing, not one per UPower update. The latch clears on the
  // way back up so plugging in and unplugging again warns again.
  property bool warned: false

  onWarnChanged: {
    if (!root.warn) {
      root.warned = false
      return
    }
    if (root.warned) return
    root.warned = true
    NotifServer.send("battery low",
      `${root.percent}% remaining` + (root.secondsLeft > 0
        ? ` · about ${root.duration(root.secondsLeft)} left` : ""))
  }

  // -- draw sampling ---------------------------------------------------------
  property var samples: []

  Timer {
    running: root.present
    interval: 2000
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      const rate = Math.abs(root.device?.changeRate ?? 0)
      // A zero read while the machine is demonstrably running off the pack is a
      // transient firmware answer, not a real 0 W draw. Dropping it keeps the
      // mean from dipping every few samples on hardware that does this.
      if (rate === 0 && root.discharging) return
      root.samples = root.samples.concat([rate]).slice(-5)
    }
  }

  // A change of direction invalidates the window: averaging the tail of a
  // discharge into the head of a charge shows a figure that was never true.
  onChargingChanged: root.samples = []
  onOnAcChanged: root.samples = []

  // Cycle count is not on UPower's device interface; it is one file in sysfs
  // next to the one UPower itself is reading. Absent on plenty of packs, in
  // which case the tooltip simply drops the row.
  //
  // The DISPLAY device is a composite with no native path of its own, so the
  // path has to come off the real pack in the device list.
  readonly property var physical: UPower.devices.values.find(d => d.isLaptopBattery) ?? null

  readonly property int cycles: cyclesFile.path === ""
    ? 0 : (parseInt(cyclesFile.text().trim()) || 0)

  FileView {
    id: cyclesFile
    path: root.physical?.nativePath ? `${root.physical.nativePath}/cycle_count` : ""
    watchChanges: true
    // Most packs do not export this; that is not a fault worth logging.
    printErrors: false
    onFileChanged: cyclesFile.reload()
  }
}
