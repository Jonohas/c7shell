import QtQuick
import qs.Theme
import qs.Common
import qs.Services
import qs.Modules.Settings
import qs.Modules.Bar

// The bar's own modules, as choices rather than as look-and-feel. Everything
// here writes ShellStore (~/.config/hypr/shell.json); the page owns no state,
// and the preview at the bottom is the real widget rather than a drawing of it.
//
// The page's sections are Columns rather than bare cards because a heading
// belongs 8px above its card, not 14px like the gap BETWEEN sections.
SettingsPage {
  id: root

  title: "Topbar & widgets"
  subtitle: "what the bar shows, and how much each widget says"

  // -- layout ----------------------------------------------------------------

  Column {
    width: parent.width
    spacing: 8

    SectionHeading { width: parent.width; text: "layout"; rule: false }

    SettingsCard {
      width: parent.width
      padV: 0
      padH: 0
      spacing: 0

      SettingsListRow {
        width: parent.width
        divider: false
        title: "island style"
        subtitle: ShellStore.islandStyle === "islands"
          ? "floating pills with no bar behind them"
          : "one bar surface behind every widget"

        Segmented {
          anchors.verticalCenter: parent.verticalCenter
          options: [
            { value: "islands", label: "islands" },
            { value: "bar", label: "solid bar" }
          ]
          value: ShellStore.islandStyle
          onPicked: v => ShellStore.values.islandStyle = v
        }
      }

      SettingsListRow {
        width: parent.width
        title: "workspace indicator"
        subtitle: {
          switch (ShellStore.workspaceIndicator) {
          case "numerals": return "the workspace number, plainly"
          // Hyprland only names a workspace if hyprland.conf assigns one; say
          // so, or the option looks broken on a default config.
          case "names": return "the name from hyprland.conf, the number where there is none"
          default: return "dice pips up to 6, dominos to 12, numerals beyond"
          }
        }

        Segmented {
          anchors.verticalCenter: parent.verticalCenter
          options: [
            { value: "dice", label: "dice" },
            { value: "numerals", label: "numerals" },
            { value: "names", label: "names" }
          ]
          value: ShellStore.workspaceIndicator
          onPicked: v => ShellStore.values.workspaceIndicator = v
        }
      }

      SettingsListRow {
        width: parent.width
        title: "global menu"
        // Not a decoration: turning this off gives the menus BACK to the app,
        // and an app that is already open keeps whatever it decided when its
        // window was created (Qt asks for the registrar once and caches the
        // answer). Say so, or the toggle looks broken on the dolphin window
        // that prompted it.
        subtitle: ShellStore.globalMenu
          ? "the focused app's menu bar, next to the workspaces. windows already open keep the menu bar they started with"
          : "apps draw their own menu bars. reopen a window to see the change"

        TogglePill {
          anchors.verticalCenter: parent.verticalCenter
          checked: ShellStore.globalMenu
          onToggled: ShellStore.values.globalMenu = !ShellStore.globalMenu
        }
      }
    }

    // The bar's inset from the screen edges. Shell geometry, not compositor
    // geometry: these two land in Theme and the bar rebinds on the next frame,
    // so there is nothing to push at hyprland.
    SettingsCard {
      width: parent.width
      spacing: 12

      SliderRow {
        width: parent.width
        label: "bar gap top"; suffix: "px"
        // 32, not further: the bar window reserves 36px below the island for the
        // drop shadow, and a taller inset would push the island's own shadow past
        // the bottom of the surface it is drawn on.
        value: AppearanceStore.barMarginTop; from: 0; to: 32
        onMoved: v => AppearanceStore.values.barMarginTop = v
      }
      SliderRow {
        width: parent.width
        label: "bar gap sides"; suffix: "px"
        value: AppearanceStore.barMarginSide; from: 0; to: 80
        onMoved: v => AppearanceStore.values.barMarginSide = v
      }
    }
  }

  // -- battery ---------------------------------------------------------------

  Column {
    width: parent.width
    spacing: 8

    SectionHeading { width: parent.width; text: "battery" }

    // A machine with no pack greys the section out rather than offering
    // settings for a widget that is not on screen.
    Text {
      width: parent.width
      visible: !BatteryService.present
      text: "no battery detected — the widget is hidden on this machine"
      font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
      color: Theme.alpha(Theme.text, 0.35)
    }

    SettingsCard {
      width: parent.width
      padV: 0
      padH: 0
      spacing: 0
      enabled: BatteryService.present
      opacity: BatteryService.present ? 1 : 0.45

      SettingsListRow {
        width: parent.width
        divider: false
        title: "show percentage"
        subtitle: `the number next to the icon, e.g. <font color="${Theme.alpha(Theme.text, 0.6)}">${BatteryService.percent}%</font>`

        TogglePill {
          anchors.verticalCenter: parent.verticalCenter
          checked: ShellStore.batteryPercentage
          onToggled: ShellStore.values.batteryPercentage = !ShellStore.batteryPercentage
        }
      }

      SettingsListRow {
        width: parent.width
        title: "show wattage"
        subtitle: `live power draw, signed: <font color="${Theme.accentSoft}">−14.2 W</font> discharging, <font color="${Theme.success}">+31.0 W</font> charging`

        TogglePill {
          anchors.verticalCenter: parent.verticalCenter
          checked: ShellStore.batteryWattage
          onToggled: ShellStore.values.batteryWattage = !ShellStore.batteryWattage
        }
      }

      // The two wattage-dependent rows stay VISIBLE while the toggle above is
      // off, and only disable: hiding them would hide what the toggle unlocks.
      SettingsListRow {
        width: parent.width
        indent: true
        enabled: ShellStore.batteryWattage
        title: "wattage precision"
        subtitle: "one decimal keeps the pill from resizing every second"

        Segmented {
          anchors.verticalCenter: parent.verticalCenter
          options: [
            { value: 0, label: "14 W" },
            { value: 1, label: "14.2 W" }
          ]
          value: ShellStore.batteryWattagePrecision
          onPicked: v => ShellStore.values.batteryWattagePrecision = v
        }
      }

      SettingsListRow {
        width: parent.width
        indent: true
        enabled: ShellStore.batteryWattage
        title: "only while discharging"
        subtitle: "hides the draw on AC, where it rarely tells you anything"

        TogglePill {
          anchors.verticalCenter: parent.verticalCenter
          checked: ShellStore.batteryWattageOnlyOnBattery
          onToggled: ShellStore.values.batteryWattageOnlyOnBattery
            = !ShellStore.batteryWattageOnlyOnBattery
        }
      }

      SettingsListRow {
        width: parent.width
        title: "time remaining"
        subtitle: "in the hover tooltip only — too jumpy for the bar"

        TogglePill {
          anchors.verticalCenter: parent.verticalCenter
          checked: ShellStore.batteryTimeRemaining
          onToggled: ShellStore.values.batteryTimeRemaining = !ShellStore.batteryTimeRemaining
        }
      }

      SettingsListRow {
        width: parent.width
        title: "warn below"
        subtitle: "icon and text turn crimson, one toast"

        CrimsonSlider {
          anchors.verticalCenter: parent.verticalCenter
          width: 110
          // 5–40%, in whole percent. Below 5 the warning lands after the
          // firmware has already begun shutting the machine down.
          value: (ShellStore.batteryWarnBelow - 5) / 35
          onMoved: v => ShellStore.values.batteryWarnBelow = Math.round(5 + v * 35)
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: 32
          horizontalAlignment: Text.AlignRight
          text: `${ShellStore.batteryWarnBelow}%`
          font { family: Theme.fontMono; pixelSize: 10; weight: 600 }
          color: Theme.text
        }
      }
    }
  }

  // -- preview ---------------------------------------------------------------

  Column {
    width: parent.width
    spacing: 8
    visible: BatteryService.present

    SectionHeading { width: parent.width; text: "preview" }

    SettingsCard {
      width: parent.width
      spacing: 11

      Item {
        width: parent.width
        implicitHeight: previewPill.implicitHeight

        // The real widget reading the real battery, in a stand-in for the bar's
        // own slot: this is not a drawing of the result, it IS the result.
        Rectangle {
          id: previewPill

          anchors.horizontalCenter: parent.horizontalCenter
          implicitWidth: preview.implicitWidth + 14
          implicitHeight: preview.implicitHeight + 10
          radius: 12
          color: preview.warn
            ? Theme.accentFill : Theme.alpha(Theme.glassBase, Theme.glassAlphaPanel)
          border.width: 1
          border.color: preview.warn ? Theme.accentBorder : Theme.hairlineStrong

          BatteryIndicator {
            id: preview
            anchors.centerIn: parent
          }
        }
      }

      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: "live · updates with the real battery, not a mock"
        font { family: Theme.fontMono; pixelSize: 9; weight: 400 }
        color: Theme.alpha(Theme.text, 0.3)
      }
    }
  }
}
