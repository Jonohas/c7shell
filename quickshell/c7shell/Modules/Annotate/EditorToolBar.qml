import QtQuick
import QtQuick.Effects
import qs.Theme
import qs.Common
import qs.Services

// Mockup 9a, bottom centre: the tools, and the order the number keys bind in.
//
// It holds only the tools that exist. A bar showing `blur` greyed out would
// be advertising a redaction the editor cannot perform, and the reason each
// of those is missing is that its own issue has not landed -- not that it is
// unavailable today.
GlassPanel {
  id: bar

  // The bar IS the key mapping: 1-9 in this order, read by AnnotateWindow.
  // Adding a tool here is what makes it reachable by number, so the two can
  // never disagree.
  readonly property var tools: [
    { id: "select", icon: "mouse-pointer", group: 0 },
    { id: "rect", icon: "square", group: 1 },
    { id: "crop", icon: "crop", group: 2 }
  ]

  implicitWidth: row.implicitWidth + 12
  implicitHeight: row.implicitHeight + 12
  radius: Theme.radiusToolBar
  glassAlpha: Theme.glassAlphaPanel

  RectangularShadow {
    anchors.fill: parent
    radius: bar.radius
    color: Theme.panelShadowColor
    offset.y: 16
    blur: 40
    z: -1
  }

  Row {
    id: row
    anchors.centerIn: parent
    spacing: 3

    Repeater {
      model: bar.tools

      Row {
        required property var modelData
        required property int index

        spacing: 3

        Rectangle {   // the rule between groups, drawn before the tool it precedes
          anchors.verticalCenter: parent.verticalCenter
          visible: index > 0 && modelData.group !== bar.tools[index - 1].group
          width: 1
          height: 18
          color: Theme.hairlineStrong
        }

        Rectangle {
          id: button
          readonly property bool active: AnnotateService.tool === modelData.id

          width: 34
          height: 30
          radius: 10
          color: button.active ? Theme.accentFill
            : hover.containsMouse ? Theme.surface07
            : "transparent"
          border.width: button.active ? 1 : 0
          border.color: Theme.accentBorder

          Icon {
            anchors.centerIn: parent
            name: modelData.icon
            size: 14
            tint: button.active ? Theme.accentSoft : Theme.text2
          }

          MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            onClicked: AnnotateService.tool = modelData.id
          }
        }
      }
    }
  }
}
