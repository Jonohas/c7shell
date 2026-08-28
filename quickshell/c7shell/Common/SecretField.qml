import QtQuick
import qs.Theme

// The one field every password prompt types into (14a/14b). The four looks the
// design draws are not four components -- they are this one, told which of them
// it is in:
//
//   input     42px, crimson border, focus ring          ask
//   error     no ring, heavier border, message + n of 3 wrong
//   locked    a fixed dot row, nothing accepts keys     verifying
//   waiting   dashed, no field at all                   alternate factor
//
// `compact` is the 38px variant the keyring, wifi and sudo prompts use.
Rectangle {
  id: root

  property bool compact: false
  property bool locked: false
  property bool waiting: false
  // Shown in place of the placeholder while the field is empty, so the first
  // keystroke replaces it -- the same rule PskField follows for the wi-fi row.
  property string error: ""
  property string counter: ""
  property string placeholder: "password"
  // The wifi variant reveals its key: a network key is not a personal secret
  // and is routinely read off a card. Nothing else offers this.
  property bool revealable: false
  property bool revealed: false

  property alias text: input.text

  signal accepted(string secret)
  signal cancelled

  function focusInput() { input.forceActiveFocus() }
  function clear() { input.text = "" }

  readonly property bool failed: root.error !== ""

  // For the test that pins the rule above: how many dots are actually on
  // screen, which must not vary with what was typed.
  readonly property int shownDots: dotRow.visible ? dots.count : 0

  implicitHeight: root.compact ? 38 : 42
  radius: root.compact ? 11 : 12

  color: root.waiting ? Theme.alpha(Theme.text, 0.03)
       : root.failed ? Theme.alpha(Theme.accent, 0.10)
       : root.locked ? Theme.surface04
       : Theme.surface05

  border.width: 1
  border.color: root.waiting ? Theme.alpha(Theme.text, 0.14)
              : root.failed ? Theme.alpha(Theme.accent, 0.65)
              : root.locked ? Theme.hairline
              : Theme.alpha(Theme.accent, 0.50)

  // 0 0 0 3px rgba(accent,.12): a solid ring outside the border, not a blur.
  // Drawn only while the field is both live and focused -- the failed state
  // carries its weight in the border instead, and a locked field that still
  // glowed would look like it were waiting for typing.
  Rectangle {
    anchors { fill: parent; margins: -3 }
    radius: root.radius + 3
    color: "transparent"
    border.width: 3
    border.color: Theme.alpha(Theme.accent, 0.12)
    visible: input.activeFocus && !root.failed && !root.locked && !root.waiting
  }

  // -- waiting: no field, just what is being waited for ----------------------
  Text {
    anchors.centerIn: parent
    visible: root.waiting
    text: root.placeholder
    font { family: Theme.fontMono; pixelSize: 10; weight: 400 }
    color: Theme.text3
  }

  // -- locked: a FIXED seven dots -------------------------------------------
  // Not one per character. Once the password is submitted the field must stop
  // saying how long it was: an onlooker who watched someone authenticate should
  // not come away knowing the length of their password.
  Row {
    id: dotRow
    anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
    visible: root.locked && !root.waiting
    spacing: 4
    opacity: 0.4

    Repeater {
      id: dots
      model: 7
      Rectangle {
        width: 5; height: 5; radius: 3
        color: Theme.alpha(Theme.text, 0.7)
      }
    }
  }

  // -- input ----------------------------------------------------------------
  TextInput {
    id: input

    visible: !root.locked && !root.waiting
    enabled: visible
    anchors {
      left: parent.left; leftMargin: 12
      right: reveal.visible ? reveal.left : counterText.left
      rightMargin: 8
      verticalCenter: parent.verticalCenter
    }

    echoMode: root.revealed ? TextInput.Normal : TextInput.Password
    passwordCharacter: "•"
    // Qt unmasks the character just typed for a moment by default. On a
    // surface like this one that is a shoulder surfer's whole job made easy.
    passwordMaskDelay: 0
    font { family: Theme.fontMono; pixelSize: 11; weight: 500 }
    color: Theme.text
    selectionColor: Theme.accentFill
    selectedTextColor: Theme.text
    clip: true

    onAccepted: root.accepted(input.text)
    Keys.onEscapePressed: event => {
      root.cancelled()
      event.accepted = true
    }

    // Solid crimson block, like the launcher's -- the shell has one cursor.
    cursorDelegate: Rectangle {
      width: 2
      height: 14
      color: Theme.accent
    }

    Text {
      anchors { left: parent.left; verticalCenter: parent.verticalCenter }
      visible: input.text === ""
      text: root.failed ? root.error : root.placeholder
      font { family: Theme.fontMono; pixelSize: 10; weight: root.failed ? 500 : 400 }
      color: root.failed ? Theme.accentSoft : Theme.alpha(Theme.text, 0.30)
    }
  }

  // -- the n of 3 counter ---------------------------------------------------
  Text {
    id: counterText
    anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
    visible: root.counter !== "" && !root.locked && !root.waiting
    text: root.counter
    font { family: Theme.fontMono; pixelSize: 9; weight: 400 }
    color: Theme.alpha(Theme.accentSoft, 0.6)
  }

  Icon {
    id: reveal
    anchors { right: parent.right; rightMargin: 11; verticalCenter: parent.verticalCenter }
    visible: root.revealable && !root.locked && !root.waiting
    name: root.revealed ? "eye-off" : "eye"
    size: 13
    tint: Theme.alpha(Theme.text, root.revealed ? 0.6 : 0.35)

    MouseArea {
      anchors { fill: parent; margins: -6 }
      cursorShape: Qt.PointingHandCursor
      onClicked: root.revealed = !root.revealed
    }
  }
}
