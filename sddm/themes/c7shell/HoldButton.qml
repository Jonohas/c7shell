import QtQuick

// Shutdown and reboot: press and hold to confirm, the same 600 ms the shell's
// power menu uses, with a fill sweeping across as it counts. A misplaced click
// on the greeter's power buttons costs somebody's unsaved session, which is why
// these are not plain buttons.
Rectangle {
  id: root

  property int holdMs: 600
  property var icon: ({})
  property color iconColor: Theme.ink(0.6)
  readonly property bool holding: press.pressed

  signal confirmed

  implicitWidth: Theme.px(32)
  implicitHeight: Theme.barItemHeight
  radius: Theme.radiusButton
  color: hover.hovered ? Theme.hover : "transparent"
  clip: true

  Behavior on color { ColorAnimation { duration: 120 } }

  // The progress sweep.
  Rectangle {
    id: fill
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: 0
    radius: parent.radius
    color: Theme.crimson(0.45)
  }

  VectorIcon {
    anchors.centerIn: parent
    icon: root.icon
    size: Theme.px(14)
    color: root.holding ? Theme.text : root.iconColor
  }

  HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }

  TapHandler {
    id: press
    longPressThreshold: root.holdMs / 1000
    onLongPressed: root.confirmed()
  }

  states: State {
    when: root.holding
    PropertyChanges { fill.width: root.width }
  }

  transitions: [
    Transition {
      to: ""
      NumberAnimation { target: fill; property: "width"; to: 0; duration: 120 }
    },
    Transition {
      NumberAnimation { target: fill; property: "width"; duration: root.holdMs; easing.type: Easing.Linear }
    }
  ]
}
