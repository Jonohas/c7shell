pragma ComponentBehavior: Bound
import QtQuick
import qs.Theme
import qs.Common

// 2a/2b sidebar: 212px, right hairline, search field over three labelled
// groups. Typing filters the items live and hides any group left empty.
Item {
  id: root

  // Page key of the selected item; the window loads the matching page.
  property string current: "appearance"

  property string query: ""

  // The nav is the sidebar's own business — the window only needs to know
  // which key is current. Keys match SettingsService.open(page) arguments.
  readonly property var groups: [
    {
      label: "connectivity",
      items: [
        { page: "wifi", label: "wi-fi" },
        { page: "network", label: "network & vpn" },
        { page: "bluetooth", label: "bluetooth" }
      ]
    },
    {
      label: "system",
      items: [
        { page: "appearance", label: "appearance" },
        { page: "system", label: "system" },
        { page: "displays", label: "displays" },
        { page: "audio", label: "audio" },
        { page: "power", label: "power" },
        { page: "notifications", label: "notifications" }
      ]
    },
    {
      label: "shell",
      items: [
        { page: "topbar", label: "topbar & widgets" },
        { page: "keybinds", label: "keybinds" }
      ]
    }
  ]

  function matches(label) {
    return root.query === "" || label.toLowerCase().includes(root.query.toLowerCase())
  }

  // Title for a page key, for the placeholder the phase-2 entries load.
  function labelFor(page) {
    for (const g of root.groups)
      for (const i of g.items)
        if (i.page === page) return i.label
    return page
  }

  implicitWidth: 212

  // Right hairline, drawn rather than a border so only the one edge shows.
  Rectangle {
    anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
    width: 1
    color: Theme.hairline
  }

  Column {
    anchors {
      left: parent.left; right: parent.right; top: parent.top
      leftMargin: 10; rightMargin: 10; topMargin: 12
    }
    spacing: 2

    // -- search ------------------------------------------------------------
    Rectangle {
      width: parent.width
      implicitHeight: 26
      radius: Theme.radiusChip
      color: Theme.surface05

      Icon {
        id: glass
        anchors { left: parent.left; leftMargin: 9; verticalCenter: parent.verticalCenter }
        name: "search"
        size: 11
        tint: Theme.alpha(Theme.text, 0.4)
      }

      TextInput {
        id: search

        anchors {
          left: glass.right; leftMargin: 8
          right: parent.right; rightMargin: 9
          verticalCenter: parent.verticalCenter
        }
        font { family: Theme.fontMono; pixelSize: 11; weight: 400 }
        color: Theme.text
        clip: true
        onTextChanged: root.query = text
        Keys.onEscapePressed: search.text = ""

        Text {
          anchors.fill: parent
          verticalAlignment: Text.AlignVCenter
          visible: search.text === ""
          text: "search settings"
          font { family: Theme.fontMono; pixelSize: 11; weight: 400 }
          color: Theme.alpha(Theme.text, 0.35)
        }
      }

      MouseArea {
        anchors.fill: parent
        // The field is only 26px tall; the whole pill should focus it.
        onClicked: search.forceActiveFocus()
      }
    }

    Item { width: 1; height: 6 }   // the mock's 8px gap, less the column spacing

    // -- groups ------------------------------------------------------------
    Repeater {
      // A constant array, not a rebuilt filtered one: filtering happens in the
      // delegates via `visible`.
      model: root.groups

      Column {
        id: group

        required property var modelData
        required property int index

        width: parent.width
        spacing: 2
        visible: group.modelData.items.some(i => root.matches(i.label))

        Text {
          text: group.modelData.label
          font { family: Theme.fontMono; pixelSize: 9; weight: 500 }
          color: Theme.alpha(Theme.text, 0.3)
          leftPadding: 9
          topPadding: group.index === 0 ? 4 : 10
          bottomPadding: 2
        }

        Repeater {
          model: group.modelData.items

          Rectangle {
            id: item

            required property var modelData

            readonly property bool selected: root.current === item.modelData.page

            width: group.width
            implicitHeight: 30
            radius: Theme.radiusChip
            visible: root.matches(item.modelData.label)
            color: item.selected ? Theme.accent
              : (itemMouse.containsMouse ? Theme.surface04 : "transparent")

            MouseArea {
              id: itemMouse
              anchors.fill: parent
              hoverEnabled: true
              onClicked: root.current = item.modelData.page
            }

            Text {
              anchors {
                left: parent.left; leftMargin: 9
                right: parent.right; rightMargin: 9
                verticalCenter: parent.verticalCenter
              }
              text: item.modelData.label
              font {
                family: Theme.fontMono
                pixelSize: 11
                weight: item.selected ? 600 : 500
              }
              color: item.selected ? Theme.textOnAccent : Theme.alpha(Theme.text, 0.75)
              elide: Text.ElideRight
            }
          }
        }
      }
    }
  }
}
