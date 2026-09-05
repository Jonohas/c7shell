import QtQuick
import qs.Theme

// The bordered action chip: "remove them", "take new", "⟳ rescan", "pair",
// "forget". Three near-verbatim copies of this existed -- OrphanCard's and
// PacnewRow's private `Choice`s and Modules/Settings/ActionChip -- differing
// only in which colour meant "this is the one to press" (#89).
//
// Three emphasis levels, and they are the whole API:
//   plain           a secondary answer -- "keep them", "keep mine", "merge…"
//   highlight       the recommended answer, in `highlightColor`
//   accented        the row's primary action, crimson
// `accented` wins over `highlight`; setting both is the caller's mistake.
//
// The numbers below are the shell's chip metrics (Common/KbdChip, the picker
// chips in Common/Segmented), not this component's own invention: pixelSize 10
// at weight 500, a transparent rest fill so the chip reads as an outline until
// it is under the pointer, and Theme.radiusChip.
Rectangle {
  id: root

  property string text: ""
  property bool highlight: false
  property bool accented: false
  // What "recommended" is coloured in. Neutral by default; PacnewRow's amber
  // is the one caller that means something else by it.
  property color highlightColor: Theme.text
  property color highlightBorder: Theme.hairlineStrong

  signal triggered()

  readonly property bool _lit: root.accented || root.highlight

  implicitWidth: label.implicitWidth + 20
  implicitHeight: 20
  radius: Theme.radiusChip

  // Hover is the only fill: a resting chip is its border and its label. The
  // guard is not redundant with `enabled` -- a HoverHandler on a disabled item
  // stops updating `hovered` but keeps whatever value it last had, so a chip
  // disabled while the pointer is over it would stay lit.
  color: hover.hovered && root.enabled
    ? (root.accented ? Theme.accentFillSoft : Theme.surface07)
    : "transparent"
  border.width: 1
  border.color: root.accented ? Theme.accentBorder
    : (root.highlight ? root.highlightBorder : Theme.hairlineStrong)
  // Dead rather than pretending otherwise, at the same 0.4 as Common/TogglePill
  // and Common/Segmented.
  opacity: root.enabled ? 1 : 0.4

  Text {
    id: label
    anchors.centerIn: parent
    text: root.text
    font { family: Theme.fontMono; pixelSize: 10; weight: 500 }
    color: root.accented ? Theme.accentSoft
      : (root.highlight ? root.highlightColor : Theme.text2)
  }

  HoverHandler {
    id: hover
    enabled: root.enabled
    cursorShape: Qt.PointingHandCursor
  }
  TapHandler {
    enabled: root.enabled
    onTapped: root.triggered()
  }
}
