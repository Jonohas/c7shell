import QtQuick
import "../sddm/themes/c7shell" as C7

// Render the sddm greeter theme without a display manager:
//
//   qml6 tests/greeter-preview.qml
//   qml6 tests/greeter-preview.qml -- --failed      # the failed-auth state
//   qml6 tests/greeter-preview.qml -- --one-user    # single account, no list
//
// sddm hands the theme its models as context properties, which no QML file can
// create -- so Greeter.qml takes them as plain properties and this harness
// fills them with ListModels shaped like sddm's. tests/test-greeter.sh runs
// this offscreen and fails on any QML warning.
Window {
  id: window

  // --typed <n>: put n characters in the password field, since nothing here can
  // type. The dot row and the caret are drawn from the length, and their
  // alignment is the whole point of looking.
  readonly property int typed: window.argAfter("--typed", 0)

  // --size WxH for a real panel size; the mockup's own frame by default.
  width: window.argSize(0, 1120)
  height: window.argSize(1, 630)
  visible: true
  title: "c7shell greeter preview"
  color: "#08080a"

  readonly property var flags: Qt.application.arguments
  readonly property bool oneUser: window.flags.indexOf("--one-user") >= 0
  readonly property bool failed: window.flags.indexOf("--failed") >= 0
  readonly property bool manual: window.flags.indexOf("--manual") >= 0
  readonly property bool sessionsOpen: window.flags.indexOf("--sessions") >= 0
  readonly property bool caps: window.flags.indexOf("--caps") >= 0

  // userModel: name, realName, icon
  ListModel {
    id: userRows
    ListElement { name: "alex"; realName: "Alex Mertens"; icon: "" }
    ListElement { name: "robin"; realName: "Robin Vermeulen"; icon: "" }
  }
  ListModel {
    id: oneUserRow
    ListElement { name: "alex"; realName: "Alex Mertens"; icon: "" }
  }

  // sessionModel: name, comment
  ListModel {
    id: sessionRows
    ListElement { name: "c7shell"; comment: "Hyprland with the c7shell Quickshell shell" }
    ListElement { name: "Hyprland"; comment: "An intelligent dynamic tiling compositor" }
    ListElement { name: "GNOME"; comment: "wayland · fallback" }
  }

  // keyboard.layouts: a plain list of objects with shortName/longName
  QtObject {
    id: usLayout
    property string shortName: "us"
    property string longName: "English (US)"
  }
  QtObject {
    id: beLayout
    property string shortName: "be"
    property string longName: "Belgian"
  }

  C7.Greeter {
    id: greeter
    anchors.fill: parent
    focus: true

    hostName: "c7-fw16"
    users: window.oneUser ? oneUserRow : userRows
    sessions: sessionRows
    layouts: [usLayout, beLayout]
    currentLayout: 0
    capsLock: window.caps
    allowManualLogin: window.manual
    // --network-file <path> stands in for the dispatcher script's output.
    networkFile: window.argString("--network-file")

    onLoginRequested: function (user, password, sessionIndex) {
      console.log("login:", user, "session", sessionIndex, "password length", password.length)
      // Everything but "hunter2" fails, so the failure states can be walked
      // through by hand.
      if (password === "hunter2") greeter.loginSucceeded()
      else greeter.loginFailed("")
    }
    onLayoutRequested: function (index) { greeter.currentLayout = index }
    onSuspendRequested: console.log("suspend")
    onRebootRequested: console.log("reboot")
    onPowerOffRequested: console.log("power off")

    Component.onCompleted: {
      if (window.manual) greeter.userIndex = greeter.userCount
      if (window.sessionsOpen) greeter.sessionsOpen = true
      if (window.typed > 0) greeter.password = "x".repeat(window.typed)
      if (window.failed) {
        greeter.loginFailed("")
        greeter.loginFailed("")
      }
    }
  }

  // --exit-after <ms>, and --shot <path> to write a PNG of the frame first:
  // between them, the greeter can be rendered and looked at from a terminal.
  Timer {
    property int ms: window.argAfter("--exit-after", 0)
    interval: ms
    running: ms > 0
    onTriggered: {
      const path = window.argString("--shot")
      if (path !== "") {
        greeter.grabToImage(function (result) {
          if (!result.saveToFile(path)) console.warn("could not write", path)
          Qt.exit(0)
        })
      } else {
        Qt.exit(0)
      }
    }
  }

  // "--size 1920x1080" -> [1920, 1080]
  function argSize(axis, fallback) {
    const parts = window.argString("--size").split("x")
    const v = parseInt(parts[axis], 10)
    return isNaN(v) ? fallback : v
  }
  function argString(flag) {
    const i = window.flags.indexOf(flag)
    return i >= 0 && i + 1 < window.flags.length ? window.flags[i + 1] : ""
  }
  function argAfter(flag, fallback) {
    const v = parseInt(window.argString(flag), 10)
    return isNaN(v) ? fallback : v
  }
}
