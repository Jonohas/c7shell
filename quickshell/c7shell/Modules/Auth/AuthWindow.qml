pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import qs.Theme
import qs.Services

// Turn 14, the surface: one modal prompt, centred, over a dimmed screen.
//
// Overlay layer with an EXCLUSIVE keyboard grab, which is the security half of
// this window rather than a convenience -- nothing behind it can read what is
// typed into it, the same reason the lock screen takes one. It follows from
// that grab that Esc has to work in every state, verifying included: a modal
// that holds the keyboard and cannot be dismissed is a hung session.
//
// Only ever one prompt on screen. A second request queues behind the first --
// the daemon keeps it un-started, so there is never a second live PAM
// conversation -- and the panel says how many are waiting.
PanelWindow {
  id: win

  visible: AuthService.active
  screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? null

  anchors { top: true; bottom: true; left: true; right: true }
  exclusiveZone: 0
  color: "transparent"

  // Its own namespace, and hypr/conf/rules.lua gives it its own layer rule:
  // the shell-wide c7shell-blur rule skips anything below 0.7 alpha so that
  // panel shadows stay sharp, and the 45% backdrop this window draws is on the
  // wrong side of that line.
  WlrLayershell.namespace: "c7shell-auth"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

  // -- backdrop --------------------------------------------------------------
  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.45)

    // No click-to-dismiss. Every other popover in the shell closes when you
    // click away; this one does not, because a stray click must not answer
    // "no" to a question the person may not have read yet. Esc and cancel are
    // the two ways out, and both are deliberate.
    MouseArea { anchors.fill: parent }
  }

  FocusScope {
    id: scope
    anchors.fill: parent
    focus: true

    // Esc lives here rather than on the field, so it still cancels while the
    // field is locked or replaced by the fingerprint state.
    Keys.onEscapePressed: event => {
      AuthService.cancel()
      event.accepted = true
    }

    Column {
      anchors.centerIn: parent
      spacing: 9

      AuthPrompt {
        id: prompt

        // Never bound to a null request: the window is only visible while
        // there is one, but bindings keep evaluating through the frame in
        // which it goes away.
        request: AuthService.current ?? ({})
        stage: AuthService.stage
        tries: AuthService.tries
        maxTries: AuthService.maxTries
        promptReady: AuthService.promptReady
        promptText: AuthService.promptText
        factorText: AuthService.factorText
        pamError: AuthService.pamError
        waiting: AuthService.waiting

        onSubmitted: secret => AuthService.submit(secret)
        onCancelled: AuthService.cancel()
        onUsePasswordRequested: AuthService.usePassword()

        // One shake, then the field is cleared and keeps focus -- the greeter's
        // rule, and the reason retyping needs no click.
        SequentialAnimation {
          id: shakeAnim
          NumberAnimation { target: prompt; property: "x"; to:  7; duration: 45 }
          NumberAnimation { target: prompt; property: "x"; to: -6; duration: 55 }
          NumberAnimation { target: prompt; property: "x"; to:  4; duration: 50 }
          NumberAnimation { target: prompt; property: "x"; to:  0; duration: 45 }
        }
      }

      // "1 more waiting": the only hint that the queue exists. Deliberately
      // not a list -- the next prompt will introduce itself.
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: AuthService.waiting > 0
        text: AuthService.waiting === 1 ? "1 more waiting"
                                        : `${AuthService.waiting} more waiting`
        font { family: Theme.fontMono; pixelSize: 9; weight: 500 }
        color: Theme.alpha(Theme.text, 0.32)
      }
    }
  }

  // -- focus -----------------------------------------------------------------
  // The field takes focus when it can be typed into, and the scope takes it
  // back when it cannot, so Esc always lands somewhere.
  function refocus() {
    if (!win.visible) return
    if (AuthService.promptReady && !AuthService.verifying && !AuthService.onFactor)
      prompt.focusInput()
    else
      scope.forceActiveFocus()
  }

  // Keyboard focus only exists once the layer surface has mapped, so the first
  // focus of a newly shown window cannot be taken synchronously.
  onVisibleChanged: if (win.visible) Qt.callLater(win.refocus)

  Connections {
    target: AuthService

    function onStageChanged() { Qt.callLater(win.refocus) }
    function onPromptReadyChanged() { Qt.callLater(win.refocus) }
    function onCurrentChanged() {
      prompt.clearInput()
      Qt.callLater(win.refocus)
    }
    // Wrong password: shake once, clear, keep focus.
    function onShake() {
      shakeAnim.restart()
      prompt.clearInput()
      Qt.callLater(win.refocus)
    }
  }
}
