pragma Singleton
import Quickshell
import QtQuick

Singleton {
  readonly property var now: clock.date
  readonly property string dateLine: Qt.formatDateTime(clock.date, "ddd MMM d").toLowerCase()
  readonly property string hm: Qt.formatDateTime(clock.date, "HH:mm")

  SystemClock { id: clock; precision: SystemClock.Minutes }
}
