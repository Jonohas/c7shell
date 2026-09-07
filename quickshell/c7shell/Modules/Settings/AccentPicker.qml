import QtQuick
import qs.Theme
import qs.Common
import qs.Services
import "../../Common/Hex.js" as Hex

// The custom half of 2b's accent card: a saturation/value square, a hue strip
// under it, and the hex the two of them add up to. Disclosed by the accent
// card's last swatch, which is the only thing that sets `open`.
//
// It holds h/s/v of its own rather than deriving them from the accent on every
// repaint, for the reason Common/Hex.js documents: a grey has no hue to
// recover, so a drag down into the black corner would lose the hue it was
// dragged from and spring the strip back to red on release. The seed happens
// once, when the card opens.
//
// Writes land on AppearanceStore.values.accent immediately, the same as the
// geometry sliders on this page -- the store coalesces both the hyprctl eval
// and the kdeglobals export behind its own timers, so a drag costs one of each
// once it stops moving. That makes the whole shell the preview, which is the
// point: an accent is a colour you judge against the bar and the popovers, not
// against a 24px dot.
Item {
  id: root

  // Driven by the disclosure swatch. Closed, this collapses to nothing rather
  // than staying mapped at zero opacity -- the card measures its children.
  property bool open: false

  // 0..360, 0..1, 0..1. Seeded from the accent in force at open time.
  property real hue: 0
  property real sat: 1
  property real val: 1

  readonly property string hex: Hex.fromHsv(root.hue, root.sat, root.val)
  // Full-strength version of the current hue: the SV square's ground, which
  // the white and black overlays are mixed into.
  readonly property color pureHue: Hex.fromHsv(root.hue, 1, 1)

  visible: root.open
  implicitHeight: root.open ? body.implicitHeight : 0

  // Reading `accent`, not the raw JSON: a hand-edited nonsense value is
  // already the palette default by the time it gets here, so the picker opens
  // on the colour the shell is actually painting.
  function seed() {
    const c = Hex.toHsv(String(AppearanceStore.accent))
    // A neutral accent keeps whatever hue the strip is already on -- toHsv
    // reports 0 for every grey, and springing to red is not a seed.
    if (c.s > 0) root.hue = c.h
    root.sat = c.s
    root.val = c.v
    // Explicitly, as well as through onHexChanged: an accent that happens to
    // equal what the field already holds emits nothing, and the field may be
    // carrying a rejected string from the last time the card was open.
    hexField.text = root.hex
  }

  // The field is assigned rather than bound, because typing in a TextInput
  // breaks a binding on its own text: `text: root.hex` would go dead the
  // moment anyone edited it, and the square would then drag with the field
  // frozen on whatever was typed. Nothing but a drag or an accepted entry
  // changes `hex`, so this never fights the cursor.
  onHexChanged: hexField.text = root.hex

  // Seeding on open rather than on completion: the accent can have been
  // changed by a preset swatch, or by a hand-edit of appearance.json, since
  // the last time the card was down.
  onOpenChanged: if (root.open) root.seed()

  // And again whenever the accent moves under a CLOSED card, which is the
  // ordering this got wrong first time round: AppearanceStore's FileView loads
  // asynchronously, so a picker seeded during component completion reads the
  // palette default and then sits on it for the rest of the session -- opening
  // on crimson over a blue shell. While the card is open the picker is the one
  // writing, so re-seeding then would fight the drag it is reacting to.
  Connections {
    target: AppearanceStore
    function onAccentChanged() { if (!root.open) root.seed() }
  }

  function commit() {
    AppearanceStore.values.accent = root.hex
  }

  function setSv(s, v) {
    root.sat = Math.max(0, Math.min(1, s))
    root.val = Math.max(0, Math.min(1, v))
    root.commit()
  }

  // 359.999 rather than 360: the two are the same colour, and clamping to 360
  // would park the thumb half off the right end of the strip.
  function setHue(h) {
    root.hue = Math.max(0, Math.min(359.999, h))
    root.commit()
  }

  // Typed hex wins over the marker: seed h/s/v off it so the square and the
  // strip agree with what was entered, then write it out. Rejected input
  // leaves the accent alone and the field snaps back to the colour in force,
  // which is the only feedback there is room for here.
  function applyField() {
    const clean = Hex.normalise(hexField.text)
    if (clean === "") {
      hexField.text = root.hex
      return
    }
    const c = Hex.toHsv(clean)
    if (c.s > 0) root.hue = c.h
    root.sat = c.s
    root.val = c.v
    AppearanceStore.values.accent = clean
    hexField.text = clean
  }

  Column {
    id: body

    anchors { left: parent.left; right: parent.right; top: parent.top }
    spacing: 10

    // -- saturation / value ------------------------------------------------
    Item {
      id: field

      width: parent.width
      implicitHeight: 104

      Rectangle {
        id: square

        anchors.fill: parent
        radius: Theme.radiusTile
        color: root.pureHue

        // Saturation left to right, value top to bottom, the way every other
        // picker on the desktop draws it. White and black rather than palette
        // entries: these are the ends of a mixing range, not tokens. Both
        // overlays carry the square's own radius -- clip is rectangular, so
        // without it the gradients' corners sit outside the rounded ground.
        Rectangle {
          anchors.fill: parent
          radius: square.radius
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 1) }
            GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0) }
          }
        }
        Rectangle {
          anchors.fill: parent
          radius: square.radius
          gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0) }
            GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 1) }
          }
        }

        Rectangle {   // the hairline every other surface on this page has
          anchors.fill: parent
          radius: square.radius
          color: "transparent"
          border.width: 1
          border.color: Theme.hairlineStrong
        }
      }

      // A ring, not a dot: a filled marker is invisible against the colour it
      // is standing on, which is exactly the colour being looked at when it is
      // placed. Two rings, so it survives the white corner as well as the
      // black one.
      Rectangle {
        x: root.sat * field.width - width / 2
        y: (1 - root.val) * field.height - height / 2
        width: 12
        height: 12
        radius: 6
        color: "transparent"
        border.width: 2
        border.color: Qt.rgba(1, 1, 1, 1)

        Rectangle {
          anchors.fill: parent
          anchors.margins: 2
          radius: width / 2
          color: "transparent"
          border.width: 1
          border.color: Qt.rgba(0, 0, 0, 0.45)
        }
      }

      MouseArea {
        anchors.fill: parent
        // Every settings page is a Flickable once the window is short enough
        // to scroll, and it steals a drag that wanders vertically -- which is
        // one of this control's two axes. CrimsonSlider holds the grab for the
        // same reason.
        preventStealing: true

        function place(mx, my) {
          root.setSv(mx / field.width, 1 - my / field.height)
        }

        onPressed: mouse => place(mouse.x, mouse.y)
        onPositionChanged: mouse => place(mouse.x, mouse.y)
      }
    }

    // -- hue ---------------------------------------------------------------
    Item {
      width: parent.width
      implicitHeight: 14

      Rectangle {
        id: strip

        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
        height: 10
        radius: height / 2
        border.width: 1
        border.color: Theme.hairlineStrong

        gradient: HueGradient {}
      }

      // The same 13px white thumb CrimsonSlider draws, so the sliders on this
      // page read as one control and not two.
      Rectangle {
        x: Math.max(0, Math.min(strip.width - width, root.hue / 360 * strip.width - width / 2))
        anchors.verticalCenter: parent.verticalCenter
        width: 13
        height: 13
        radius: 6.5
        color: Theme.textOnAccent
        border.width: 1
        border.color: Qt.rgba(0, 0, 0, 0.25)
      }

      MouseArea {
        anchors.fill: parent
        // Vertical slop, as CrimsonSlider has, so a 10px track is grabbable.
        anchors.topMargin: -4
        anchors.bottomMargin: -4
        preventStealing: true

        function seek(mx) {
          root.setHue(mx / strip.width * 360)
        }

        onPressed: mouse => seek(mouse.x)
        onPositionChanged: mouse => seek(mouse.x)
      }
    }

    // -- hex ---------------------------------------------------------------
    // Typed as well as picked: a colour that arrives from a brand palette or
    // from another machine's config arrives as six digits, and nobody hunts
    // for those on a square. Same shape as the wallpaper path field.
    Rectangle {
      width: parent.width
      implicitHeight: 28
      radius: Theme.radiusTile
      color: Theme.surface04

      Rectangle {   // what is in force, not what is in the field
        id: dot

        anchors { left: parent.left; leftMargin: 9; verticalCenter: parent.verticalCenter }
        width: 16
        height: 16
        radius: 8
        color: Theme.accent
        border.width: 1
        border.color: Theme.hairlineStrong
      }

      TextInput {
        id: hexField

        anchors {
          left: dot.right; leftMargin: 9
          right: setHex.left; rightMargin: 8
          verticalCenter: parent.verticalCenter
        }
        font { family: Theme.fontMono; pixelSize: 11; weight: 500 }
        color: Theme.text
        // "#rrggbb" is seven; the slack takes a paste that brought a space or
        // a second hash with it, which normalise then trims.
        maximumLength: 9
        clip: true
        onAccepted: root.applyField()
      }

      Text {
        id: setHex

        anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
        text: "set"
        font { family: Theme.fontMono; pixelSize: 10; weight: 500 }
        // Dimmed rather than hidden while the field does not name a colour: a
        // control that vanishes mid-typing reads as a crash.
        color: Hex.normalise(hexField.text) === "" ? Theme.text3 : Theme.accentSoft

        MouseArea {
          anchors.fill: parent
          anchors.margins: -4
          onClicked: root.applyField()
        }
      }
    }
  }
}
