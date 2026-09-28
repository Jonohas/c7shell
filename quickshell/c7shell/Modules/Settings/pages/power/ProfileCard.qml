pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import qs.Theme
import qs.Common
import qs.Services
import qs.Modules.Settings

// One of the three tuned profiles, as a card: the name, what it costs, and
// this machine's own runtime estimate under it. The estimate is the point --
// the trade-off between the profiles is not something the labels describe, it
// is the numbers beside them.
Rectangle {
  id: pcard

  required property var profile

  readonly property bool applying: TunedService.applying === pcard.profile.key
  readonly property bool current: TunedService.applying !== ""
    ? pcard.applying : TunedService.activeKey === pcard.profile.key

  implicitHeight: pbody.implicitHeight + 28
  radius: Theme.radiusCard
  color: pcard.current ? Theme.accentFill : Theme.surface04
  border.width: 1
  border.color: pcard.current ? Theme.accentBorder : Theme.hairline
  opacity: TunedService.applying !== "" && !pcard.applying ? 0.45 : 1

  Behavior on color { ColorAnimation { duration: 120 } }
  Behavior on opacity { NumberAnimation { duration: 120 } }

  // The active card's `0 0 24px` glow. RectangularShadow rather than
  // MultiEffect for the same reason CrimsonSlider uses it: MultiEffect would
  // repaint the card on top of itself.
  RectangularShadow {
    anchors.fill: parent
    radius: parent.radius
    color: Theme.alpha(Theme.accent, 0.14)
    blur: 24
    visible: pcard.current
    z: -1
  }

  MouseArea {
    anchors.fill: parent
    // A card click is the user watching it happen; no toast.
    onClicked: TunedService.apply(pcard.profile.key, false)
  }

  Column {
    id: pbody

    anchors {
      left: parent.left; right: parent.right; top: parent.top
      leftMargin: 14; rightMargin: 14; topMargin: 14
    }
    spacing: 9

    Item {
      width: parent.width
      implicitHeight: 30

      Rectangle {
        id: ptile

        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
        width: 30
        height: 30
        radius: Theme.radiusChip
        color: pcard.current ? Theme.alpha(Theme.accent, 0.18) : Theme.surface05
        border.width: 1
        border.color: pcard.current ? Theme.alpha(Theme.accent, 0.35) : Theme.hairline

        Icon {
          anchors.centerIn: parent
          name: pcard.profile.icon
          size: 15
          tint: pcard.current ? Theme.accentSoft : Theme.text2
        }
      }

      Column {
        anchors {
          left: ptile.right; leftMargin: 9
          right: pbadge.left; rightMargin: 6
          verticalCenter: parent.verticalCenter
        }
        spacing: 1

        Text {
          width: parent.width
          text: pcard.profile.label
          font { family: Theme.fontMono; pixelSize: 11; weight: 600 }
          color: pcard.current ? Theme.text : Theme.alpha(Theme.text, 0.8)
          elide: Text.ElideRight
        }
        Text {
          width: parent.width
          // The tuned name is on the card because the mapping is the thing a
          // user with hand-written profiles came here to check.
          text: `tuned: ${pcard.profile.tuned}`
          font { family: Theme.fontMono; pixelSize: 9; weight: 400 }
          color: Theme.alpha(Theme.text, pcard.current ? 0.4 : 0.35)
          elide: Text.ElideRight
        }
      }

      Item {
        id: pbadge

        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        width: pcard.applying ? 12 : (pcard.current ? activeBadge.implicitWidth : 0)
        height: 14

        Spinner {
          anchors.centerIn: parent
          size: 11
          visible: pcard.applying
          arcColor: Theme.alpha(Theme.accent, 0.85)
        }

        Rectangle {
          id: activeBadge

          anchors.centerIn: parent
          visible: pcard.current && !pcard.applying
          implicitWidth: activeText.implicitWidth + 14
          implicitHeight: 14
          radius: 5
          color: Theme.accent

          Text {
            id: activeText
            anchors.centerIn: parent
            text: "ACTIVE"
            font { family: Theme.fontMono; pixelSize: 8; weight: 600; letterSpacing: 0.4 }
            color: Theme.textOnAccent
          }
        }
      }
    }

    Text {
      width: parent.width
      text: pcard.profile.blurb
      font { family: Theme.fontMono; pixelSize: 9; weight: 400 }
      lineHeight: 1.7
      wrapMode: Text.WordWrap
      color: Theme.alpha(Theme.text, pcard.current ? 0.55 : 0.45)
    }

    Item {
      width: parent.width
      implicitHeight: pstats.implicitHeight + 9

      Rectangle {
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 1
        color: pcard.current ? Theme.alpha(Theme.accent, 0.2) : Theme.alpha(Theme.text, 0.06)
      }

      Column {
        id: pstats
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        spacing: 4

        CardStat {
          width: parent.width
          highlighted: pcard.current
          key: "idle draw"
          // Measured on this machine, never hard-coded: a 14 W
          // "performance" printed on a fanless tablet is the UI lying about
          // the hardware it is running on.
          value: TunedService.idleDrawText(pcard.profile.key)
        }
        CardStat {
          width: parent.width
          highlighted: pcard.current
          key: "boost"
          value: pcard.profile.boost
        }
      }
    }
  }

  component CardStat: Item {
    id: stat

    required property string key
    required property string value
    property bool highlighted: false

    implicitHeight: 13

    Text {
      anchors { left: parent.left; verticalCenter: parent.verticalCenter }
      text: stat.key
      font { family: Theme.fontMono; pixelSize: 9; weight: 400 }
      color: Theme.alpha(Theme.text, stat.highlighted ? 0.45 : 0.4)
    }
    Text {
      anchors { right: parent.right; verticalCenter: parent.verticalCenter }
      text: stat.value
      font { family: Theme.fontMono; pixelSize: 9; weight: 400 }
      color: stat.highlighted ? Theme.text : Theme.alpha(Theme.text, 0.65)
      elide: Text.ElideRight
    }
  }
}
