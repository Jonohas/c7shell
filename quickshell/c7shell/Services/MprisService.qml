pragma Singleton
import Quickshell
import Quickshell.Services.Mpris
import QtQuick

// The one media player every now-playing surface reads (design 15b): the bar
// pill, the tray popover and the track-change OSD all bind to this, so none of
// them knows or cares which player is registered. MPRIS, not Spotify -- the
// same three surfaces drive mpv, a browser tab and Spotify alike.
//
// Two things here are not just forwarding, and both are the reason this is a
// singleton rather than three copies of `Mpris.players.values[0]`:
//
//   * which player is "the" player when several are registered, which is the
//     normal case (a browser tab plus a music client) and the most visible way
//     this breaks;
//   * `position`, which MPRIS does not push. It has to be pulled, and pulling
//     it costs CPU forever if nothing on screen is showing it.
Singleton {
  id: root

  // -- the active player ------------------------------------------------------

  // Last player to report Playing. A plain reference, deliberately not a
  // binding: it is a record of something that happened, and the players list
  // re-evaluating must not undo it.
  property var preferred: null

  readonly property var players: Mpris.players.values

  // Falls back to the first registered rather than to null: a paused player is
  // still worth a pill, and on login nothing has reported Playing yet.
  readonly property var player: {
    const list = root.players
    if (list.length === 0) return null
    // includes(), so a player that quit drops the preference on its own -- there
    // is nowhere else to notice it went away.
    if (root.preferred && list.includes(root.preferred)) return root.preferred
    return list[0]
  }

  // Everything currently playing, not just the active one. A Connections on
  // `player` would only ever watch the player that is ALREADY active, so it
  // could never notice another one starting -- which is the whole rule.
  // Reading each player's state inside the filter is what subscribes this to
  // all of them at once.
  readonly property var playingNow: root.players.filter(p =>
    p.playbackState === MprisPlaybackState.Playing)

  // The previous membership of that list, so a re-evaluation can be asked what
  // is new in it rather than just that it changed. Plain state, not a binding.
  property var wasPlaying: []

  onPlayingNowChanged: {
    const started = root.playingNow.filter(p => !root.wasPlaying.includes(p))
    root.wasPlaying = root.playingNow
    // Last, not first: two players starting in the same frame is the shell
    // restarting under both, and the later one is the more recent event.
    if (started.length > 0) root.preferred = started[started.length - 1]
  }

  // -- what the surfaces read -------------------------------------------------

  readonly property bool hasPlayer: root.player !== null
  // "Spotify", "Firefox" -- the popover's source line.
  readonly property string identity: root.player?.identity ?? ""
  // Stable enough to tell "the active player changed" from "the track changed":
  // the dbus name is unique per player and constant for its lifetime.
  readonly property string playerId: root.player?.dbusName ?? ""

  readonly property string title: root.player?.trackTitle ?? ""
  readonly property string artist: root.player?.trackArtist ?? ""
  readonly property string album: root.player?.trackAlbum ?? ""
  // Passed to an Image as-is: players hand out http(s) and file: URLs and Qt
  // loads both. Empty is the placeholder case, which every surface handles --
  // a broken image is never drawn.
  readonly property string artUrl: root.player?.trackArtUrl ?? ""

  // Identity of the CURRENT TRACK, for the OSD to compare against. uniqueId
  // alone is not enough: it is only unique within one player, so two players
  // can hold the same id, and the title is what a person would call the track.
  readonly property string trackId: root.title === ""
    ? "" : `${root.player?.uniqueId ?? 0}␟${root.title}`

  readonly property bool playing: root.player?.playbackState === MprisPlaybackState.Playing

  // Seconds, both of them -- Quickshell converts MPRIS's microseconds. `length`
  // reads back as `position` when the player does not report one, so the
  // scrubber tests lengthSupported rather than length > 0.
  readonly property real position: root.player?.position ?? 0
  readonly property real length: root.lengthKnown ? root.player.length : 0
  readonly property bool lengthKnown: (root.player?.lengthSupported ?? false)
    && (root.player?.length ?? 0) > 0

  readonly property bool canControl: root.player?.canControl ?? false
  readonly property bool canGoNext: root.player?.canGoNext ?? false
  readonly property bool canGoPrevious: root.player?.canGoPrevious ?? false
  // positionSupported as well as canSeek: a player can accept a relative seek
  // and still report no position, and a scrubber with no position to draw is
  // not something to hand a drag to.
  readonly property bool canSeek: (root.player?.canSeek ?? false)
    && (root.player?.positionSupported ?? false)
  readonly property bool canTogglePlaying: root.player?.canTogglePlaying ?? false

  readonly property bool volumeSupported: root.player?.volumeSupported ?? false
  readonly property real volume: root.player?.volume ?? 0

  readonly property bool shuffleSupported: (root.player?.shuffleSupported ?? false) && root.canControl
  readonly property bool shuffle: root.player?.shuffle ?? false
  readonly property bool loopSupported: (root.player?.loopSupported ?? false) && root.canControl
  readonly property int loopState: root.player?.loopState ?? MprisLoopState.None

  // -- controls ---------------------------------------------------------------
  // Every one of these re-checks its capability rather than trusting the caller:
  // a disabled button is the UI's job, but a player can drop a capability
  // between the render and the click, and Quickshell warns on a refused call.

  function next() { if (root.canGoNext) root.player.next() }
  function previous() { if (root.canGoPrevious) root.player.previous() }
  function playPause() { if (root.canTogglePlaying) root.player.togglePlaying() }

  // Absolute, in seconds -- what a scrubber produces. MprisPlayer.seek() is
  // relative, so the write goes to `position` instead.
  function setPosition(seconds) {
    if (!root.canSeek) return
    root.player.position = Math.max(0, Math.min(root.length, seconds))
  }

  // Relative, in seconds, for the media keys' nudge.
  function seek(seconds) { if (root.canSeek) root.player.seek(seconds) }

  function setVolume(v) {
    if (!root.volumeSupported || !root.canControl) return
    root.player.volume = Math.max(0, Math.min(1, v))
  }

  function toggleShuffle() { if (root.shuffleSupported) root.player.shuffle = !root.player.shuffle }

  // None → Playlist → Track → None. The order the transport button cycles.
  function cycleLoop() {
    if (!root.loopSupported) return
    switch (root.loopState) {
      case MprisLoopState.None: root.player.loopState = MprisLoopState.Playlist; break
      case MprisLoopState.Playlist: root.player.loopState = MprisLoopState.Track; break
      default: root.player.loopState = MprisLoopState.None
    }
  }

  // -- position polling -------------------------------------------------------
  // MprisPlayer.position does not update on its own (Quickshell suppresses the
  // property updates on purpose); re-emitting positionChanged is what makes a
  // binding on it re-evaluate. So it costs a timer, and the timer only earns
  // its keep while something is drawing a scrubber.
  //
  // Surfaces bracket their own visibility with watchPosition(true/false)
  // instead of a bool, because there can legitimately be more than one on
  // screen at once and the last one to close must not silence the others.
  property int positionWatchers: 0

  function watchPosition(on) {
    root.positionWatchers = Math.max(0, root.positionWatchers + (on ? 1 : -1))
  }

  Timer {
    // Paused is a position that does not move, so polling it is pure waste --
    // and the value on screen is already correct.
    running: root.positionWatchers > 0 && root.playing && root.player !== null
    interval: 500   // twice a second: the scrubber is 270px wide, a second is a pixel
    repeat: true
    onTriggered: root.player.positionChanged()
  }
}
