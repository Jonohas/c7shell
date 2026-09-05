import QtQuick
import Quickshell.Networking
import qs.Theme
import qs.Services

// The password row a secured network grows underneath itself, rather than
// opening a second popup that the popover's own focus grab would dismiss.
// Owns the whole ask-for-a-key state machine -- the popover and the settings
// page each had their own copy, and only one of them ever asked.
//
// The caller shows the row's normal click as: asking ? focusInput() : ask().
Rectangle {
  id: root

  required property var network
  property int padH: 10

  // Grown, not just focused: `asking` is what makes the row visible.
  property bool asking: false
  property string error: ""

  // Enterprise and WEP cannot be joined from a single field, so the row says so
  // instead of pretending to ask.
  readonly property bool capable: NetworkService.pskCapable(root.network)

  function ask() {
    root.error = root.capable ? "" : "needs a full network manager"
    root.asking = true
    // Grown before focused. Measured on this Qt, forceActiveFocus() lands even
    // from inside a hidden subtree, so the old order worked by luck -- this one
    // does not depend on that.
    input.forceActiveFocus()
  }

  function focusInput() { input.forceActiveFocus() }

  function collapse() {
    // Hand focus back to something that is still visible, or the panel above
    // never gets it back and esc stops closing the popup. The row is inside the
    // panel, so keys bubble up to it from there.
    if (input.activeFocus && root.parent) root.parent.forceActiveFocus()
    root.asking = false
    root.error = ""
    input.text = ""
  }

  // -- keeping the row alive long enough to type into ----------------------
  // The scan list re-sorts on every signal-strength update NetworkManager
  // pushes, and a Repeater rebuilds every delegate when its model array
  // changes -- taking this field, its text and its focus with it. So a row
  // that is asking freezes the list until it stops asking. Hung off `asking`
  // rather than ask(), because onConnectionFailed re-asks without going
  // through it.
  onAskingChanged: {
    if (!root.asking) {
      root.releaseList()
      return
    }
    root.claimed = root.network?.name ?? ""
    NetworkService.pskTarget = root.claimed
  }

  // Remembered rather than read back off the network: a row can be torn down
  // with `network` already null, and reading it then would leave the list
  // frozen with nothing left able to unfreeze it.
  property string claimed: ""

  // Guarded on the freeze still being ours, so a row torn down after another
  // has claimed it does not unfreeze that one.
  function releaseList() {
    if (root.claimed !== "" && NetworkService.pskTarget === root.claimed)
      NetworkService.pskTarget = ""
    root.claimed = ""
  }

  Component.onDestruction: root.releaseList()

  visible: root.asking
  implicitHeight: 28
  radius: Theme.radiusTile
  color: Theme.surface04

  Connections {
    target: root.network

    function onConnectionFailed(reason) {
      if (reason !== ConnectionFailReason.NoSecrets) return
      if (!root.capable) {
        root.error = "needs a full network manager"
        root.asking = true
        return
      }
      // Read before it is written: already asking means the key that was typed
      // is the wrong one.
      root.error = root.asking ? "wrong password" : ""
      root.asking = true
      input.forceActiveFocus()
    }

    function onConnectedChanged() {
      if (root.network.connected) root.collapse()
    }
  }

  Text {
    visible: !root.capable
    anchors { fill: parent; leftMargin: root.padH }
    verticalAlignment: Text.AlignVCenter
    text: root.error
    font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
    color: Theme.accentSoft
  }

  TextInput {
    id: input

    visible: root.capable
    anchors {
      left: parent.left; leftMargin: root.padH
      right: join.left; rightMargin: 8
      verticalCenter: parent.verticalCenter
    }

    echoMode: TextInput.Password
    font { family: Theme.fontMono; pixelSize: 11; weight: 500 }
    color: Theme.text
    clip: true
    // Enter is the only thing that talks to NetworkManager here.
    onAccepted: NetworkService.connectWithPsk(root.network, text)
    // Accepted, so esc closes the field rather than the whole popover.
    Keys.onEscapePressed: event => {
      root.collapse()
      event.accepted = true
    }

    Text {
      anchors.fill: parent
      verticalAlignment: Text.AlignVCenter
      visible: input.text === ""
      text: root.error !== "" ? root.error : "password"
      font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
      color: root.error !== "" ? Theme.accentSoft : Theme.alpha(Theme.text, 0.35)
    }
  }

  Text {
    id: join
    visible: root.capable
    anchors { right: parent.right; rightMargin: root.padH; verticalCenter: parent.verticalCenter }
    text: "join"
    font { family: Theme.fontMono; pixelSize: 10; weight: 500 }
    color: Theme.accentSoft

    MouseArea {
      anchors.fill: parent
      anchors.margins: -4
      onClicked: NetworkService.connectWithPsk(root.network, input.text)
    }
  }
}
