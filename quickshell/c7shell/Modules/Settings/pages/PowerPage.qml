pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import qs.Theme
import qs.Common
import qs.Services
import qs.Modules.Settings

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
    Rectangle {
      width: parent.width
      visible: !TunedService.available
      implicitHeight: missing.implicitHeight + 26
      radius: Theme.radiusCard
      color: Theme.alpha(Theme.warning, 0.05)
      border.width: 1
      border.color: Theme.alpha(Theme.warning, 0.3)

      Column {
        id: missing

        anchors {
          left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
          leftMargin: 14; rightMargin: 14
        }
        spacing: 9

        Row {
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
            ? "The profile list is hidden rather than faked — there is nothing to read the active profile from. Everything below still works."
            : "The three profile buttons map to tuned profiles, so they need tuned. Everything below still works without it."
          font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
          lineHeight: 1.5
          wrapMode: Text.WordWrap
          color: Theme.alpha(Theme.text, 0.45)
        }

        Rectangle {
          visible: TunedService.installed
          implicitWidth: enableLabel.implicitWidth + 26
          implicitHeight: 28
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
          text: `${PowerStore.dropBelow}%`
          font { family: Theme.fontMono; pixelSize: 10; weight: 600 }
          color: Theme.text
        }
      }
    }
  }

  // -- suspend & screen · battery health -------------------------------------

  Row {
    width: parent.width
    spacing: 14

    Column {
      width: (parent.width - 14) - 290
      spacing: 8

      SectionHeading { width: parent.width; text: "suspend & screen" }

      SettingsCard {
        width: parent.width
        padV: 0
        padH: 0
        spacing: 0

        // hypridle reads its config once at startup, so every change here
        // rewrites ~/.config/hypr/hypridle.conf and restarts it. The page is
        // the single editor for these and for the lid below, which is the only
        // way the two cannot end up disagreeing.
        TimingRow {
          width: parent.width
          divider: false
          title: "blank screen"
          seconds: PowerStore.blankScreen
          options: [0, 60, 120, 300, 600, 900, 1800]
          onPicked: v => PowerStore.values.blankScreen = v
        }

        TimingRow {
          width: parent.width
          enabled: PowerStore.blankScreen > 0
          title: "lock after blank"
          seconds: PowerStore.lockAfterBlank
          options: [0, 30, 60, 300, 600]
          neverLabel: "immediately"
          onPicked: v => PowerStore.values.lockAfterBlank = v
        }

        TimingRow {
          width: parent.width
          title: "suspend on battery"
          seconds: PowerStore.suspendOnBattery
          options: [0, 600, 1200, 1800, 3600]
          onPicked: v => PowerStore.values.suspendOnBattery = v
        }

        SettingsListRow {
          width: parent.width
          title: "lid close"
          // logind, not hypridle -- and it is system state, so this one asks.
          subtitle: "written to logind, which needs an admin password"

          Dropdown {
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: 104
            options: ["suspend", "lock", "ignore", "poweroff"]
            current: PowerStore.lidClose
            onPicked: v => PowerService.setLidClose(v)
          }
        }
      }
    }

    Column {
      width: 290
      spacing: 8

      SectionHeading { width: parent.width; text: "battery health" }

      SettingsCard {
        width: parent.width
        spacing: 9

        Text {
          width: parent.width
          visible: !BatteryService.present
          text: "no battery detected on this machine"
          font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
          color: Theme.alpha(Theme.text, 0.35)
        }

        Column {
          width: parent.width
          visible: BatteryService.present
          spacing: 4

          HealthRow {
            width: parent.width
            key: "capacity"
            // Health, then what it means in Wh. A pack that does not report
            // health drops the ratio rather than printing "0% of 0 Wh".
            value: BatteryService.health >= 0
              ? `${BatteryService.health}% · ${BatteryService.energyFullWh.toFixed(1)} of ${BatteryService.energyDesignWh.toFixed(1)} Wh`
              : `${BatteryService.energyFullWh.toFixed(1)} Wh`
          }
          HealthRow {
            width: parent.width
            visible: BatteryService.cycles > 0
            key: "cycles"
            value: `${BatteryService.cycles}`
          }
          HealthRow {
            width: parent.width
            key: "charge"
            value: `${BatteryService.percent}% · ${BatteryService.energyWh.toFixed(1)} Wh`
          }
        }

        Item {
          width: parent.width
          visible: BatteryService.present
          implicitHeight: limitBody.implicitHeight + 9

          Rectangle {
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: 1
            color: Theme.alpha(Theme.text, 0.06)
          }

          Item {
            id: limitBody

            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            implicitHeight: Math.max(limitText.implicitHeight, limitPick.implicitHeight)

            Column {
              id: limitText

              anchors {
                left: parent.left; right: limitPick.left; rightMargin: 12
                verticalCenter: parent.verticalCenter
              }
              spacing: 2

              Text {
                width: parent.width
                text: "charge limit"
                font { family: Theme.fontMono; pixelSize: 10; weight: 500 }
                color: Theme.alpha(Theme.text, 0.75)
              }
              Text {
                width: parent.width
                // The value shown is the one sysfs reports back, never the one
                // that was asked for: several vendors clamp the write, and a
                // limit that did not take must not read as though it did.
                text: !PowerService.limitSupported
                  ? "this pack exposes no charge threshold"
                  : PowerService.chargeLimit >= 100
                    ? "charges to full"
                    : `stops at ${PowerService.chargeLimit}% to slow wear`
                font { family: Theme.fontMono; pixelSize: 9; weight: 400 }
                color: Theme.alpha(Theme.text, 0.35)
                wrapMode: Text.WordWrap
              }
            }

            Dropdown {
              id: limitPick

              anchors { right: parent.right; verticalCenter: parent.verticalCenter }
              implicitWidth: 76
              enabled: PowerService.limitSupported
              opacity: PowerService.limitSupported ? 1 : 0.4
              options: ["60%", "70%", "80%", "85%", "90%", "95%", "off"]
              current: PowerService.chargeLimit >= 100 || PowerService.chargeLimit === 0
                ? "off" : `${PowerService.chargeLimit}%`
              onPicked: v => PowerService.setChargeLimit(v === "off" ? 100 : parseInt(v))
            }
          }
        }
      }
    }
  }

  // -- components ------------------------------------------------------------

  component HealthRow: Item {
    id: hrow

    required property string key
    required property string value

    implicitHeight: hrow.visible ? 14 : 0

    Text {
      anchors { left: parent.left; verticalCenter: parent.verticalCenter }
      text: hrow.key
      font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
      color: Theme.alpha(Theme.text, 0.42)
    }
    Text {
      anchors { right: parent.right; verticalCenter: parent.verticalCenter }
      text: hrow.value
      font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
      color: Theme.text
    }
  }

  // A SettingsListRow whose control is a duration. Seconds in, seconds out --
  // the minutes are a presentation detail and never reach PowerStore.
  component TimingRow: SettingsListRow {
    id: trow

    required property int seconds
    required property var options
    property string neverLabel: "never"

    signal picked(int value)

    function label(s) {
      if (s <= 0) return trow.neverLabel
      if (s < 60) return `${s} s`
      return `${s / 60} min`
    }

    Dropdown {
      anchors.verticalCenter: parent.verticalCenter
      implicitWidth: 92
      options: trow.options.map(s => trow.label(s))
      current: trow.label(trow.seconds)
      onPicked: v => {
        const i = trow.options.map(s => trow.label(s)).indexOf(v)
        if (i >= 0) trow.picked(trow.options[i])
      }
    }
  }

  component ProfileCard: Rectangle {
    id: pcard

    required property var profile

    readonly property bool applying: TunedService.applying === pcard.profile.key
    readonly property bool current: TunedService.applying !== ""
      ? pcard.applying : TunedService.activeKey === pcard.profile.key

    implicitHeight: pbody.implicitHeight + 28
    radius: Theme.radiusCard
    color: pcard.current ? Theme.accentFill : Theme.surface04
    border.width: 1
    border.color: pcard.current ? Theme.accentBorder : Theme.hairline
    opacity: TunedService.applying !== "" && !pcard.applying ? 0.45 : 1

    Behavior on color { ColorAnimation { duration: 120 } }
    Behavior on opacity { NumberAnimation { duration: 120 } }

    // The active card's `0 0 24px` glow. RectangularShadow rather than
    // MultiEffect for the same reason CrimsonSlider uses it: MultiEffect would
    // repaint the card on top of itself.
    RectangularShadow {
      anchors.fill: parent
      radius: parent.radius
      color: Theme.alpha(Theme.accent, 0.14)
      blur: 24
      visible: pcard.current
      z: -1
    }

    MouseArea {
      anchors.fill: parent
      // A card click is the user watching it happen; no toast.
      onClicked: TunedService.apply(pcard.profile.key, false)
    }

    Column {
      id: pbody

      anchors {
        left: parent.left; right: parent.right; top: parent.top
        leftMargin: 14; rightMargin: 14; topMargin: 14
      }
      spacing: 9

      Item {
        width: parent.width
        implicitHeight: 30

        Rectangle {
          id: ptile

          anchors { left: parent.left; verticalCenter: parent.verticalCenter }
          width: 30
          height: 30
          radius: Theme.radiusChip
          color: pcard.current ? Theme.alpha(Theme.accent, 0.18) : Theme.surface05
          border.width: 1
          border.color: pcard.current ? Theme.alpha(Theme.accent, 0.35) : Theme.hairline

          Icon {
            anchors.centerIn: parent
            name: pcard.profile.icon
            size: 15
            tint: pcard.current ? Theme.accentSoft : Theme.text2
          }
        }

        Column {
          anchors {
            left: ptile.right; leftMargin: 9
            right: pbadge.left; rightMargin: 6
            verticalCenter: parent.verticalCenter
          }
          spacing: 1

          Text {
            width: parent.width
            text: pcard.profile.label
            font { family: Theme.fontMono; pixelSize: 11; weight: 600 }
            color: pcard.current ? Theme.text : Theme.alpha(Theme.text, 0.8)
            elide: Text.ElideRight
          }
          Text {
            width: parent.width
            // The tuned name is on the card because the mapping is the thing a
            // user with hand-written profiles came here to check.
            text: `tuned: ${pcard.profile.tuned}`
            font { family: Theme.fontMono; pixelSize: 9; weight: 400 }
            color: Theme.alpha(Theme.text, pcard.current ? 0.4 : 0.35)
            elide: Text.ElideRight
          }
        }

        Item {
          id: pbadge

          anchors { right: parent.right; verticalCenter: parent.verticalCenter }
          width: pcard.applying ? 12 : (pcard.current ? activeBadge.implicitWidth : 0)
          height: 14

          Spinner {
            anchors.centerIn: parent
            size: 11
            visible: pcard.applying
            arcColor: Theme.alpha(Theme.accent, 0.85)
          }

          Rectangle {
            id: activeBadge

            anchors.centerIn: parent
            visible: pcard.current && !pcard.applying
            implicitWidth: activeText.implicitWidth + 14
            implicitHeight: 14
            radius: 5
            color: Theme.accent

            Text {
              id: activeText
              anchors.centerIn: parent
              text: "ACTIVE"
              font { family: Theme.fontMono; pixelSize: 8; weight: 600; letterSpacing: 0.4 }
              color: Theme.textOnAccent
            }
          }
        }
      }

      Text {
        width: parent.width
        text: pcard.profile.blurb
        font { family: Theme.fontMono; pixelSize: 9; weight: 400 }
        lineHeight: 1.7
        wrapMode: Text.WordWrap
        color: Theme.alpha(Theme.text, pcard.current ? 0.55 : 0.45)
      }

      Item {
        width: parent.width
        implicitHeight: pstats.implicitHeight + 9

        Rectangle {
          anchors { left: parent.left; right: parent.right; top: parent.top }
          height: 1
          color: pcard.current ? Theme.alpha(Theme.accent, 0.2) : Theme.alpha(Theme.text, 0.06)
        }

        Column {
          id: pstats
          anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
          spacing: 4

          CardStat {
            width: parent.width
            highlighted: pcard.current
            key: "idle draw"
            // Measured on this machine, never hard-coded: a 14 W
            // "performance" printed on a fanless tablet is the UI lying about
            // the hardware it is running on.
            value: TunedService.idleDrawText(pcard.profile.key)
          }
          CardStat {
            width: parent.width
            highlighted: pcard.current
            key: "boost"
            value: pcard.profile.boost
          }
        }
      }
    }
  }

  component CardStat: Item {
    id: stat

    required property string key
    required property string value
    property bool highlighted: false

    implicitHeight: 13

    Text {
      anchors { left: parent.left; verticalCenter: parent.verticalCenter }
      text: stat.key
      font { family: Theme.fontMono; pixelSize: 9; weight: 400 }
      color: Theme.alpha(Theme.text, stat.highlighted ? 0.45 : 0.4)
    }
    Text {
      anchors { right: parent.right; verticalCenter: parent.verticalCenter }
      text: stat.value
      font { family: Theme.fontMono; pixelSize: 9; weight: 400 }
      color: stat.highlighted ? Theme.text : Theme.alpha(Theme.text, 0.65)
      elide: Text.ElideRight
    }
  }
}
