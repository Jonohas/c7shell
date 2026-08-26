import QtQuick
import qs.Theme

// "other networks", "nearby", "devices", "apps" — the 9.5px .35 label that
// separates the sections of a popover. pixelSize is an int, so 9.5 rounds up.
Text {
  font { family: Theme.fontMono; pixelSize: 10; weight: 500 }
  color: Theme.alpha(Theme.text, 0.35)
  leftPadding: 2
}
