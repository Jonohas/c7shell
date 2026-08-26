pragma ComponentBehavior: Bound
import QtQuick
import qs.Theme
import qs.Services

// 2b: the three theme preview cards. Selecting one only writes the variant to
// the appearance store — what each variant means is Theme's business.
Row {
  id: root

  spacing: 10

  // Miniature swatches describing what a variant looks like; they belong to
  // the variant, not to the running theme, so they live here.
  //
  // `ready` is whether Theme can actually render the variant. Light needs a
  // whole second palette — text, surfaces and hairlines are all light-on-dark
  // literals — so its card is shown and disabled rather than offered and inert:
  // a control that changes nothing is worse than one that says it cannot yet.
  readonly property var variants: [
    { key: "dark", label: "dark · default", bg: "#0d0d10", ink: "#ffffff", bar: 0.12, block: 0.07, ready: true },
    { key: "oled", label: "oled black", bg: "#050506", ink: "#ffffff", bar: 0.09, block: 0.05, ready: true },
    { key: "light", label: "light · later", bg: "#e9e6e2", ink: "#000000", bar: 0.12, block: 0.07, ready: false }
  ]

  Repeater {
    model: root.variants

    Item {
      id: card

      required property var modelData

      readonly property bool selected: AppearanceStore.theme === card.modelData.key

      width: (root.width - root.spacing * 2) / 3
      implicitHeight: 82
      opacity: card.modelData.ready ? 1 : 0.45

      MouseArea {
        anchors.fill: parent
        enabled: card.modelData.ready
        onClicked: AppearanceStore.values.theme = card.modelData.key
      }

      // The preview carries the variant's own background; the label sits below
      // it on the page. Painting the variant across the whole card instead puts
      // the label's ink on the wrong ground — light's read #f0eff1 on #e9e6e2.
      Rectangle {
        id: preview
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 58
        radius: Theme.radiusPreview
        color: card.modelData.bg
        border.width: card.selected ? 2 : 1
        border.color: card.selected ? Theme.accent : Theme.hairlineStrong

        // A bar over a window, exactly as the mock draws it.
        Rectangle {
          anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
          height: 7
          radius: 4
          color: Theme.alpha(card.modelData.ink, card.modelData.bar)
        }
        Rectangle {
          anchors { left: parent.left; top: parent.top; leftMargin: 6; topMargin: 19 }
          width: parent.width * 0.4
          height: 26
          radius: 5
          color: Theme.alpha(card.modelData.ink, card.modelData.block)
        }
      }

      Text {
        anchors { left: parent.left; leftMargin: 3; top: preview.bottom; topMargin: 7 }
        text: card.modelData.label
        font { family: Theme.fontMono; pixelSize: 10; weight: card.selected ? 600 : 500 }
        color: card.selected ? Theme.text : Theme.alpha(Theme.text, 0.6)
      }
    }
  }
}
