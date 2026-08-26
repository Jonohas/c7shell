import QtQuick
import qs.Theme

// The month card from 1d. Six fixed rows so the panel does not change height
// when you page through months.
Rectangle {
  id: root

  property date today: new Date()
  // Set imperatively, never bound: `today` ticks, and a binding would snap the
  // view back to this month while you are paging through next year.
  property int viewYear: 0
  property int viewMonth: 0                              // 0-11

  Component.onCompleted: root.toToday()

  // Weeks start on Monday, Date.getDay() starts on Sunday.
  readonly property int lead: (new Date(root.viewYear, root.viewMonth, 1).getDay() + 6) % 7

  // Month arithmetic goes through Date rather than modular arithmetic on the
  // month number: `new Date(2026, 12, 1)` is January 2027, so December → next
  // and January → previous cross the year on their own.
  function step(delta) {
    const d = new Date(root.viewYear, root.viewMonth + delta, 1)
    root.viewYear = d.getFullYear()
    root.viewMonth = d.getMonth()
  }

  function toToday() {
    root.viewYear = root.today.getFullYear()
    root.viewMonth = root.today.getMonth()
  }

  implicitHeight: content.implicitHeight + 24
  radius: Theme.radiusCard
  color: Theme.surface04
  border.width: 1
  border.color: Theme.hairline

  Column {
    id: content
    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
    spacing: 0

    Item {
      width: parent.width
      implicitHeight: 20

      Text {
        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
        text: Qt.formatDate(new Date(root.viewYear, root.viewMonth, 1), "MMMM yyyy").toLowerCase()
        font { family: Theme.fontMono; pixelSize: 11; weight: 600 }
        color: Theme.text
      }

      Row {
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        spacing: 10

        Nav { glyph: "‹"; onTapped: root.step(-1) }
        Nav { glyph: "›"; onTapped: root.step(1) }
      }
    }

    Item { width: 1; height: 9 }

    Grid {
      width: parent.width
      columns: 7
      spacing: 1

      Repeater {
        model: ["mo", "tu", "we", "th", "fr", "sa", "su"]

        Text {
          required property var modelData
          required property int index

          width: (content.width - 6) / 7
          height: 20
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          text: modelData
          font { family: Theme.fontMono; pixelSize: 10; weight: 500 }
          color: index >= 5 ? Theme.alpha(Theme.accentSoft, 0.5) : Theme.alpha(Theme.text, 0.35)
        }
      }

      Repeater {
        model: 42

        Rectangle {
          id: cell

          required property int index

          readonly property date cellDate: new Date(root.viewYear, root.viewMonth, 1 - root.lead + cell.index)
          readonly property bool inMonth: cell.cellDate.getMonth() === root.viewMonth
          readonly property bool isToday: cell.cellDate.getFullYear() === root.today.getFullYear()
            && cell.cellDate.getMonth() === root.today.getMonth()
            && cell.cellDate.getDate() === root.today.getDate()

          width: (content.width - 6) / 7
          height: 24
          radius: 8
          color: cell.isToday ? Theme.accent : "transparent"

          Text {
            anchors.centerIn: parent
            text: cell.cellDate.getDate()
            font {
              family: Theme.fontMono
              pixelSize: 11
              weight: cell.isToday ? 700 : 500
            }
            color: cell.isToday ? Theme.textOnAccent : Theme.text
            opacity: cell.isToday ? 1 : (cell.inMonth ? 0.75 : 0.25)
          }
        }
      }
    }
  }

  component Nav: Text {
    id: nav

    property string glyph
    signal tapped()

    text: nav.glyph
    font { family: Theme.fontMono; pixelSize: 11; weight: 500 }
    color: navMouse.containsMouse ? Theme.text : Theme.alpha(Theme.text, 0.4)

    MouseArea {
      id: navMouse
      anchors.fill: parent
      anchors.margins: -5
      hoverEnabled: true
      onClicked: nav.tapped()
    }
  }
}
