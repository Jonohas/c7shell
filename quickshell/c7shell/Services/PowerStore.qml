pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// The power page's preferences: which tuned profile each of the three buttons
// means, what should happen on unplug, and the suspend/screen timings.
//
// Two deliberate departures from the power handoff:
//
//   * The file is ~/.config/hypr/power.json, not ~/.config/c7shell/power.json.
//     FileView cannot create a missing parent directory, so a fresh
//     ~/.config/c7shell would silently never persist. c7shell-setup guarantees
//     ~/.config/hypr exists, and shell.json, appearance.json and displays.json
//     are already there -- see the note at the top of ShellStore.
//   * Keys are flat (profilePowersave, …) rather than nested
//     (profiles.powersave). quickshell 0.3.1's JsonAdapter has no nested
//     JsonObject, so the nested form is not expressible at all.
//
// The profile mapping is the point of the file: a user with hand-written tuned
// profiles repoints the three buttons here without the UI knowing anything
// changed.
Singleton {
  id: root

  readonly property alias values: adapter

  property bool ready: false

  // -- profile mapping --
  // UI key -> tuned profile name. The three the handoff names, and nothing
  // else: everything past them lives behind "see all N tuned profiles".
  readonly property string profilePowersave: root.values.profilePowersave
  readonly property string profileBalanced: root.values.profileBalanced
  readonly property string profilePerformance: root.values.profilePerformance

  // The three, as the UI iterates them. Order is the trade-off axis, left to
  // right, and both the cards and the popover rows read it from here so they
  // cannot disagree about which end is which.
  readonly property var profiles: [
    {
      key: "powersave",
      tuned: root.profilePowersave,
      label: "powersave",
      icon: "leaf",
      blurb: "Caps boost, favours the efficient cores, dims the panel a step. Quiet, and roughly double the runtime.",
      boost: "off"
    },
    {
      key: "balanced",
      tuned: root.profileBalanced,
      label: "balanced",
      icon: "gauge",
      blurb: "Boost on demand, fans stay off until they have to move. The default, and the one the shell falls back to.",
      boost: "on demand"
    },
    {
      key: "performance",
      tuned: root.profilePerformance,
      label: "performance",
      icon: "zap",
      blurb: "Everything unlocked, no latency saving. Audible under load, and it will not last an afternoon on battery.",
      boost: "always"
    }
  ]

  function profileFor(key) {
    return root.profiles.find(p => p.key === key) ?? null
  }

  // Which of the three, if any, a tuned profile name is. "" for a profile the
  // three buttons do not cover -- which is a state the UI has to show honestly
  // rather than lighting up the nearest card.
  function keyForTuned(name) {
    const p = root.profiles.find(p => p.tuned === name)
    return p ? p.key : ""
  }

  // -- switching --
  readonly property bool autoSwitch: root.values.autoSwitch
  readonly property string onBatteryProfile: root.values.onBatteryProfile
  readonly property string onPowerProfile: root.values.onPowerProfile
  // Whole percent. Crossing it while discharging drops to powersave and says so.
  readonly property int dropBelow: root.values.dropBelow

  // -- suspend & screen --
  // Seconds throughout, because that is what hypridle's config takes; the page
  // presents them in minutes.
  readonly property int blankScreen: root.values.blankScreen
  readonly property int lockAfterBlank: root.values.lockAfterBlank
  readonly property int suspendOnBattery: root.values.suspendOnBattery
  readonly property string lidClose: root.values.lidClose

  // -- learned draw ----------------------------------------------------------
  // Median observed watts per profile, per machine. The handoff is explicit
  // that the idle-draw figures are measured rather than hard-coded: a 15 W
  // "performance" printed on a fanless tablet is a lie the UI would be telling
  // about the machine it is running on.
  //
  // 0 means "not learned yet", and every consumer falls back to the live draw.
  readonly property real drawPowersave: root.values.drawPowersave
  readonly property real drawBalanced: root.values.drawBalanced
  readonly property real drawPerformance: root.values.drawPerformance

  function learnedDraw(key) {
    switch (key) {
    case "powersave": return root.drawPowersave
    case "balanced": return root.drawBalanced
    case "performance": return root.drawPerformance
    }
    return 0
  }

  function setLearnedDraw(key, watts) {
    switch (key) {
    case "powersave": root.values.drawPowersave = watts; break
    case "balanced": root.values.drawBalanced = watts; break
    case "performance": root.values.drawPerformance = watts; break
    }
  }

  FileView {
    id: file

    path: `${Quickshell.env("HOME")}/.config/hypr/power.json`
    watchChanges: true
    printErrors: false

    onFileChanged: file.reload()
    onAdapterUpdated: file.writeAdapter()
    onLoaded: root.ready = true
    onLoadFailed: err => {
      if (err !== FileViewError.FileNotFound) return
      root.ready = true
      file.writeAdapter()
    }

    JsonAdapter {
      id: adapter

      property string profilePowersave: "powersave"
      property string profileBalanced: "balanced"
      property string profilePerformance: "throughput-performance"

      property bool autoSwitch: true
      property string onBatteryProfile: "powersave"
      property string onPowerProfile: "balanced"
      property int dropBelow: 20

      property int blankScreen: 300
      property int lockAfterBlank: 30
      property int suspendOnBattery: 1200
      property string lidClose: "suspend"

      property real drawPowersave: 0
      property real drawBalanced: 0
      property real drawPerformance: 0
    }
  }
}
