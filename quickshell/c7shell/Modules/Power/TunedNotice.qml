pragma ComponentBehavior: Bound
import QtQuick
import qs.Theme
import qs.Common
import qs.Services

// The amber card that stands in for the profile list when tuned is not running:
// the battery popover's and the settings page's, which were the same card
// written twice and had already drifted a pixel apart.
//
// Hidden rather than faked is the rule behind it -- there is nothing to read an
// active profile from, so the shell shows no profiles at all instead of three
// buttons that do nothing. Everything that does not go through tuned (the
// charge readout, suspend, screen, battery health) carries on either side of
// this card, which is why it replaces one section instead of the whole view.
//
// `visible` is deliberately NOT bound to TunedService.available here: both
// callers place this inside a column whose other children are bound to it too,
// and a component that hides itself reads as a layout bug at the call site.
Rectangle {
  id: root

  // The one line that differs between the two callers: the popover has 262px
  // to spend and the page has a column, so they explain the same thing at
  // different lengths. Both branches of the caller's ternary belong to it.
  property string blurb: ""

  // The popover's metrics rather than the page's: a tile inside a 262px panel,
  // not a card in a settings column. It is one flag because the six numbers
  // below always move together -- there is no third size.
  property bool compact: false

  width: parent.width
  implicitHeight: body.implicitHeight + (root.compact ? 24 : 26)
  radius: root.compact ? Theme.radiusTile : Theme.radiusCard
  color: Theme.alpha(Theme.warning, root.compact ? 0.06 : 0.05)
  border.width: 1
  border.color: Theme.alpha(Theme.warning, 0.3)

  Column {
    id: body

    anchors {
      left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
      leftMargin: root.compact ? 12 : 14
      rightMargin: root.compact ? 12 : 14
    }
    spacing: 9

    Row {
      width: parent.width
      spacing: 10

      Icon {
        anchors.verticalCenter: parent.verticalCenter
        name: "alert-triangle"
        size: 14
        tint: Theme.warning
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        // Installed-but-stopped and not-installed are different problems with
        // different fixes, and the button below only exists for the first.
        text: TunedService.installed ? "tuned is not running" : "tuned is not installed"
        font { family: Theme.fontMono; pixelSize: 11; weight: 600 }
        color: Theme.text
      }
    }

    Text {
      width: parent.width
      text: root.blurb
      font { family: Theme.fontMono; pixelSize: root.compact ? 9 : 10; weight: 400 }
      lineHeight: 1.5
      wrapMode: Text.WordWrap
      color: Theme.alpha(Theme.text, 0.45)
    }

    Rectangle {
      // Offered only when there is a service to enable: a button that cannot
      // work is worse than no button.
      visible: TunedService.installed
      // Full width in the popover, hugging its label on the page -- a
      // panel-wide button in a settings column reads as a section, not an
      // action.
      width: root.compact ? parent.width : enableLabel.implicitWidth + 26
      implicitHeight: root.compact ? 26 : 28
      radius: Theme.radiusChip
      color: enableMouse.containsMouse ? Theme.accentSoft : Theme.accent

      Behavior on color { ColorAnimation { duration: 120 } }

      Text {
        id: enableLabel
        anchors.centerIn: parent
        text: "enable tuned.service"
        font { family: Theme.fontMono; pixelSize: 10; weight: 600 }
        color: Theme.textOnAccent
      }

      MouseArea {
        id: enableMouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: PowerService.enableTuned()
      }
    }
  }
}
