pragma Singleton
import Quickshell
import Quickshell.Services.Pipewire

// The Pipewire node vocabulary the 1g popover and the 1g settings page both
// speak. Pipewire is neither a process nor a dbus call, so this is not the
// usual process wrapper -- it exists because the filters were written twice and
// drifted, and the page's copy was dead for a whole release.
//
// Every node whose volume or mute is read has to sit in a PwObjectTracker or it
// never updates; one tracker here covers every view.
Singleton {
  id: root

  readonly property var output: Pipewire.defaultAudioSink
  readonly property var input: Pipewire.defaultAudioSource

  // Streams are individual applications, not devices, and video nodes carry no
  // audio interface at all -- neither belongs in a device list.
  readonly property var sinks: Pipewire.nodes.values.filter(n => !n.isStream && n.isSink && n.audio)
  readonly property var sources: Pipewire.nodes.values.filter(n => !n.isStream && !n.isSink && n.audio)

  // isSink, not properties["media.class"]: `properties` stays empty until a node
  // is bound by a tracker, and the only tracker is fed from this very list -- so
  // a media.class test can never match a stream it has not already found, and
  // the mixer stayed permanently empty. isSink is populated without binding.
  // For a stream isSink means "feeds a sink", i.e. playback; a recording stream
  // is a stream too and the mixer only mixes playback.
  readonly property var streams: Pipewire.nodes.values.filter(n => n.isStream && n.audio && n.isSink)

  // Short lists, so tracking all of them costs little and keeps the slider live
  // even for the device you are about to switch to.
  PwObjectTracker { objects: root.sinks.concat(root.sources).concat(root.streams) }

  function label(node) {
    return node ? (node.description || node.nickname || node.name) : "none"
  }

  function setVolume(node, v) {
    if (!node?.audio) return
    node.audio.muted = false
    node.audio.volume = v
  }

  function toggleMute(node) {
    if (node?.audio) node.audio.muted = !node.audio.muted
  }
}
