import QtQuick
import qs.Theme
import qs.Common
import qs.Services

// Mockup 9b: the options for the active tool, and only those. It swaps in
// place above the tool bar and is not there at all for a tool with nothing to
// set -- an empty strip would be a bar that moves the tool bar down by its own
// height for no reason.
//
// Every control writes through AnnotateService.setOption, which is what makes
// this a property sheet as well as a set of defaults: change the colour with a
// rectangle selected and that rectangle changes too.
GlassPanel {
  id: strip

  readonly property string tool: AnnotateService.tool
  readonly property var opts: AnnotateService.options[strip.tool] ?? null

  visible: strip.opts !== null
  implicitWidth: row.implicitWidth + 20
  implicitHeight: strip.visible ? row.implicitHeight + 12 : 0
  radius: Theme.radiusMenu
  glassAlpha: Theme.glassAlphaPanel

  Row {
    id: row
    anchors.centerIn: parent
    spacing: 12

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: strip.tool
      font { family: Theme.fontMono; pixelSize: 10; weight: 600 }
      color: Theme.text3
    }

    Segmented {   // outline | fill
      anchors.verticalCenter: parent.verticalCenter
      visible: strip.opts?.fill !== undefined
      options: [{ value: false, label: "outline" }, { value: true, label: "fill" }]
      value: strip.opts?.fill ?? false
      onPicked: v => AnnotateService.setOption(strip.tool, "fill", v)
    }

    Field {
      // Meaningless on a filled shape, and a stroke width that changes
      // nothing on screen is a control that looks broken.
      visible: strip.opts?.stroke !== undefined && !strip.opts?.fill
      label: "stroke"
      choices: [1, 2, 3, 5, 8]
      value: strip.opts?.stroke ?? 3
      onPicked: v => AnnotateService.setOption(strip.tool, "stroke", v)
    }

    Field {
      visible: strip.opts?.radius !== undefined
      label: "corner"
      choices: [0, 4, 12]
      value: strip.opts?.radius ?? 0
      onPicked: v => AnnotateService.setOption(strip.tool, "radius", v)
    }

    Row {   // the four swatches; never a free picker
      anchors.verticalCenter: parent.verticalCenter
      visible: strip.opts?.colour !== undefined
      spacing: 5

      Repeater {
        model: Theme.swatchTokens

        Rectangle {
          required property var modelData

          readonly property bool active: strip.opts?.colour === modelData

          width: 18
          height: 18
          radius: 5
          color: Theme.swatch(modelData)
          // The dark swatch is invisible on a dark bar without one, and the
          // ring doubles as the selected state for all four.
          border.width: active ? 2 : 1
          border.color: active ? Theme.accentSoft : Theme.hairlineStrong

          MouseArea {
            anchors.fill: parent
            onClicked: AnnotateService.setOption(strip.tool, "colour", modelData)
          }
        }
      }
    }
  }

  // A labelled row of fixed choices. Discrete rather than a slider or a
  // spinbox: these are pixel counts on an image whose scale you cannot see
  // exactly, and five sensible values are quicker than any of them.
  component Field: Row {
    id: field

    property string label
    property var choices: []
    property var value
    signal picked(var value)

    anchors.verticalCenter: parent.verticalCenter
    spacing: 6

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: field.label
      font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
      color: Theme.text3
    }

    Segmented {
      anchors.verticalCenter: parent.verticalCenter
      options: field.choices.map(c => ({ value: c, label: String(c) }))
      value: field.value
      onPicked: v => field.picked(v)
    }
  }
}
