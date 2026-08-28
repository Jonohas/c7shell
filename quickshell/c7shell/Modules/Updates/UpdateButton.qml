import QtQuick
import qs.Theme

// The one button the merged flow turns on: `update · 412 MB` on the clean
// path, `review & update →` on the escalated one. Same button, same place --
// the label and the arrow are the only promise of a window.
Rectangle {
  id: root

  property string label: ""
  // Set on the clean path; the design puts the download size *on* the button
  // rather than in a line above it, so one glance carries both.
  property string trailing: ""
  property bool primary: true
  signal triggered()

  implicitWidth: parent ? parent.width : 200
  implicitHeight: 32
  radius: Theme.radiusChip
  color: !root.enabled ? Theme.surface04
       : root.primary ? (hover.hovered ? Qt.lighter(Theme.accent, 1.12) : Theme.accent)
                      : (hover.hovered ? Theme.surface07 : Theme.surface04)
  border.width: root.primary ? 0 : 1
  border.color: Theme.hairline

  Behavior on color { ColorAnimation { duration: 120 } }

  Row {
    anchors.centerIn: parent
    spacing: 6

    Text {
      text: root.label
      font { family: Theme.fontMono; pixelSize: 11; weight: 600 }
      color: !root.enabled ? Theme.textDisabled
           : root.primary ? Theme.textOnAccent : Theme.text
    }
    Text {
      visible: root.trailing !== ""
      text: `· ${root.trailing}`
      font { family: Theme.fontMono; pixelSize: 11; weight: 400 }
      color: root.primary ? Theme.alpha(Theme.textOnAccent, 0.72) : Theme.text3
    }
  }

  HoverHandler { id: hover; enabled: root.enabled; cursorShape: Qt.PointingHandCursor }
  TapHandler { enabled: root.enabled; onTapped: root.triggered() }
}
