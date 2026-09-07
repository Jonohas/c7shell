import QtQuick
import qs.Theme
import qs.Common
import qs.Services

// Design 15b, tray popover: art · title · artist · source · scrubber · full
// transport. 300px, MPRIS-driven, so the same panel drives whatever is playing.
//
// The design's "next up" row is not here and cannot be: MPRIS exposes no queue
// at all, and inventing one per player is exactly the Spotify-specific coupling
// the rest of this design avoids. The panel ends at the transport row.
GlassPopover {
  id: root

  name: "media"
  panelWidth: 300

  // MediaPill is the one anchor in the bar that resizes on its own: its title
  // is capped at 150px but not fixed at it, so a two-word track after a long
  // one narrows the pill. Centred, that would slide this panel half of every
  // such change; pinned to the pill's right edge, which does not move, the
  // panel stays where the user left it across a whole album.
  pinRight: true

  // position does not update on its own -- the service polls it, and only while
  // something is asking. This panel is that something, for as long as it is up.
  // Bracketed on `open` rather than on `visible`: the window stays mapped
  // through the 150ms fade-out, and half a second of polling a panel nobody can
  // see any more is not worth the arithmetic.
  onOpenChanged: MprisService.watchPosition(root.open)
  // The shell going down with the panel open would otherwise leave the count
  // raised and the timer running for the life of the process.
  Component.onDestruction: if (root.open) MprisService.watchPosition(false)

  // Closing the player closes the panel. The pill it hangs off hides itself
  // when the last player quits, and a panel left anchored to an invisible pill
  // is a floating box of dead controls -- there is nothing left to drive.
  Connections {
    target: MprisService
    function onHasPlayerChanged() {
      if (!MprisService.hasPlayer && root.open) PopoverManager.close()
    }
  }

  // -- header: art, title, artist, source ------------------------------------
  Row {
    width: parent.width
    spacing: 12

    Rectangle {
      id: art
      width: 66; height: 66
      radius: Theme.radiusRow
      color: Theme.surface07
      border.width: 1
      border.color: Theme.hairline
      clip: true

      // Underneath the art rather than instead of it: a player between tracks
      // drops its art url for a frame, and swapping the two would flicker.
      Icon {
        anchors.centerIn: parent
        name: "music"
        size: 24
        tint: Theme.text3
      }

      Image {
        anchors.fill: parent
        source: MprisService.artUrl
        fillMode: Image.PreserveAspectCrop
        visible: status === Image.Ready
        asynchronous: true
        sourceSize: Qt.size(132, 132)
      }
    }

    Column {
      width: parent.width - art.width - parent.spacing
      spacing: 3
      anchors.verticalCenter: parent.verticalCenter

      Text {
        width: parent.width
        elide: Text.ElideRight
        // Space Grotesk: the design's rule is that only titles get the display
        // face, and this is the one title on the panel.
        text: MprisService.title || "nothing playing"
        font { family: Theme.fontDisplay; pixelSize: 12; weight: 600 }
        color: Theme.text
      }
      Text {
        width: parent.width
        elide: Text.ElideRight
        visible: text !== ""
        text: MprisService.artist
        font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
        color: Theme.text2
      }
      Text {
        width: parent.width
        elide: Text.ElideRight
        // The source line: the album if the player gives one, and always which
        // player it is -- the panel is not Spotify's, and it should say so.
        text: MprisService.album
          ? `${MprisService.album} · ${MprisService.identity.toLowerCase()}`
          : MprisService.identity.toLowerCase()
        font { family: Theme.fontMono; pixelSize: 9; weight: 400 }
        color: Theme.text3
      }
    }
  }

  // -- scrubber ---------------------------------------------------------------
  // Only drawn when the player reports a length. Without one there is no
  // fraction to fill and a full-width empty track reads as a stalled download.
  Row {
    width: parent.width
    spacing: 9
    visible: MprisService.lengthKnown

    Text {
      anchors.verticalCenter: parent.verticalCenter
      width: 30
      text: root.clock(MprisService.position)
      font { family: Theme.fontMono; pixelSize: 9 }
      color: Theme.text3
    }

    CrimsonSlider {
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - 78
      // The design's 3px track, and no thumb: a knob invites a drag, and on a
      // player that cannot seek there is nothing to drag it to.
      trackHeight: 3
      thumb: MprisService.canSeek
      value: MprisService.lengthKnown
        ? MprisService.position / MprisService.length : 0
      // moved() only ever fires from a press or a drag, and MprisService
      // refuses the write when canSeek is false -- but a slider that silently
      // eats the click is worse than one that does not take it, so the
      // MouseArea is disabled outright.
      enabled: MprisService.canSeek
      onMoved: fraction => MprisService.setPosition(fraction * MprisService.length)
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      width: 30
      horizontalAlignment: Text.AlignRight
      text: root.clock(MprisService.length)
      font { family: Theme.fontMono; pixelSize: 9 }
      color: Theme.text3
    }
  }

  // -- transport --------------------------------------------------------------
  Item {
    width: parent.width
    implicitHeight: transport.implicitHeight

    Row {
      id: transport
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 18

      // Shuffle and repeat only where the player actually has them: a dead
      // button that looks live is the failure mode the issue calls out, so an
      // unsupported one is not drawn at all and the row closes up.
      TransportButton {
        anchors.verticalCenter: parent.verticalCenter
        visible: MprisService.shuffleSupported
        icon: "shuffle"
        on: MprisService.shuffle
        onTriggered: MprisService.toggleShuffle()
      }
      TransportButton {
        anchors.verticalCenter: parent.verticalCenter
        icon: "skip-back"
        enabled: MprisService.canGoPrevious
        onTriggered: MprisService.previous()
      }

      // The primary action, and the only filled control on the panel: a 30px
      // A Theme.text disc with a dark glyph, per the design.
      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: 30; height: 30
        radius: 15
        color: MprisService.canTogglePlaying
          ? (playMouse.containsMouse ? Theme.textOnAccent : Theme.text)
          : Theme.alpha(Theme.text, 0.25)

        Icon {
          anchors.centerIn: parent
          // Offset because a triangle's optical centre is left of its bounding
          // box; the pause bars are symmetric and need no nudge.
          anchors.horizontalCenterOffset: MprisService.playing ? 0 : 1
          name: MprisService.playing ? "pause" : "play"
          size: 11
          tint: Theme.bg
        }

        MouseArea {
          id: playMouse
          anchors.fill: parent
          hoverEnabled: true
          enabled: MprisService.canTogglePlaying
          onClicked: MprisService.playPause()
        }
      }

      TransportButton {
        anchors.verticalCenter: parent.verticalCenter
        icon: "skip-forward"
        enabled: MprisService.canGoNext
        onTriggered: MprisService.next()
      }
      TransportButton {
        anchors.verticalCenter: parent.verticalCenter
        visible: MprisService.loopSupported
        // repeat-1 is the same glyph with a "1" in it: track repeat and
        // playlist repeat are different states and must not look identical.
        icon: MprisService.loopState === root.loopTrack ? "repeat-1" : "repeat"
        on: MprisService.loopState !== root.loopNone
        onTriggered: MprisService.cycleLoop()
      }
    }
  }

  // MprisLoopState lives in Quickshell.Services.Mpris, which is a service
  // module and has no business being imported into a view -- these are the two
  // values this panel compares against.
  readonly property int loopNone: 0
  readonly property int loopTrack: 1

  // mm:ss. Seconds, straight from MprisService; a track over an hour long
  // simply counts past 60 minutes rather than growing an hours field, which
  // would change the label's width mid-track.
  function clock(seconds) {
    if (!(seconds > 0)) return "0:00"
    const total = Math.floor(seconds)
    return `${Math.floor(total / 60)}:${`${total % 60}`.padStart(2, "0")}`
  }

  // -- delegates --------------------------------------------------------------

  // A 14px glyph in a 26px hit target: the design draws bare icons 18px apart,
  // which is a 14px click target, and that is too small to hit reliably.
  component TransportButton: Item {
    id: button

    property string icon
    // Lit, as shuffle and repeat are when they are on.
    property bool on: false
    signal triggered()

    implicitWidth: 26
    implicitHeight: 26
    opacity: button.enabled ? 1 : 0.35

    Icon {
      anchors.centerIn: parent
      name: button.icon
      size: 14
      tint: button.on ? Theme.accentSoft
        : buttonMouse.containsMouse ? Theme.text
        : Theme.text2
    }

    MouseArea {
      id: buttonMouse
      anchors.fill: parent
      hoverEnabled: true
      enabled: button.enabled
      onClicked: button.triggered()
    }
  }
}
