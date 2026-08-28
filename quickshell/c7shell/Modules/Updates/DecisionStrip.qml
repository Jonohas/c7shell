pragma ComponentBehavior: Bound
import QtQuick
import qs.Theme
import qs.Services

// What the dropdown says instead of "nothing needs a decision": a crimson
// panel naming exactly what escalated the run, one line each.
//
// It names them rather than counting them because the count alone ("3 things
// need a decision") is what sends people to a terminal to find out which.
Rectangle {
  id: root

  required property var decisions

  implicitWidth: parent ? parent.width : 300
  implicitHeight: body.implicitHeight + 18
  radius: Theme.radiusRow
  color: Theme.accentFill
  border.width: 1
  border.color: Theme.accentBorder

  Column {
    id: body
    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 9 }
    spacing: 6

    Text {
      text: root.decisions.length === 1
        ? "1 thing needs a decision"
        : `${root.decisions.length} things need a decision`
      font { family: Theme.fontMono; pixelSize: 11; weight: 600 }
      color: Theme.accentSoft
    }

    Repeater {
      model: root.decisions

      Row {
        id: line
        required property var modelData
        width: parent.width
        spacing: 5

        Text {
          text: line.modelData.kind
          font { family: Theme.fontMono; pixelSize: 10; weight: 500 }
          color: Theme.alpha(Theme.accentSoft, 0.75)
        }
        Text {
          text: "·"
          font { family: Theme.fontMono; pixelSize: 10 }
          color: Theme.text3
        }
        Text {
          width: parent.width - x
          elide: Text.ElideRight
          text: line.modelData.detail && line.modelData.detail !== ""
            ? `${line.modelData.title} · ${line.modelData.detail.split("\n")[0]}`
            : line.modelData.title
          font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
          color: Theme.text2
        }
      }
    }
  }
}
