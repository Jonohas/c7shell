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
        anchors { right: fromWallpaper.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
        spacing: 8

        Repeater {
          model: AppearanceStore.accentChoices

          Rectangle {
            id: swatch

            required property string modelData

            // Compared as colors, not strings: "#E53A44" from a hand-edit is
            // the same accent as "#e53a44".
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
              onClicked: AppearanceStore.values.accent = swatch.modelData
            }
          }
        }
      }

      Row {
        id: fromWallpaper
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        spacing: 8

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "from wallpaper"
          font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
          color: Theme.alpha(Theme.text, 0.4)
        }
        TogglePill {
          anchors.verticalCenter: parent.verticalCenter
          checked: AppearanceStore.fromWallpaper
          // Spec §11: the toggle persists, the extraction itself lands later.
          onToggled: AppearanceStore.values.fromWallpaper = !AppearanceStore.fromWallpaper
        }
      }
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
        text: "browse →"
        font { family: Theme.fontMono; pixelSize: 10; weight: 500 }
        color: Theme.accentSoft

        MouseArea {
          anchors.fill: parent
          anchors.margins: -4
          // No GUI file picker in phase 1 — the field below is the picker.
          onClicked: pathField.forceActiveFocus()
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
