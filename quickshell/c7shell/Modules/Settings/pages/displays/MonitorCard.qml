pragma ComponentBehavior: Bound
import QtQuick
import qs.Theme
import qs.Common
import qs.Services
import qs.Modules.Settings

SettingsCard {
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

  // The selected mode is the staged one while a pick is pending, else the
  // live mode. Both dropdowns and the rate list read it through selRes/selRate,
  // so a cancel that clears the staging drops the pickers back to the live
  // mode, and a mode Hyprland refuses springs them back once the re-read lands.
  readonly property string selMode:
    DisplayService.stagedFor(card.monitor.name).mode || card.mode
  readonly property string selRes: card.selMode.split("@")[0]
  readonly property string selRate: card.selMode.split("@")[1]

  // Only ever stages a resolution+rate pair that came out of availableModes.
  function applyMode(res, rate) {
    if (!card.parsed.some(m => m.res === res && m.rate === rate)) return
    DisplayService.stage(card.monitor.name, { mode: `${res}@${rate}` })
  }

  // Rotation, as Hyprland's transform 0..3. The flipped variants (4..7) are
  // not offered here; a monitor already sitting on one still reads correctly
  // because the label list is indexed by value. Staged like mode and scale,
  // so the picker shows the pending value until commit or revert.
  readonly property var rotations: ["normal", "90°", "180°", "270°"]
  readonly property int curTransform:
    DisplayService.stagedFor(card.monitor.name).transform
      ?? (card.monitor.lastIpcObject?.transform ?? 0)

  readonly property int brightnessRow: BrightnessService.rowFor(card.monitor.name)
  readonly property var backend: card.brightnessRow >= 0
    ? BrightnessService.screens[card.brightnessRow] : null

  // Staged to turn off on the next apply -- dimmed so it reads as on its way
  // out while its controls stay reachable in case that was a misclick.
  readonly property bool willDisable:
    DisplayService.stagedFor(card.monitor.name).disabled === true
  opacity: card.willDisable ? 0.55 : 1

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

        Chip {
          anchors.verticalCenter: parent.verticalCenter
          text: card.willDisable ? "keep on" : "disable"
          accented: card.willDisable
          // setEnabled itself refuses to stage off the last screen left on.
          onTriggered: DisplayService.setEnabled(card.monitor.name, card.willDisable)
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
    // The staged value while one is pending, else the live one.
    value: DisplayService.stagedFor(card.monitor.name).scale ?? card.monitor.scale
    from: 0.5
    to: 3
    step: 0.25
    decimals: 2
    // Staged, not applied: Hyprland only sees it on commit, and refuses a
    // scale that lands the logical size on a fraction of a pixel then -- the
    // slider springs back when the re-read lands.
    onMoved: v => DisplayService.stage(card.monitor.name, { scale: v })
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

  // -- rotation
  Item {
    width: parent.width
    implicitHeight: 22

    Text {
      id: rotLabel
      anchors { left: parent.left; verticalCenter: parent.verticalCenter }
      width: 108
      text: "rotation"
      font { family: Theme.fontMono; pixelSize: 11; weight: 500 }
      color: Theme.alpha(Theme.text, 0.7)
    }

    Dropdown {
      anchors { left: rotLabel.right; leftMargin: 12; verticalCenter: parent.verticalCenter }
      width: 118
      options: card.rotations
      // The monitor is the source of truth once the staging clears: a
      // transform Hyprland refuses springs the label back rather than
      // leaving it claiming a rotation that never took.
      current: card.rotations[card.curTransform] ?? card.rotations[0]
      onPicked: label => DisplayService.stage(card.monitor.name,
        { transform: card.rotations.indexOf(label) })
    }
  }
}
