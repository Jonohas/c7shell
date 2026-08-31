import QtQuick
import qs.Theme

// The two- or three-way picker the topbar handoff uses where a toggle would
// lose the names of the choices: a recessed track with the active chip painted
// crimson. Options are `[{ value, label }]`; the caller owns the value.
Rectangle {
  id: root

  required property var options
  required property var value

  signal picked(var value)

  implicitWidth: chips.implicitWidth + 6
  implicitHeight: chips.implicitHeight + 6
  radius: Theme.radiusChip
  color: Theme.alpha(Theme.text, 0.06)
  // Disabled is a real state here: the wattage rows stay legible while their
  // parent toggle is off, so the user can see what turning it on unlocks.
  opacity: root.enabled ? 1 : 0.4

  Row {
    id: chips
    anchors.centerIn: parent
    spacing: 2

    Repeater {
      model: root.options

      Rectangle {
        id: chip

        required property var modelData

        readonly property bool selected: root.value === chip.modelData.value

        implicitWidth: label.implicitWidth + 20
        implicitHeight: 19
        radius: 6
        color: chip.selected ? Theme.accent
          : (mouse.containsMouse && root.enabled ? Theme.surface07 : "transparent")

        Behavior on color { ColorAnimation { duration: 120 } }

        Text {
          id: label
          anchors.centerIn: parent
          text: chip.modelData.label
          font {
            family: Theme.fontMono
            pixelSize: 10
            weight: chip.selected ? 600 : 500
          }
          color: chip.selected ? Theme.textOnAccent : Theme.alpha(Theme.text, 0.5)
        }

        MouseArea {
          id: mouse
          anchors.fill: parent
          hoverEnabled: true
          enabled: root.enabled
          onClicked: if (!chip.selected) root.picked(chip.modelData.value)
        }
      }
    }
  }
}
