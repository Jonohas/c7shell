import QtQuick
import qs.Theme

// The prompt's two buttons. Not shared with the rest of the shell on purpose:
// these are 8px-tall-padding text rows sized in halves of a 280px panel, and
// the design fixes their labels per caller. Everything else uses TogglePill or
// HoldButton.
Rectangle {
  id: root

  property string label: ""
  property bool primary: false
  property bool compact: false
  // Verifying: the submit is inert but still legible, so the panel does not
  // reflow and the person can see what they pressed.
  property bool dimmed: false

  signal clicked

  implicitHeight: root.compact ? 30 : 32
  radius: root.compact ? 9 : 10

  color: root.primary
       ? (root.dimmed ? Theme.alpha(Theme.accent, 0.4)
          : area.containsMouse ? Qt.lighter(Theme.accent, 1.12) : Theme.accent)
       : (area.containsMouse ? Theme.hoverPill : Theme.alpha(Theme.text, 0.06))

  Text {
    anchors.centerIn: parent
    text: root.label
    font {
      family: Theme.fontMono
      pixelSize: root.compact ? 10 : 10
      weight: root.primary ? 600 : 500
    }
    color: root.primary
         ? (root.dimmed ? Theme.alpha(Theme.textOnAccent, 0.55) : Theme.textOnAccent)
         : Theme.alpha(Theme.text, 0.6)
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
