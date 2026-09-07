import QtQuick

// The pill bar along the bottom: session, keyboard layout, battery, then sleep,
// reboot and shutdown. Same vocabulary as the shell's bar -- 30px items in a
// 6px-padded glass pill -- so the greeter's bar and the session's bar read as
// the same object.
Item {
  id: root

  property string sessionName: ""
  property bool sessionPanelOpen: false
  property string layout: ""
  property int layoutCount: 0
  property bool capsLock: false
  property int batteryLevel: -1
  property bool batteryCharging: false
  property string networkName: ""
  property bool networkWireless: true
  property bool canSuspend: true
  property bool canReboot: true
  property bool canPowerOff: true

  signal sessionToggled
  signal layoutCycled
  signal suspendRequested
  signal rebootRequested
  signal powerOffRequested

  implicitWidth: pill.width
  implicitHeight: pill.height

  GlassPanel {
    id: pill
    width: row.implicitWidth + Theme.px(12)
    height: Theme.barItemHeight + Theme.px(12)
    radius: Theme.radiusBar
    color: Theme.pillPanel
    border.color: Theme.hairlineSoft
    shadowBlur: Theme.px(54)
    shadowOffset: Theme.px(18)
    shadowColor: Theme.shadowPill

    Row {
      id: row
      anchors.centerIn: parent
      spacing: Theme.px(5)

      // -- session ---------------------------------------------------------
      PillButton {
        anchors.verticalCenter: parent.verticalCenter
        active: root.sessionPanelOpen
        onClicked: root.sessionToggled()

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: Theme.px(6); height: Theme.px(6)
          radius: width / 2
          color: Theme.accent
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: root.sessionName
          color: root.sessionPanelOpen ? Theme.text : Theme.ink(0.7)
          font.family: Theme.fontMono
          font.pixelSize: Theme.fs(10)
          font.weight: 500
        }
        Icon {
          anchors.verticalCenter: parent.verticalCenter
          name: root.sessionPanelOpen ? "chevron-up" : "chevron-down"
          size: Theme.px(9)
          color: Theme.ink(root.sessionPanelOpen ? 0.5 : 0.4)
        }
      }

      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: 1; height: Theme.px(18)
        color: Theme.hairline
      }

      // -- keyboard layout -------------------------------------------------
      // One layout means nothing to switch to, so the pill stops being a
      // button -- but it still says which layout the password is typed in.
      PillButton {
        anchors.verticalCenter: parent.verticalCenter
        interactive: root.layoutCount > 1
        visible: root.layout !== ""
        onClicked: root.layoutCycled()

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: root.layout
          color: Theme.ink(0.7)
          font.family: Theme.fontMono
          font.pixelSize: Theme.fs(10)
          font.weight: 500
        }
        Icon {
          anchors.verticalCenter: parent.verticalCenter
          name: "chevron-down"
          size: Theme.px(9)
          color: Theme.ink(0.4)
          visible: root.layoutCount > 1
        }
      }

      // -- caps lock -------------------------------------------------------
      // The one thing most worth saying on a login screen, and only said when
      // it is true.
      PillButton {
        anchors.verticalCenter: parent.verticalCenter
        interactive: false
        visible: root.capsLock
        padding: Theme.px(11)

        Icon {
          anchors.verticalCenter: parent.verticalCenter
          name: "arrow-big-up"
          size: Theme.px(11)
          color: Theme.accentSoft
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: qsTr("caps lock")
          color: Theme.accentSoft
          font.family: Theme.fontMono
          font.pixelSize: Theme.fs(10)
          font.weight: 500
        }
      }

      // -- network ---------------------------------------------------------
      // The mockup's "c7-office" pill. Empty name = nothing published (no
      // dispatcher script) or nothing connected, and the pill stays away
      // rather than claiming an offline machine is online.
      PillButton {
        anchors.verticalCenter: parent.verticalCenter
        interactive: false
        visible: root.networkName !== ""
        padding: Theme.px(11)

        Icon {
          anchors.verticalCenter: parent.verticalCenter
          name: root.networkWireless ? "wifi" : "ethernet"
          size: Theme.px(12)
          color: Theme.ink(0.55)
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: root.networkName
          color: Theme.ink(0.55)
          font.family: Theme.fontMono
          font.pixelSize: Theme.fs(10)
          font.weight: 500
          elide: Text.ElideRight
          // A guest network called something enormous must not push the power
          // buttons off the bar.
          width: Math.min(implicitWidth, Theme.px(140))
        }
      }

      // -- battery ---------------------------------------------------------
      PillButton {
        anchors.verticalCenter: parent.verticalCenter
        interactive: false
        visible: root.batteryLevel >= 0
        padding: Theme.px(11)

        BatteryGlyph {
          anchors.verticalCenter: parent.verticalCenter
          level: root.batteryLevel
          charging: root.batteryCharging
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: root.batteryLevel + "%"
          color: Theme.ink(0.55)
          font.family: Theme.fontMono
          font.pixelSize: Theme.fs(10)
          font.weight: 500
        }
      }

      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: 1; height: Theme.px(18)
        color: Theme.hairline
      }

      // -- power -----------------------------------------------------------
      // Sleep is a tap; reboot and shutdown are held, as in the shell's power
      // menu -- one stray click here ends everybody's session.
      PillButton {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.canSuspend
        padding: Theme.px(9)
        onClicked: root.suspendRequested()

        Icon {
          anchors.verticalCenter: parent.verticalCenter
          name: "moon"
          size: Theme.px(14)
          color: Theme.ink(0.6)
        }
      }
      HoldButton {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.canReboot
        icon: "rotate-ccw"
        onConfirmed: root.rebootRequested()
      }
      HoldButton {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.canPowerOff
        icon: "power"
        iconColor: Theme.ink(0.5)
        onConfirmed: root.powerOffRequested()
      }
    }
  }

  // The mockup's caption under the bar, kept because the hold is not
  // discoverable otherwise.
  Text {
    anchors.top: pill.bottom
    anchors.topMargin: Theme.px(6)
    anchors.horizontalCenter: pill.horizontalCenter
    text: qsTr("hold reboot or shutdown to confirm")
    color: Theme.ink(0.2)
    font.family: Theme.fontMono
    font.pixelSize: Theme.fs(8.5)
  }
}
