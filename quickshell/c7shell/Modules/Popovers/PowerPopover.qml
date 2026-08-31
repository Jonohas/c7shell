pragma ComponentBehavior: Bound
import QtQuick
import qs.Theme
import qs.Common
import qs.Services

// 17b: the battery pill's own popover. Charge at the top, the three tuned
// profiles under it, each carrying ITS OWN runtime estimate -- which is the
// whole idea of the screen. The trade-off between the profiles is not something
// the labels describe, it is the numbers beside them.
//
// Never grows a scrollbar: exactly three rows, whatever tuned knows. Anything
// past the three lives behind the "see all N tuned profiles" link on the
// settings page.
GlassPopover {
  id: root

  name: "power"
  panelWidth: 262
  padding: 13
  gap: 11

  // -- header ----------------------------------------------------------------
  Item {
    width: parent.width
    implicitHeight: Math.max(headText.implicitHeight, glyph.height)

    Column {
      id: headText

      anchors { left: parent.left; right: glyph.left; rightMargin: 11; top: parent.top }
      spacing: 3

      Text {
        // The one Space Grotesk figure in the panel: the charge is the headline,
        // and everything else in here is mono.
        text: `${BatteryService.percent}%`
        font { family: Theme.fontDisplay; pixelSize: 15; weight: 600 }
        color: Theme.text
      }

      Text {
        width: parent.width
        // "recalculating…" while the draw window is being refilled after a
        // switch: the arithmetic would otherwise be the OLD profile's draw
        // against the new profile's name, which is a number about to be
        // contradicted.
        text: {
          if (TunedService.recalculating) return "recalculating…"
          if (BatteryService.idleOnPower) return "on power"
          const draw = `${BatteryService.watts.toFixed(1)} W`
          if (BatteryService.secondsLeft <= 0) return draw
          const left = BatteryService.duration(BatteryService.secondsLeft)
          return BatteryService.charging
            ? `${left} to full · ${draw}` : `${left} left · ${draw}`
        }
        font { family: Theme.fontMono; pixelSize: 9; weight: 400 }
        color: Theme.alpha(Theme.text, 0.42)
        elide: Text.ElideRight
      }
    }

    BatteryGlyph {
      id: glyph
      anchors { right: parent.right; top: parent.top; topMargin: 1 }
    }
  }

  // The charge bar takes its colour from the glyph rather than repeating the
  // rule: charging green, crimson on the way down, grey parked on AC. One
  // instance owns the state, and the bar is a second view of it.
  Rectangle {
    width: parent.width
    height: 4
    radius: 2
    color: Theme.alpha(Theme.text, 0.09)

    Rectangle {
      width: Math.max(2, parent.width * BatteryService.fraction)
      height: parent.height
      radius: parent.radius
      color: glyph.fill

      Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    }
  }

  // -- tuned is not running --------------------------------------------------
  // Amber-bordered, and the profile list is HIDDEN rather than faked. The
  // battery readout above carries on regardless, which is the point: the pill
  // is still worth opening on a machine with no tuned.
  Rectangle {
    width: parent.width
    visible: !TunedService.available
    implicitHeight: missing.implicitHeight + 24
    radius: Theme.radiusTile
    color: Theme.alpha(Theme.warning, 0.06)
    border.width: 1
    border.color: Theme.alpha(Theme.warning, 0.3)

    Column {
      id: missing

      anchors {
        left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
        leftMargin: 12; rightMargin: 12
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
          text: TunedService.installed ? "tuned is not running" : "tuned is not installed"
          font { family: Theme.fontMono; pixelSize: 11; weight: 600 }
          color: Theme.text
        }
      }

      Text {
        width: parent.width
        text: TunedService.installed
          ? "The profile list is hidden rather than faked. Battery readout still works."
          : "Install it to switch power profiles from here. Battery readout still works."
        font { family: Theme.fontMono; pixelSize: 9; weight: 400 }
        lineHeight: 1.5
        wrapMode: Text.WordWrap
        color: Theme.alpha(Theme.text, 0.45)
      }

      Rectangle {
        width: parent.width
        // Offered only when there is a service to enable: a button that cannot
        // work is worse than no button.
        visible: TunedService.installed
        implicitHeight: 26
        radius: Theme.radiusChip
        color: enableMouse.containsMouse ? Theme.accentSoft : Theme.accent

        Behavior on color { ColorAnimation { duration: 120 } }

        Text {
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

  // -- profiles --------------------------------------------------------------
  Column {
    width: parent.width
    visible: TunedService.available
    spacing: 3

    Item {
      width: parent.width
      implicitHeight: 14

      Text {
        anchors { left: parent.left; bottom: parent.bottom; bottomMargin: 3 }
        text: "PROFILE"
        font { family: Theme.fontMono; pixelSize: 9; weight: 600; letterSpacing: 0.9 }
        color: Theme.alpha(Theme.text, 0.3)
      }

      // A tuned profile outside the three has to be said out loud, or the panel
      // reads as though nothing is active at all.
      Text {
        anchors { right: parent.right; bottom: parent.bottom; bottomMargin: 3 }
        visible: TunedService.activeKey === "" && TunedService.activeProfile !== ""
        text: TunedService.activeProfile
        font { family: Theme.fontMono; pixelSize: 9; weight: 500 }
        color: Theme.alpha(Theme.text, 0.45)
        elide: Text.ElideRight
      }
    }

    Repeater {
      model: PowerStore.profiles

      Rectangle {
        id: row

        required property var modelData

        readonly property string key: row.modelData.key
        readonly property bool applying: TunedService.applying === row.key
        // The highlight moves to the picked row IMMEDIATELY, before tuned has
        // answered: the click's feedback must not wait on the bus.
        readonly property bool current: TunedService.applying !== ""
          ? row.applying : TunedService.activeKey === row.key

        width: parent.width
        implicitHeight: 34
        radius: Theme.radiusTile
        color: row.current ? Theme.accentFill
          : (rowMouse.containsMouse ? Theme.surface04 : "transparent")
        border.width: row.current ? 1 : 0
        border.color: Theme.accentBorder
        // The other rows DIM rather than lock while a switch is in flight, so a
        // mis-click costs one more click instead of a wait.
        opacity: TunedService.applying !== "" && !row.applying ? 0.45 : 1

        Behavior on color { ColorAnimation { duration: 120 } }
        Behavior on opacity { NumberAnimation { duration: 120 } }

        MouseArea {
          id: rowMouse
          anchors.fill: parent
          hoverEnabled: true
          // No toast: a click in here is its own feedback.
          onClicked: TunedService.apply(row.key, false)
        }

        Icon {
          id: rowIcon
          anchors { left: parent.left; leftMargin: 9; verticalCenter: parent.verticalCenter }
          name: row.modelData.icon
          size: 14
          tint: row.current ? Theme.accentSoft : Theme.alpha(Theme.text, 0.5)
        }

        Column {
          anchors {
            left: rowIcon.right; leftMargin: 10
            right: mark.left; rightMargin: 8
            verticalCenter: parent.verticalCenter
          }
          spacing: 1

          Text {
            width: parent.width
            text: row.modelData.label
            font {
              family: Theme.fontMono
              pixelSize: 11
              weight: row.current ? 600 : 500
            }
            color: row.current ? Theme.text : Theme.alpha(Theme.text, 0.75)
            elide: Text.ElideRight
          }
          Text {
            width: parent.width
            // The estimate IS the label's other half. While the window is being
            // refilled there is nothing honest to print, so the line goes.
            visible: text !== ""
            text: row.applying ? "applying…"
              : TunedService.recalculating ? ""
              : TunedService.estimateText(row.key)
            font { family: Theme.fontMono; pixelSize: 9; weight: 400 }
            color: Theme.alpha(Theme.text, row.current ? 0.42 : 0.32)
            elide: Text.ElideRight
          }
        }

        Item {
          id: mark

          anchors { right: parent.right; rightMargin: 9; verticalCenter: parent.verticalCenter }
          width: 12
          height: 12

          Spinner {
            anchors.centerIn: parent
            size: 11
            visible: row.applying
            arcColor: Theme.alpha(Theme.accent, 0.85)
          }
          Icon {
            anchors.centerIn: parent
            name: "check"
            size: 11
            visible: row.current && !row.applying
            tint: Theme.accent
          }
        }
      }
    }
  }

  // A refusal from tuned is the one thing the panel has to surface: the
  // highlight has already moved, so silence would leave a row lit that is not
  // actually active.
  Text {
    width: parent.width
    visible: TunedService.lastError !== ""
    text: TunedService.lastError
    font { family: Theme.fontMono; pixelSize: 9; weight: 400 }
    color: Theme.accentSoft
    wrapMode: Text.WordWrap
  }

  PopoverFooter {
    width: parent.width
    leftText: TunedService.available
      ? (PowerStore.autoSwitch ? "tuned · auto on unplug" : "tuned · manual")
      : "battery"
    rightText: "power settings →"
    onRightClicked: { PopoverManager.close(); SettingsService.open("power") }
  }
}
