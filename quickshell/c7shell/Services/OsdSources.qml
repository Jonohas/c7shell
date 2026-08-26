import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import QtQuick
import qs.Services

// Every event that raises an OSD, in one place and with no UI: pipewire volume
// and mute, the backlight file, hyprland's layout and workspace switches.
// Instantiated once from shell.qml -- not a singleton, because nothing reads
// state off it and one instance is the whole point.
Scope {
  id: root

  // -- audio ------------------------------------------------------------------
  readonly property var sink: Pipewire.defaultAudioSink
  readonly property var micNode: Pipewire.defaultAudioSource
  readonly property var sinkAudio: root.sink?.audio ?? null
  readonly property var micAudio: root.micNode?.audio ?? null

  // Volume and muted arrive asynchronously once a node is tracked, and picking a
  // new default device rebinds the lot -- both land as ordinary change signals
  // that are not somebody pressing a key. Nothing shows until they settle.
  property bool armed: false
  onSinkAudioChanged: root.disarm()
  onMicAudioChanged: root.disarm()

  function disarm() {
    root.armed = false
    settle.restart()
  }

  function showSink() {
    if (!root.armed || !root.sinkAudio) return
    if (root.sinkAudio.muted) OsdManager.show("mute", {})
    else OsdManager.show("volume", { value: Math.round(root.sinkAudio.volume * 100) })
  }

  function showMic() {
    if (!root.armed || !root.micAudio) return
    // The hint is the mock's shortcut, not a bind this config has -- see
    // INTEGRATION.md before believing it.
    OsdManager.show("mic", { muted: root.micAudio.muted, hint: "super+m" })
  }

  // Any node whose volume/muted is read has to sit in a tracker or the values
  // never arrive.
  PwObjectTracker {
    objects: [root.sink, root.micNode].filter(node => node)
  }

  Timer {
    id: settle
    running: true
    interval: 800
    onTriggered: root.armed = true
  }

  Connections {
    target: root.sinkAudio
    // `volume` is the average of `volumes`, and volumesChanged is the only
    // signal behind it -- there is no volumeChanged to connect to.
    function onVolumesChanged() { root.showSink() }
    function onMutedChanged() { root.showSink() }
  }

  Connections {
    target: root.micAudio
    function onMutedChanged() { root.showMic() }
  }

  // -- brightness -------------------------------------------------------------
  // Only key steps raise a pill: BrightnessService also moves on its own startup
  // read and on anything else that writes the backlight, and neither is a
  // keypress. The service reports the percentage its own step produced.
  Connections {
    target: BrightnessService

    function onStepped(percentage) {
      OsdManager.show("brightness", { value: percentage })
    }
  }

  // -- keyboard layout --------------------------------------------------------
  // hyprland sends the xkb description ("English (US)"); the pill wants the
  // short code the user actually typed into kb_layout.
  readonly property var layoutCodes: ({
    "german": "de", "french": "fr", "spanish": "es", "italian": "it",
    "russian": "ru", "polish": "pl", "swedish": "se", "norwegian": "no"
  })

  function shortLayout(description) {
    const parenthesised = description.match(/\(([A-Za-z]{2,3})\)/)
    if (parenthesised) return parenthesised[1].toLowerCase()
    const name = description.replace(/\s*\(.*\)\s*$/, "").trim().toLowerCase()
    return root.layoutCodes[name] ?? name.slice(0, 2)
  }

  property string layout: ""

  Connections {
    target: Hyprland

    function onRawEvent(event) {
      if (event.name !== "activelayout") return
      // "<keyboard name>,<layout description>" -- device names can hold commas,
      // the layout cannot, so split from the right.
      const comma = event.data.lastIndexOf(",")
      if (comma < 0) return

      const next = root.shortLayout(event.data.slice(comma + 1))
      const previous = root.layout
      root.layout = next
      // An empty `previous` is hyprland announcing the layout it started with.
      if (previous !== "" && previous !== next)
        OsdManager.show("layout", { from: previous, to: next })
    }
  }

  // -- workspace --------------------------------------------------------------
  property int lastWorkspace: -1
  readonly property int workspace: Hyprland.focusedWorkspace?.id ?? -1
  onWorkspaceChanged: {
    const previous = root.lastWorkspace
    root.lastWorkspace = root.workspace
    // -1 covers both startup and the gap while hyprland moves focus.
    if (previous < 0 || root.workspace < 0) return
    OsdManager.show("workspace", {
      value: root.workspace,
      hint: root.workspace >= 1 && root.workspace <= 9 ? `super+${root.workspace}` : ""
    })
  }
}
