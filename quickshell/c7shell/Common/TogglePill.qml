import QtQuick
import qs.Theme

// Spec §4 toggle: 30×17 pill, crimson when on. Size is settable because 1d's
// "do not disturb" row uses a smaller 26×15 one.
Rectangle {
  id: root

  property bool checked: false
  signal toggled()

  implicitWidth: 30
  implicitHeight: 17
  radius: height / 2
  color: root.checked ? Theme.accent : Theme.hairlineStrong
  // A radio blocked in hardware cannot be un-blocked from software, so the
  // toggle shows itself as dead rather than pretending otherwise.
  opacity: root.enabled ? 1 : 0.4

  Behavior on color { ColorAnimation { duration: 120 } }

  Rectangle {
    x: root.checked ? root.width - width - 2 : 2
    anchors.verticalCenter: parent.verticalCenter
    width: root.height - 4
    height: width
    radius: width / 2
    color: root.checked ? Theme.textOnAccent : Theme.alpha(Theme.text, 0.5)

    Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
  }

  MouseArea {
    anchors.fill: parent
    onClicked: root.toggled()
  }
}
