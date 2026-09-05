pragma Singleton
import QtQuick

// GENERATED from quickshell/c7shell/palette.json by tools/gen-palette-qml.py -- do not edit.
// Regenerate after changing the palette; tests/test-greeter.sh fails on a
// copy that has fallen behind.
QtObject {
  readonly property var palette: ({
      "variants": {
        "dark": {
          "bg": "#0a0a0c",
          "canvas": "#0f0e10",
          "glassBase": "#0f0f13"
        },
        "oled": {
          "bg": "#000000",
          "canvas": "#050506",
          "glassBase": "#000000"
        }
      },
      "text": "#f0eff1",
      "textOnAccent": "#ffffff",
      "success": "#4ade80",
      "warning": "#e0b341",
      "negative": "#ff7a6b",
      "neutral": "#f0a44a",
      "greeterBg": "#08080a",
      "accentChoices": [
        "#e53a44",
        "#e24947",
        "#9964e5",
        "#1692c0",
        "#00a149"
      ],
      "borderChoices": [
        "#2a2a2e",
        "#595959",
        "#8b8b93",
        "#e53a44"
      ],
      "previews": [
        {
          "key": "dark",
          "label": "dark · default",
          "bg": "#0d0d10",
          "ink": "#ffffff",
          "bar": 0.12,
          "block": 0.07,
          "ready": true
        },
        {
          "key": "oled",
          "label": "oled black",
          "bg": "#050506",
          "ink": "#ffffff",
          "bar": 0.09,
          "block": 0.05,
          "ready": true
        },
        {
          "key": "light",
          "label": "light · later",
          "bg": "#e9e6e2",
          "ink": "#000000",
          "bar": 0.12,
          "block": 0.07,
          "ready": false
        }
      ]
    })
  readonly property var defaults: ({
      "theme": "dark",
      "colorScheme": "dark",
      "accent": "#e53a44",
      "rounding": 19,
      "gapsIn": 3,
      "gapsOut": 12,
      "blurSize": 8,
      "blurPasses": 3,
      "inactiveOpacity": 1.0,
      "borderWidth": 2,
      "inactiveBorder": "#595959",
      "barMarginTop": 10,
      "barMarginSide": 12,
      "animationsEnabled": true,
      "animationSpeed": 1.0,
      "wallpaper": "",
      "cursorTheme": "Adwaita",
      "cursorSize": 24
    })
}
