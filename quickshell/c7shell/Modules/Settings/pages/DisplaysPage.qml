pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Hyprland
import qs.Theme
import qs.Common
import qs.Services
import qs.Modules.Settings
import qs.Modules.Settings.pages.displays

// A plan of the desk you can drag screens around on, then one card per
// connected monitor, built from Hyprland's own monitor list — no panel is named
// anywhere in this file. Brightness comes from whatever backend
// BrightnessService discovered for that connector; mode, scale and position go
// out as hl.monitor() through DisplayService.
//
// Everything applied here is also SAVED for the set of screens connected right
// now, to ~/.config/hypr/displays.json via DisplayService -- the implicit model
// KDE and GNOME use, with no named profiles. Plug the same screens back in and
// conf/monitors.lua restores it; "reset" throws it away again.
SettingsPage {
  id: root

  title: "Displays"
  subtitle: "arrangement · scale · brightness"

  // While rearranging, the tiles drag and the page must not flick under them.
  property bool rearranging: false
  interactive: !root.rearranging

  // Nothing on this page touches the compositor until "apply". Both chips hide
  // when there is nothing staged, so the header is clean the rest of the time.
  headerTrailing: [
    Chip {
      visible: DisplayService.hasStaged
      text: "cancel"
      onTriggered: DisplayService.revertStaged()
    },
    Chip {
      visible: DisplayService.hasStaged
      text: "apply"
      accented: true
      onTriggered: DisplayService.commit()
    }
  ]

  SettingsCard {
    width: parent.width

    Item {
      width: parent.width
      implicitHeight: 18

      SectionLabel {
        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
        text: "arrangement"
      }

      Row {
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        spacing: 6

        Chip {
          text: root.rearranging ? "done" : "rearrange"
          accented: root.rearranging
          // Arms the drag on the plan below and freezes the page scroll so a
          // drag does not turn into a flick.
          onTriggered: root.rearranging = !root.rearranging
        }

        Chip {
          text: "auto"
          // Stages "auto" for every output; Hyprland re-places them left to
          // right on apply. Not saved: "auto" is a request to let hyprland
          // decide, which is what having no saved entry already means.
          onTriggered: {
            for (const m of Hyprland.monitors.values)
              DisplayService.stage(m.name, { position: "auto" })
          }
        }

        Chip {
          text: "reset"
          enabled: DisplayService.hasSaved
          // Drops this set of screens' saved layout and reloads, so hyprland
          // comes back up with every screen on and auto placement.
          onTriggered: DisplayService.forget()
        }
      }
    }

    ArrangeCanvas { width: parent.width; dragEnabled: root.rearranging }

    ToggleRow {
      width: parent.width
      label: "snap to screens"
      checked: ShellStore.arrangeSnap
      onToggled: ShellStore.values.arrangeSnap = !ShellStore.arrangeSnap
    }

    // Canvas px, not logical: the reach is how far the cursor travels, and
    // that does not change with how many screens the plan has to fit.
    SliderRow {
      width: parent.width
      label: "snap reach"
      value: ShellStore.arrangeSnapReach
      from: 8
      to: 160
      step: 4
      suffix: "px"
      enabled: ShellStore.arrangeSnap
      opacity: enabled ? 1 : 0.4
      onMoved: v => ShellStore.values.arrangeSnapReach = v
    }

    Text {
      width: parent.width
      wrapMode: Text.WordWrap
      text: root.rearranging
        ? "drag a screen to move it. the outline shows where it lands: "
          + (ShellStore.arrangeSnap
            ? "within snap reach it snaps to touch the nearest screen, past it "
              + "it stays where you drop it. "
            : "exactly where you drop it, or nowhere if that overlaps a screen. ")
          + "the move is staged when you let go — nothing changes "
          + "on screen until you press apply. \"done\" locks the plan."
        : "press \"rearrange\" to drag the screens around. the page scroll pauses "
          + "while you do, so a drag does not turn into a scroll."
      font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
      color: Theme.alpha(Theme.text, 0.4)
    }
  }

  // -- eye saver ----------------------------------------------------------
  // One filter over the whole desk, not a per-monitor setting: hyprsunset owns
  // the gamma of every output at once. Unlike everything else on this page it
  // applies the moment it is touched -- there is nothing to stage when the
  // change IS the preview.
  SettingsCard {
    width: parent.width
    spacing: 9

    SectionLabel { text: "eye saver" }

    ToggleRow {
      width: parent.width
      label: "warm the screen"
      checked: EyeSaverService.enabled
      onToggled: EyeSaverService.setEnabled(!EyeSaverService.enabled)
    }

    SliderRow {
      width: parent.width
      label: "temperature"
      value: EyeSaverService.temperature
      from: EyeSaverService.minTemperature
      to: EyeSaverService.maxTemperature
      step: 100
      suffix: "K"
      onMoved: v => EyeSaverService.setTemperature(v)
    }

    Text {
      width: parent.width
      wrapMode: Text.WordWrap
      text: EyeSaverService.probed && !EyeSaverService.available
        ? "hyprsunset is not installed, so nothing is filtering the screen. "
          + "install it (pacman -S hyprsunset) and the toggle starts working."
        : "cuts the blue end of every screen's gamma. lower is warmer; 6500K is "
          + "daylight, which is the same as off. the filter lives with the shell "
          + "-- it is gone the moment the session is."
      font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
      color: Theme.alpha(Theme.text, 0.4)
    }
  }

  Repeater {
    model: Hyprland.monitors

    MonitorCard {
      required property var modelData
      width: parent.width
      monitor: modelData
    }
  }

  // Screens turned off. A disabled monitor is gone from Hyprland.monitors and so
  // from every card above; DisplayService reads the full output list from
  // `hyprctl monitors all` so they can be switched back on here.
  readonly property var disabledOutputs:
    DisplayService.allOutputs.filter(o => o.disabled)

  SettingsCard {
    width: parent.width
    visible: root.disabledOutputs.length > 0
    spacing: 9

    SectionLabel { text: "disabled" }

    Repeater {
      model: root.disabledOutputs

      Item {
        id: offRow
        required property var modelData
        width: parent.width
        implicitHeight: 26

        // Staged to come back on at the next apply.
        readonly property bool willEnable:
          DisplayService.stagedFor(offRow.modelData.name).disabled === false

        Column {
          anchors { left: parent.left; verticalCenter: parent.verticalCenter }
          spacing: 1

          Text {
            text: offRow.modelData.name
            font { family: Theme.fontMono; pixelSize: 12; weight: 600 }
            color: Theme.text
          }
          Text {
            text: offRow.modelData.description
            font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
            color: Theme.alpha(Theme.text, 0.45)
          }
        }

        Chip {
          anchors { right: parent.right; verticalCenter: parent.verticalCenter }
          text: offRow.willEnable ? "keep off" : "enable"
          accented: !offRow.willEnable
          onTriggered: DisplayService.setEnabled(offRow.modelData.name, !offRow.willEnable)
        }
      }
    }
  }

  SettingsCard {
    width: parent.width

    Text {
      width: parent.width
      wrapMode: Text.WordWrap
      text: DisplayService.hasSaved
        ? "this arrangement is saved for this set of screens in "
          + "~/.config/hypr/displays.json and comes back on replug, reload and "
          + "login. plug in a different set and it remembers its own. \"reset\" "
          + "forgets this one."
        : "nothing saved for this set of screens yet — every screen is on and "
          + "hyprland places them. press apply after any change and it is "
          + "remembered for this set of screens from then on."
      font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
      color: Theme.alpha(Theme.text, 0.4)
    }
  }
}
