pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import qs.Theme
import qs.Common
import qs.Services
import qs.Modules.Power
import qs.Modules.Settings
import qs.Modules.Settings.pages.power

// 17a: settings → system → power.
//
// The rule the whole page is built on is that tuned owns the state. Nothing
// here writes a governor, an EPP value or a platform profile; the cards read
// tuned's active profile and ask it to change, and a `tuned-adm profile …` run
// in a terminal repaints this page within a second because the list is driven
// by tuned's own signal rather than by what the shell last set.
//
// Where tuned is not running the PROFILE section is REPLACED by the same amber
// card the popover shows -- hidden rather than faked -- and everything below it
// (suspend, screen, battery health) carries on working, because none of it goes
// through tuned.
SettingsPage {
  id: root

  title: "Power"
  subtitle: "profiles come from tuned · the shell never sets a governor itself"

  headerTrailing: Rectangle {
    implicitWidth: badge.implicitWidth + 20
    implicitHeight: 24
    radius: Theme.radiusChip
    color: TunedService.available
      ? Theme.alpha(Theme.success, 0.1) : Theme.alpha(Theme.warning, 0.1)
    border.width: 1
    border.color: TunedService.available
      ? Theme.alpha(Theme.success, 0.24) : Theme.alpha(Theme.warning, 0.3)

    Row {
      id: badge
      anchors.centerIn: parent
      spacing: 7

      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: 6
        height: 6
        radius: 3
        color: TunedService.available ? Theme.success : Theme.warning
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        // The version comes from pacman, not from the bus: tuned publishes no
        // version property, and an invented one is worse than none.
        text: {
          if (!TunedService.installed) return "tuned not installed"
          const v = TunedService.version !== "" ? `tuned ${TunedService.version}` : "tuned"
          return `${v} · ${TunedService.available ? "active" : "inactive"}`
        }
        font { family: Theme.fontMono; pixelSize: 10; weight: 500 }
        color: Theme.alpha(Theme.text, 0.7)
      }
    }
  }

  // -- profile ---------------------------------------------------------------

  Column {
    width: parent.width
    spacing: 9

    SectionHeading { width: parent.width; text: "profile"; rule: false }

    // The tuned-missing card, in the space the three cards would occupy.
    TunedNotice {
      visible: !TunedService.available
      blurb: TunedService.installed
        ? "The profile list is hidden rather than faked — there is nothing to read the active profile from. Everything below still works."
        : "The three profile buttons map to tuned profiles, so they need tuned. Everything below still works without it."
    }

    Row {
      width: parent.width
      visible: TunedService.available
      spacing: 11

      Repeater {
        model: PowerStore.profiles

        ProfileCard {
          required property var modelData
          profile: modelData
          width: (parent.width - 22) / 3
        }
      }
    }

    // Everything past the three lives behind this, so neither the popover nor
    // this page ever has to grow a scrollbar of profiles.
    Item {
      width: parent.width
      visible: TunedService.available
      implicitHeight: hint.implicitHeight

      Text {
        id: hint

        width: parent.width
        textFormat: Text.StyledText
        text: `these three map to tuned profiles · <a href="all">see all ${TunedService.allProfiles.length} tuned profiles</a> for anything else, including ones you have written yourself`
        font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
        color: Theme.alpha(Theme.text, 0.3)
        linkColor: Theme.alpha(Theme.text, 0.55)
        wrapMode: Text.WordWrap
        onLinkActivated: root.showAll = !root.showAll
      }
    }

    // The full list, inline rather than in a dialog: it is a list of names, and
    // a window to hold one is more ceremony than the content deserves. Clicking
    // one switches to it, which is the honest behaviour -- tuned has no notion
    // of a profile you may look at but not select.
    SettingsCard {
      width: parent.width
      visible: root.showAll && TunedService.available
      padV: 8
      spacing: 0

      Flickable {
        width: parent.width
        height: Math.min(contentHeight, 154)
        contentHeight: allRows.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: allRows
          width: parent.width

          Repeater {
            model: TunedService.allProfiles

            Rectangle {
              id: allRow

              required property string modelData

              readonly property bool current: TunedService.activeProfile === allRow.modelData

              width: allRows.width
              implicitHeight: 22
              radius: Theme.radiusMenuRow
              color: allMouse.containsMouse ? Theme.surface04 : "transparent"

              MouseArea {
                id: allMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: TunedService.applyProfile(allRow.modelData)
              }

              Text {
                anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
                text: allRow.modelData
                font {
                  family: Theme.fontMono
                  pixelSize: 10
                  weight: allRow.current ? 600 : 400
                }
                color: allRow.current ? Theme.accentSoft : Theme.alpha(Theme.text, 0.6)
              }

              Text {
                anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                visible: PowerStore.keyForTuned(allRow.modelData) !== ""
                text: PowerStore.keyForTuned(allRow.modelData)
                font { family: Theme.fontMono; pixelSize: 9; weight: 400 }
                color: Theme.alpha(Theme.text, 0.3)
              }
            }
          }
        }
      }
    }
  }

  property bool showAll: false

  // -- switching -------------------------------------------------------------

  Column {
    width: parent.width
    spacing: 8
    visible: TunedService.available

    SectionHeading { width: parent.width; text: "switching" }

    SettingsCard {
      width: parent.width
      padV: 0
      padH: 0
      spacing: 0

      SettingsListRow {
        width: parent.width
        divider: false
        title: "switch automatically on unplug"
        // Said plainly, because the handoff's own wording ("tuned's own
        // ac/battery rules") describes something tuned does not expose over
        // D-Bus -- see the note in TunedService. What actually happens is this.
        subtitle: "the cable coming out is the trigger, not a timer. a manual pick wins until the next unplug"

        TogglePill {
          anchors.verticalCenter: parent.verticalCenter
          checked: PowerStore.autoSwitch
          onToggled: PowerStore.values.autoSwitch = !PowerStore.autoSwitch
        }
      }

      SettingsListRow {
        width: parent.width
        indent: true
        enabled: PowerStore.autoSwitch
        title: "on battery"
        subtitle: "applied the moment the cable comes out"

        Segmented {
          anchors.verticalCenter: parent.verticalCenter
          // performance is deliberately absent: it is not a thing to land on
          // by unplugging, and offering it here is offering a foot-gun.
          options: [
            { value: "powersave", label: "powersave" },
            { value: "balanced", label: "balanced" }
          ]
          value: PowerStore.onBatteryProfile
          onPicked: v => PowerStore.values.onBatteryProfile = v
        }
      }

      SettingsListRow {
        width: parent.width
        indent: true
        enabled: PowerStore.autoSwitch
        title: "on power"
        subtitle: "a manual pick always wins until you unplug again"

        Segmented {
          anchors.verticalCenter: parent.verticalCenter
          options: [
            { value: "powersave", label: "powersave" },
            { value: "balanced", label: "balanced" },
            { value: "performance", label: "performance" }
          ]
          value: PowerStore.onPowerProfile
          onPicked: v => PowerStore.values.onPowerProfile = v
        }
      }

      SettingsListRow {
        width: parent.width
        enabled: PowerStore.autoSwitch
        title: "drop to powersave below"
        subtitle: "one toast when it happens, no silent switch"

        CrimsonSlider {
          anchors.verticalCenter: parent.verticalCenter
          width: 110
          // 5–50%. Above 50 the machine would spend most of its life in
          // powersave, which is a profile choice rather than a threshold.
          value: (PowerStore.dropBelow - 5) / 45
          onMoved: v => PowerStore.values.dropBelow = Math.round(5 + v * 45)
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: 32
          horizontalAlignment: Text.AlignRight
          // `enabled` is inherited from the row, so the readout fades with the
          // slider it belongs to instead of staying the brightest thing left.
          opacity: enabled ? 1 : 0.4
          text: `${PowerStore.dropBelow}%`
          font { family: Theme.fontMono; pixelSize: 10; weight: 600 }
          color: Theme.text
        }
      }
    }
  }

  // -- suspend & screen · battery health -------------------------------------
  // Its own file: none of it goes through tuned, so it neither reads nor is
  // replaced by anything above.
  SuspendAndHealth { width: parent.width }
}
