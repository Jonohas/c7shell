//@ pragma UseQApplication
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects

// 8a screenshare picker. Runs as its own qs instance (see
// bin/screenshare-picker.sh); writes "[SELECTION]/..." to $XDPH_OUT and
// quits. Cancel = quit without writing.
// ponytail: screens + windows only; region needs a drag overlay — the
// region:OUT@x,y,w,h protocol is ready whenever it is worth building.
ShellRoot {
  id: root

  property string tab: "screens"
  property int selScreen: -1
  property string selWindow: ""
  property string selWindowLabel: ""

  // "{handle}[HC>]{class}[HT>]{title}[HE>]{addr}[HA>]" repeated.
  readonly property var windows: {
    const s = Quickshell.env("XDPH_WINDOW_SHARING_LIST") ?? ""
    const out = []
    const re = /(\d+)\[HC>\](.*?)\[HT>\](.*?)\[HE>\](.*?)\[HA>\]/g
    let m
    while ((m = re.exec(s)) !== null)
      out.push({ handle: m[1], cls: m[2], title: m[3] })
    return out
  }

  function confirm() {
    let sel = ""
    if (root.tab === "screens" && root.selScreen >= 0)
      sel = `[SELECTION]/screen:${Quickshell.screens[root.selScreen].name}`
    else if (root.tab === "windows" && root.selWindow !== "")
      sel = `[SELECTION]/window:${root.selWindow}`
    if (sel === "") return
    // argv keeps the shell out of the selection string; $XDPH_OUT is the
    // wrapper's tempfile.
    writeProc.exec(["sh", "-c", 'printf "%s" "$1" > "$XDPH_OUT"', "sh", sel])
  }

  Process {
    id: writeProc
    onExited: Qt.quit()
  }

  PanelWindow {
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "c7shell-sharepicker"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    color: Qt.rgba(4/255, 4/255, 6/255, 0.6)

    MouseArea { anchors.fill: parent; onClicked: Qt.quit() }   // click-away cancels

    Rectangle {   // the dialog; blur handled by hypr layer rules (alpha ≥ .7)
      id: dialog
      anchors.centerIn: parent
      width: 560
      height: 420
      radius: 20
      color: Qt.rgba(15/255, 15/255, 19/255, 0.80)
      border.width: 1
      border.color: Qt.rgba(1, 1, 1, 0.08)
      MouseArea { anchors.fill: parent }   // swallow clicks inside

      Column {
        anchors { fill: parent; margins: 16 }
        spacing: 12

        Text {
          text: "share your screen"
          font { family: "JetBrains Mono"; pixelSize: 13; weight: 600 }
          color: "#f0eff1"
        }

        Row {   // screens / windows segmented tabs
          spacing: 6
          Repeater {
            model: ["screens", "windows"]
            Rectangle {
              required property string modelData
              width: tabLabel.implicitWidth + 20; height: 24; radius: 9
              color: root.tab === modelData ? "#e53a44" : Qt.rgba(1, 1, 1, 0.05)
              Text {
                id: tabLabel
                anchors.centerIn: parent
                text: parent.modelData
                font { family: "JetBrains Mono"; pixelSize: 10; weight: 600 }
                color: root.tab === parent.modelData ? "#ffffff" : Qt.rgba(240/255, 239/255, 241/255, 0.55)
              }
              MouseArea { anchors.fill: parent; onClicked: root.tab = parent.modelData }
            }
          }
        }

        Flickable {
          width: parent.width
          height: 280
          contentHeight: root.tab === "screens" ? screenFlow.implicitHeight : windowCol.implicitHeight
          clip: true

          Flow {   // monitor cards with live thumbnails
            id: screenFlow
            visible: root.tab === "screens"
            width: parent.width
            spacing: 10
            Repeater {
              model: Quickshell.screens
              Rectangle {
                required property var modelData
                required property int index
                width: 254; height: 170; radius: 13
                color: Qt.rgba(1, 1, 1, 0.04)
                border.width: 2
                border.color: root.selScreen === index ? "#e53a44" : Qt.rgba(1, 1, 1, 0.08)

                Column {
                  anchors { fill: parent; margins: 8 }
                  spacing: 6
                  ScreencopyView {
                    width: parent.width; height: 128
                    captureSource: parent.parent.modelData
                    live: true
                  }
                  Text {
                    text: `${parent.parent.modelData.name} · ${parent.parent.modelData.width}×${parent.parent.modelData.height}`
                    font { family: "JetBrains Mono"; pixelSize: 10; weight: 500 }
                    color: Qt.rgba(240/255, 239/255, 241/255, 0.55)
                  }
                }
                Text {   // crimson check on the selected card
                  visible: root.selScreen === parent.index
                  anchors { top: parent.top; right: parent.right; margins: 8 }
                  text: "✓"
                  font { family: "JetBrains Mono"; pixelSize: 12; weight: 700 }
                  color: "#e53a44"
                }
                MouseArea { anchors.fill: parent; onClicked: root.selScreen = parent.index }
              }
            }
          }

          Column {   // window rows: monogram + class + title
            id: windowCol
            visible: root.tab === "windows"
            width: parent.width
            spacing: 6
            Repeater {
              model: root.windows
              Rectangle {
                required property var modelData
                width: parent.width; height: 40; radius: 10
                color: root.selWindow === modelData.handle
                  ? Qt.rgba(229/255, 58/255, 68/255, 0.14) : Qt.rgba(1, 1, 1, 0.04)
                border.width: 1
                border.color: root.selWindow === modelData.handle
                  ? Qt.rgba(229/255, 58/255, 68/255, 0.30) : Qt.rgba(1, 1, 1, 0.07)
                Column {
                  anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                  spacing: 2
                  Text {
                    text: parent.parent.modelData.cls
                    font { family: "JetBrains Mono"; pixelSize: 11; weight: 600 }
                    color: "#f0eff1"
                  }
                  Text {
                    text: parent.parent.modelData.title
                    width: dialog.width - 64
                    elide: Text.ElideRight
                    font { family: "JetBrains Mono"; pixelSize: 9; weight: 400 }
                    color: Qt.rgba(240/255, 239/255, 241/255, 0.55)
                  }
                }
                MouseArea {
                  anchors.fill: parent
                  onClicked: {
                    root.selWindow = parent.modelData.handle
                    root.selWindowLabel = parent.modelData.cls
                  }
                }
              }
            }
          }
        }

        Row {   // footer: cancel / share →
          anchors.right: parent.right
          spacing: 8
          Rectangle {
            width: cancelLabel.implicitWidth + 24; height: 28; radius: 9
            color: Qt.rgba(1, 1, 1, 0.05)
            Text {
              id: cancelLabel
              anchors.centerIn: parent; text: "cancel"
              font { family: "JetBrains Mono"; pixelSize: 10; weight: 600 }
              color: Qt.rgba(240/255, 239/255, 241/255, 0.55)
            }
            MouseArea { anchors.fill: parent; onClicked: Qt.quit() }
          }
          Rectangle {
            readonly property bool ready:
              (root.tab === "screens" && root.selScreen >= 0)
              || (root.tab === "windows" && root.selWindow !== "")
            width: shareLabel.implicitWidth + 24; height: 28; radius: 9
            color: "#e53a44"
            opacity: ready ? 1 : 0.35
            Text {
              id: shareLabel
              anchors.centerIn: parent
              text: root.tab === "screens" && root.selScreen >= 0
                ? `share ${Quickshell.screens[root.selScreen].name} →`
                : root.selWindow !== "" ? `share ${root.selWindowLabel} →` : "share →"
              font { family: "JetBrains Mono"; pixelSize: 10; weight: 700 }
              color: "#ffffff"
            }
            MouseArea { anchors.fill: parent; enabled: parent.ready; onClicked: root.confirm() }
          }
        }
      }
    }

    Shortcut { sequence: "Escape"; onActivated: Qt.quit() }
    Shortcut { sequence: "Return"; onActivated: root.confirm() }
  }
}
