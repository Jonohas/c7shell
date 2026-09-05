pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Hyprland
import qs.Theme
import qs.Common
import qs.Services
import qs.Modules.Settings

// A plan of the desk you can drag screens around on, then one card per
// connected monitor, built from Hyprland's own monitor list — no panel is named
// anywhere in this file. Brightness comes from whatever backend
// BrightnessService discovered for that connector; mode, scale and position go
// out as hl.monitor() through DisplayService.
//
// Everything applied here is also SAVED, per desk, to ~/.config/hypr/displays.json
// via DisplayService -- never into conf/monitors.lua, whose hand-written
// CATALOG/PROFILES no dialog could rebuild. That file keeps deciding which
// monitors are on (and the whole lid story); the saved layout only overrides
// the position, mode and scale it would otherwise have chosen. "use profile"
// throws the saved one away again.
SettingsPage {
  id: root

  title: "Displays"
  subtitle: "arrangement · scale · brightness"

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
          text: "auto"
          // Hyprland re-places every output left to right in its own order.
          // Not saved: "auto" is a request to let hyprland decide, which is
          // what having no saved entry already means.
          onTriggered: {
            for (const m of Hyprland.monitors.values)
              DisplayService.apply(m.name, { position: "auto" })
          }
        }

        Chip {
          text: "use profile"
          enabled: DisplayService.hasSaved
          // Drops this desk's saved layout and reloads, so hyprland comes back
          // up on conf/monitors.lua's own profile.
          onTriggered: DisplayService.forget()
        }
      }
    }

    ArrangeCanvas { width: parent.width }

    Text {
      width: parent.width
      wrapMode: Text.WordWrap
      text: "drag a screen to move it. edges snap to the neighbouring screen so "
        + "they butt up; the position is applied when you let go."
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

  SettingsCard {
    width: parent.width

    Text {
      width: parent.width
      wrapMode: Text.WordWrap
      text: DisplayService.hasSaved
        ? "position, resolution and scale are saved for this set of screens in "
          + "~/.config/hypr/displays.json and re-applied on replug, reload and "
          + "login. plug in a different screen and that desk remembers its own "
          + "arrangement. \"use profile\" forgets this one and falls back to "
          + "~/.config/hypr/conf/monitors.lua, which this page never writes to."
        : "nothing saved for this set of screens yet — the layout comes from "
          + "~/.config/hypr/conf/monitors.lua. move a screen or change a mode "
          + "and it is remembered here from then on, per set of screens."
      font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
      color: Theme.alpha(Theme.text, 0.4)
    }
  }

  // -- delegates ---------------------------------------------------------------

  component MonitorCard: SettingsCard {
    id: card

    required property var monitor

    // Hyprland reports the physical mode; availableModes is only on the raw ipc
    // object, and reads "3440x1440@99.99Hz" where hl.monitor() wants it without
    // the unit.
    readonly property string curRes: `${card.monitor.width}x${card.monitor.height}`
    readonly property string curRate:
      (card.monitor.lastIpcObject?.refreshRate ?? 0).toFixed(2)
    readonly property string mode: `${card.curRes}@${card.curRate}`

    // availableModes lists resolution and rate together — 13 entries on the
    // laptop, 43 on the ultrawide — which is unreadable as one flat list. Split
    // once here: `resolutions` is the deduplicated left half, `rates` only the
    // rates the SELECTED resolution actually offers, so picking 3840x2160
    // narrows the second list to 60.00 / 59.94 / 50.00 / 30.00 / 29.97.
    // Hyprland repeats some modes verbatim, hence the dedupe on both.
    readonly property var parsed: (card.monitor.lastIpcObject?.availableModes ?? [])
      .map(m => /^(\d+x\d+)@([\d.]+)Hz$/.exec(m))
      .filter(m => m !== null)
      .map(m => ({ res: m[1], rate: m[2] }))

    readonly property var resolutions:
      [...new Set(card.parsed.map(m => m.res))]
    readonly property var rates:
      [...new Set(card.parsed.filter(m => m.res === card.selRes).map(m => m.rate))]

    // Seeded from the monitor and re-seeded whenever it changes, so a mode
    // Hyprland refuses springs the dropdowns back rather than leaving them
    // claiming something that never took.
    property string selRes: card.curRes
    property string selRate: card.curRate
    onModeChanged: { card.selRes = card.curRes; card.selRate = card.curRate }

    // Only ever applies a resolution+rate pair that came out of availableModes.
    function applyMode(res, rate) {
      if (!card.parsed.some(m => m.res === res && m.rate === rate)) return
      card.selRes = res
      card.selRate = rate
      DisplayService.apply(card.monitor.name, { mode: `${res}@${rate}` })
    }

    readonly property int brightnessRow: BrightnessService.rowFor(card.monitor.name)
    readonly property var backend: card.brightnessRow >= 0
      ? BrightnessService.screens[card.brightnessRow] : null

    spacing: 11

    // -- header
    Item {
      width: parent.width
      implicitHeight: 30

      Column {
        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
        spacing: 2

        Row {
          spacing: 7

          Text {
            text: card.monitor.name
            font { family: Theme.fontMono; pixelSize: 12; weight: 600 }
            color: Theme.text
          }
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            visible: card.monitor.focused
            width: focusLabel.implicitWidth + 14
            height: 16
            radius: Theme.radiusChip
            color: Theme.accentFill
            border { width: 1; color: Theme.accentBorder }

            Text {
              id: focusLabel
              anchors.centerIn: parent
              text: "focused"
              font { family: Theme.fontMono; pixelSize: 9; weight: 500 }
              color: Theme.accentSoft
            }
          }
        }
        Text {
          text: card.monitor.description
          font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
          color: Theme.alpha(Theme.text, 0.45)
        }
      }

      // The numbers are still worth reading; they are just not the input method
      // any more.
      Text {
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        text: `${card.mode}  ·  ×${card.monitor.scale.toFixed(2)}  ·  `
          + `${card.monitor.x},${card.monitor.y}`
        font { family: Theme.fontMono; pixelSize: 10; weight: 500 }
        color: Theme.alpha(Theme.text, 0.5)
      }
    }

    Rectangle { width: parent.width; height: 1; color: Theme.hairline }

    // -- brightness
    SliderRow {
      width: parent.width
      visible: card.backend !== null && card.backend.value >= 0
      label: "brightness"
      // Reading BrightnessService.screens through rowFor()/percent() is what
      // makes this re-evaluate when a read lands: QML captures the property
      // access even through the function call.
      value: BrightnessService.percent(card.brightnessRow)
      from: 0
      to: 100
      step: 1
      suffix: "%"
      onMoved: v => BrightnessService.setPercent(card.monitor.name, v)
    }

    Text {
      width: parent.width
      visible: card.backend === null || card.backend.value < 0
      wrapMode: Text.WordWrap
      // The honest version of a dead slider. A monitor with no DDC/CI and no
      // /sys/class/backlight entry genuinely cannot be dimmed from here.
      text: card.backend === null
        ? "no brightness backend on this connector — it answers neither ddc/ci nor a backlight device"
        : `brightness unavailable — ${card.backend.error || "waiting for the panel to report a level"}`
      font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
      color: Theme.alpha(Theme.text, 0.4)
    }

    // -- scale
    SliderRow {
      width: parent.width
      label: "scale"
      value: card.monitor.scale
      from: 0.5
      to: 3
      step: 0.25
      decimals: 2
      // Hyprland refuses a scale that lands the logical size on a fraction of a
      // pixel and keeps the old one; the readout follows the monitor, so a
      // refused value visibly springs back rather than lying.
      onMoved: v => DisplayService.apply(card.monitor.name, { scale: v })
    }

    // -- mode
    Item {
      width: parent.width
      implicitHeight: 22
      visible: card.resolutions.length > 0

      Text {
        id: modeLabel
        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
        width: 108
        text: "resolution"
        font { family: Theme.fontMono; pixelSize: 11; weight: 500 }
        color: Theme.alpha(Theme.text, 0.7)
      }

      Row {
        anchors { left: modeLabel.right; leftMargin: 12; verticalCenter: parent.verticalCenter }
        spacing: 8

        Dropdown {
          width: 118
          options: card.resolutions
          current: card.selRes
          // A resolution alone is not a mode. Keep the rate if this resolution
          // offers it, otherwise take its fastest — never send a pair Hyprland
          // does not list.
          onPicked: res => {
            const avail = card.parsed.filter(m => m.res === res).map(m => m.rate)
            card.applyMode(res, avail.indexOf(card.selRate) >= 0 ? card.selRate
              : avail.reduce((a, b) => parseFloat(b) > parseFloat(a) ? b : a))
          }
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "@"
          font { family: Theme.fontMono; pixelSize: 11; weight: 500 }
          color: Theme.alpha(Theme.text, 0.35)
        }

        Dropdown {
          width: 92
          options: card.rates
          current: card.selRate
          onPicked: rate => card.applyMode(card.selRes, rate)
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "hz"
          font { family: Theme.fontMono; pixelSize: 10; weight: 500 }
          color: Theme.alpha(Theme.text, 0.35)
        }
      }
    }
  }
}
