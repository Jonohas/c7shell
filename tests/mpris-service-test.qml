import QtQuick
import QtQuick.Window
import mpristest
import Quickshell.Services.Mpris

// Self-check for MprisService (run by tests/test-mpris.sh).
//
// Only one thing here is worth a test rather than a read-through, and it is the
// thing the issue calls "the most visible way this breaks": which player is the
// active one when several are registered. A browser tab plus a music client is
// the normal case, not the edge case, and picking wrong points the bar pill,
// the popover and the track OSD all at the wrong thing at once.
//
// The rule: last player to report Playing wins, falling back to the first
// registered.
Window {
  id: root
  visible: true
  width: 100; height: 100

  // Throws rather than calling Qt.exit(): Qt.exit() only *schedules* the exit,
  // so the enclosing function would run on and print the PASS line regardless
  // of what the check found.
  function check(cond, msg) {
    if (!cond) throw new Error(msg)
  }

  function player(name, title) {
    return fakePlayer.createObject(root, { identity: name, trackTitle: title, dbusName: `org.mpris.MediaPlayer2.${name}` })
  }

  Component {
    id: fakePlayer

    QtObject {
      property string identity: ""
      property string dbusName: ""
      property string trackTitle: ""
      property string trackArtist: ""
      property string trackAlbum: ""
      property string trackArtUrl: ""
      property int uniqueId: 1
      property int playbackState: MprisPlaybackState.Stopped
      property int loopState: MprisLoopState.None
      property real position: 0
      property real length: 0
      property bool lengthSupported: false
      property bool positionSupported: false
      property bool canControl: true
      property bool canSeek: false
      property bool canGoNext: true
      property bool canGoPrevious: true
      property bool canTogglePlaying: true
      property bool volumeSupported: false
      property bool shuffleSupported: false
      property bool loopSupported: false
      property real volume: 1
      property bool shuffle: false
    }
  }

  Component.onCompleted: {
    try {
      check(!MprisService.hasPlayer, "a bus with no players reported one anyway")
      check(MprisService.title === "", "no player, but a title")

      // -- fallback: first registered ---------------------------------------
      const browser = root.player("Firefox", "a video")
      Mpris.players.values = [browser]
      check(MprisService.hasPlayer, "a registered player did not reach hasPlayer")
      check(MprisService.player === browser,
        "with nothing playing the active player is not the first registered")

      const music = root.player("Spotify", "a song")
      Mpris.players.values = [browser, music]
      check(MprisService.player === browser,
        "a second registered player took over without ever playing")

      // -- last to report Playing wins --------------------------------------
      music.playbackState = MprisPlaybackState.Playing
      check(MprisService.player === music,
        "the player that started playing did not become the active one")
      check(MprisService.playing, "the active player is playing but the service says otherwise")
      check(MprisService.title === "a song", "the active player's title did not reach the service")

      browser.playbackState = MprisPlaybackState.Playing
      check(MprisService.player === browser,
        "the LAST player to report Playing did not win")

      // Pausing is not a handover: the pill should keep showing what you were
      // listening to, not jump to whatever else happens to be registered.
      browser.playbackState = MprisPlaybackState.Paused
      check(MprisService.player === browser,
        "pausing the active player handed the pill to another one")
      check(!MprisService.playing, "a paused player still reports playing")

      // -- a player that quits ----------------------------------------------
      // Nothing else notices the preference has gone stale, so `player` has to.
      Mpris.players.values = [music]
      check(MprisService.player === music,
        "the active player quit and the service did not fall back")
      Mpris.players.values = []
      check(!MprisService.hasPlayer, "every player quit and the service still reports one")
      check(MprisService.title === "", "no players left, but a title")

      // -- track identity ----------------------------------------------------
      // What the OSD compares against. It has to be empty while there is no
      // title, or the first real metadata reads as a track change.
      const solo = root.player("mpv", "")
      Mpris.players.values = [solo]
      check(MprisService.trackId === "", "a player with no title still produced a track id")
      solo.trackTitle = "first"
      const first = MprisService.trackId
      check(first !== "", "a titled track produced no track id")
      solo.trackTitle = "second"
      check(MprisService.trackId !== first, "two different tracks share a track id")

      // -- capabilities gate the controls -----------------------------------
      // A refused call is a Quickshell warning and a button that lied; every
      // control re-checks rather than trusting the caller.
      solo.canGoNext = false
      MprisService.next()   // must not throw and must not reach the player
      check(!MprisService.canGoNext, "canGoNext ignored the player saying no")
      solo.canSeek = true
      solo.positionSupported = false
      check(!MprisService.canSeek,
        "canSeek ignored positionSupported -- the scrubber would have nothing to draw")

      console.log("MPRIS-TEST-PASS")
      Qt.exit(0)
    } catch (e) {
      console.error("ASSERT-FAILED: " + e.message)
      Qt.exit(1)
    }
  }
}
