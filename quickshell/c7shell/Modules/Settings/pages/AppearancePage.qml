import QtQuick
import qs.Theme
import qs.Common
import qs.Services
import qs.Modules.Settings

// 2b. Every control on this page writes AppearanceStore, which persists to
// ~/.config/hypr/appearance.json and pushes the value at hyprland — the page
// itself owns no state and runs no process.
SettingsPage {
  id: root

  title: "Appearance"
  subtitle: "theme · accent · shell geometry"

  ThemeCards { width: parent.width }

  // -- app colour scheme -----------------------------------------------------
  // Separate from the variant above on purpose: this is what the desktop tells
  // apps that ask (the portal's org.freedesktop.appearance color-scheme), not
  // what the shell paints itself with. Without it every such app defaults to
  // light next to a dark shell. AppearanceStore runs the export.
  SettingsCard {
    width: parent.width
    spacing: 6

    Item {
      width: parent.width
      implicitHeight: 22

      Text {
        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
        text: "app color scheme"
        font { family: Theme.fontMono; pixelSize: 11; weight: 600 }
        color: Theme.alpha(Theme.text, 0.85)
      }

      Row {
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        spacing: 8

        Repeater {
          model: ["dark", "light"]

          Chip {
            id: schemeChip

            required property string modelData

            readonly property bool selected: AppearanceStore.colorScheme === schemeChip.modelData

            anchors.verticalCenter: parent.verticalCenter
            text: schemeChip.modelData
            accented: schemeChip.selected
            onTriggered: AppearanceStore.values.colorScheme = schemeChip.modelData
          }
        }
      }
    }

    Text {
      width: parent.width
      text: "what apps are told to prefer — the shell keeps its own theme either way"
      font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
      color: Theme.alpha(Theme.text, 0.4)
      wrapMode: Text.WordWrap
    }
  }

  // -- inactive border -------------------------------------------------------
  // The active border follows the accent (spec §7), so only its quiet
  // counterpart is a choice. Both are appearance.json-owned; neither is a
  // literal in look-and-feel.lua any more.
  SettingsCard {
    width: parent.width

    Item {
      width: parent.width
      implicitHeight: 22

      Text {
        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
        text: "inactive border"
        font { family: Theme.fontMono; pixelSize: 11; weight: 600 }
        color: Theme.alpha(Theme.text, 0.85)
      }

      Row {
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        spacing: 8

        Repeater {
          model: AppearanceStore.borderChoices

          Rectangle {
            id: borderSwatch

            required property string modelData

            readonly property bool selected: Qt.colorEqual(AppearanceStore.inactiveBorder, borderSwatch.modelData)

            anchors.verticalCenter: parent.verticalCenter
            width: borderSwatch.selected ? 22 : 20
            height: width
            radius: width / 2
            color: borderSwatch.modelData
            border.width: borderSwatch.selected ? 2 : 1
            border.color: borderSwatch.selected ? Theme.textOnAccent : Theme.hairlineStrong

            MouseArea {
              anchors.fill: parent
              onClicked: AppearanceStore.values.inactiveBorder = borderSwatch.modelData
            }
          }
        }
      }
    }
  }

  // -- accent ----------------------------------------------------------------
  SettingsCard {
    id: accentCard

    // The five presets are a shortlist, not the range: anything the store's
    // own /^#[0-9a-fA-F]{6}$/ accepts is a valid accent, and the last swatch in
    // the row discloses AccentPicker to reach the rest of it.
    property bool picking: false

    width: parent.width

    Item {
      width: parent.width
      implicitHeight: 22

      Text {
        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
        text: "accent"
        font { family: Theme.fontMono; pixelSize: 11; weight: 600 }
        color: Theme.alpha(Theme.text, 0.85)
      }

      Row {
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        spacing: 8

        Repeater {
          model: AppearanceStore.accentChoices

          Rectangle {
            id: swatch

            required property string modelData

            // Compared as colors, not strings: an upper-case spelling from a
            // hand-edit is the same accent as the lower-case one.
            readonly property bool selected: Qt.colorEqual(AppearanceStore.accent, swatch.modelData)

            anchors.verticalCenter: parent.verticalCenter
            width: swatch.selected ? 22 : 20
            height: width
            radius: width / 2
            color: swatch.modelData
            border.width: swatch.selected ? 2 : 0
            border.color: Theme.textOnAccent

            MouseArea {
              anchors.fill: parent
              onClicked: {
                AppearanceStore.values.accent = swatch.modelData
                // Picking a preset closes the picker: leaving it open on a
                // colour it no longer describes invites the next drag to undo
                // the click that just happened.
                accentCard.picking = false
              }
            }
          }
        }

        // The way out of the shortlist. Selected when the accent in force is
        // not one of the presets -- which is the only state in which the row
        // would otherwise show nothing selected at all.
        Rectangle {
          id: custom

          readonly property bool selected: !AppearanceStore.accentChoices
            .some(c => Qt.colorEqual(AppearanceStore.accent, c))

          anchors.verticalCenter: parent.verticalCenter
          width: custom.selected || accentCard.picking ? 22 : 20
          height: width
          radius: width / 2
          // Wearing the accent once it IS the accent; a miniature of the
          // picker's own hue strip until then, which says "any colour" in the
          // one place a single fill cannot.
          color: custom.selected ? AppearanceStore.accent : "transparent"
          border.width: custom.selected ? 2 : accentCard.picking ? 1 : 0
          border.color: custom.selected ? Theme.textOnAccent : Theme.hairlineStrong

          Rectangle {
            anchors.fill: parent
            anchors.margins: 3
            radius: width / 2
            visible: !custom.selected
            // The same sweep AccentPicker's strip draws, wrapped round a dot.
            gradient: HueGradient {}
          }

          MouseArea {
            anchors.fill: parent
            onClicked: accentCard.picking = !accentCard.picking
          }
        }
      }
    }

    AccentPicker {
      width: parent.width
      open: accentCard.picking
    }
  }

  // -- geometry --------------------------------------------------------------
  SettingsCard {
    width: parent.width
    spacing: 12

    SliderRow {
      width: parent.width
      label: "rounding"; suffix: "px"
      value: AppearanceStore.rounding; from: 0; to: 40
      onMoved: v => AppearanceStore.values.rounding = v
    }
    SliderRow {
      width: parent.width
      label: "gaps in"; suffix: "px"
      value: AppearanceStore.gapsIn; from: 0; to: 40
      onMoved: v => AppearanceStore.values.gapsIn = v
    }
    SliderRow {
      width: parent.width
      label: "gaps out"; suffix: "px"
      value: AppearanceStore.gapsOut; from: 0; to: 60
      onMoved: v => AppearanceStore.values.gapsOut = v
    }
    SliderRow {
      width: parent.width
      label: "blur size"
      value: AppearanceStore.blurSize; from: 1; to: 20
      onMoved: v => AppearanceStore.values.blurSize = v
    }
    SliderRow {
      width: parent.width
      label: "blur passes"
      value: AppearanceStore.blurPasses; from: 1; to: 5
      onMoved: v => AppearanceStore.values.blurPasses = v
    }
    SliderRow {
      width: parent.width
      label: "inactive opacity"
      value: AppearanceStore.inactiveOpacity; from: 0.3; to: 1
      step: 0.05; decimals: 2
      onMoved: v => AppearanceStore.values.inactiveOpacity = v
    }
    SliderRow {
      width: parent.width
      label: "border width"; suffix: "px"
      value: AppearanceStore.borderWidth; from: 0; to: 10
      onMoved: v => AppearanceStore.values.borderWidth = v
    }
    SliderRow {
      width: parent.width
      label: "animation speed"; suffix: "×"
      value: AppearanceStore.animationSpeed; from: 0.25; to: 4
      step: 0.25; decimals: 2
      // Speed means nothing with animations off; dim it rather than hide it,
      // so the row does not make the card jump height as the toggle flips.
      enabled: AppearanceStore.animationsEnabled
      opacity: AppearanceStore.animationsEnabled ? 1 : 0.4
      onMoved: v => AppearanceStore.values.animationSpeed = v
    }
    ToggleRow {
      width: parent.width
      label: "animations"
      checked: AppearanceStore.animationsEnabled
      onToggled: AppearanceStore.values.animationsEnabled = !AppearanceStore.animationsEnabled
    }
  }

  // -- wallpaper -------------------------------------------------------------
  SettingsCard {
    width: parent.width
    spacing: 12

    Item {
      width: parent.width
      implicitHeight: 36

      Text {
        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
        text: "wallpaper"
        font { family: Theme.fontMono; pixelSize: 11; weight: 600 }
        color: Theme.alpha(Theme.text, 0.85)
      }

      WallpaperThumb {
        anchors { right: browse.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
        path: AppearanceStore.wallpaper
      }

      Text {
        id: browse
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        // The portal can take a second to start its backend the first time; a
        // button that looks like it did nothing gets clicked again.
        text: AppearanceStore.browsing ? "opening…" : "browse →"
        font { family: Theme.fontMono; pixelSize: 10; weight: 500 }
        color: AppearanceStore.browsing ? Theme.text3 : Theme.accentSoft

        MouseArea {
          anchors.fill: parent
          anchors.margins: -4
          // The desktop's own file dialog, through xdg-desktop-portal -- the
          // same one every other app here opens (README, "The file picker").
          // The store owns the process, as it owns every other one on this page.
          onClicked: AppearanceStore.browseWallpaper()
        }
      }
    }

    Rectangle {
      width: parent.width
      implicitHeight: 28
      radius: Theme.radiusTile
      color: Theme.surface04

      TextInput {
        id: pathField

        anchors {
          left: parent.left; leftMargin: 10
          right: setPath.left; rightMargin: 8
          verticalCenter: parent.verticalCenter
        }
        text: AppearanceStore.wallpaper
        font { family: Theme.fontMono; pixelSize: 11; weight: 500 }
        color: Theme.text
        clip: true
        onAccepted: AppearanceStore.values.wallpaper = pathField.text.trim()

        Text {
          anchors.fill: parent
          verticalAlignment: Text.AlignVCenter
          visible: pathField.text === ""
          text: "/path/to/wallpaper.png"
          font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
          color: Theme.alpha(Theme.text, 0.35)
        }
      }

      Text {
        id: setPath
        anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
        text: "set"
        font { family: Theme.fontMono; pixelSize: 10; weight: 500 }
        color: Theme.accentSoft

        MouseArea {
          anchors.fill: parent
          anchors.margins: -4
          onClicked: AppearanceStore.values.wallpaper = pathField.text.trim()
        }
      }
    }
  }
}
