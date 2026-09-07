import QtQuick
import "Hex.js" as Hex

// The full hue sweep, left to right. Two surfaces draw it -- AccentPicker's
// strip and the accent row's last swatch -- and they have to agree, because
// they are the same control in two sizes.
//
// Seven computed stops rather than a list of literals: the six sextant corners
// plus the wrap back to red, each from the same maths that turns the picker's
// position into the hex it writes. Qt interpolates in between, which is why 60
// degrees of hue between neighbours is enough.
Gradient {
  orientation: Gradient.Horizontal

  GradientStop { position: 0 / 6; color: Hex.fromHsv(0, 1, 1) }
  GradientStop { position: 1 / 6; color: Hex.fromHsv(60, 1, 1) }
  GradientStop { position: 2 / 6; color: Hex.fromHsv(120, 1, 1) }
  GradientStop { position: 3 / 6; color: Hex.fromHsv(180, 1, 1) }
  GradientStop { position: 4 / 6; color: Hex.fromHsv(240, 1, 1) }
  GradientStop { position: 5 / 6; color: Hex.fromHsv(300, 1, 1) }
  GradientStop { position: 6 / 6; color: Hex.fromHsv(360, 1, 1) }
}
