import QtQuick
import QtQuick.Window
import qs.Common
import qs.Services
import qs.Modules.Auth

// Self-check for the parts of the password prompt that are pure computation
// and therefore go wrong silently rather than visibly (run by
// tests/test-auth.sh):
//
//   AuthService  the event machine. A prompt that accepts a password one
//                event too early sends it into the NEXT question, which no
//                screenshot review can catch.
//   AuthPrompt   the five things a caller may replace -- icon, two text lines,
//                two button labels -- across every state and every caller.
//   SecretField  that the masked field never reveals how long the password is.
Window {
  id: root
  visible: true
  width: 320; height: 480

  // Throws rather than calling Qt.exit(): Qt.exit() only *schedules* the exit,
  // so the enclosing function runs on and prints the PASS line anyway. A
  // harness that cannot fail is worse than no harness.
  function check(cond, msg) {
    if (!cond) throw new Error(msg)
  }

  function feed(obj) { AuthService.onEvent(obj) }

  // A polkit request as the daemon sends one.
  readonly property var polkitReq: ({
    ev: "request", id: "r1", kind: "polkit", waiting: 0,
    title: "Authentication required",
    detail: "Install 23 packages",
    actionId: "org.archlinux.pamac.commit",
    command: "", proc: "pamac", pid: 4110,
    user: "alex", group: "wheel", root: true
  })

  readonly property var sudoReq: ({
    ev: "request", id: "r2", kind: "sudo", waiting: 0,
    title: "Run as root", detail: "Password:", actionId: "",
    command: "systemctl restart bluetooth",
    proc: "foot", pid: 41207,
    user: "alex", group: "wheel", root: true
  })

  AuthPrompt {
    id: prompt
    request: root.polkitReq
  }

  SecretField { id: field; width: 200 }

  // Split from run() so a thrown check exits at once. Left inline, a failure
  // sat in the event loop until the harness's own 30s timeout killed it, which
  // turned every red run into a half-minute wait.
  Component.onCompleted: {
    try {
      root.run()
    } catch (e) {
      console.log("AUTH-TEST-FAIL: " + e.message)
      Qt.exit(1)
      return
    }
    console.log("AUTH-TEST-PASS")
    Qt.exit(0)
  }

  function run() {
    // ------------------------------------------------------------------ 1 --
    // The event machine, in the order the daemon actually emits it.
    root.feed({ ev: "ready", polkit: true, askpass: "/run/x.sock",
                user: "alex", group: "wheel" })
    check(AuthService.ready, "ready did not mark the service ready")
    check(AuthService.polkitOk, "ready did not record the polkit registration")

    check(!AuthService.active, "the service was active before any request")

    root.feed(root.polkitReq)
    check(AuthService.requests.length === 1, "the request was not queued")
    check(AuthService.current.id === "r1", "the request did not become current")
    check(AuthService.waiting === 0, "a lone request reported others waiting")
    check(AuthService.active, "a queued request did not make the service active")

    root.feed({ ev: "active", id: "r1" })
    check(AuthService.stage === "ask", `a fresh head is not in ask: ${AuthService.stage}`)
    check(AuthService.tries === 0, "a fresh head started with attempts already spent")

    // ------------------------------------------------------------------ 2 --
    // Nothing may be submitted before PAM has asked for anything. This is the
    // one that matters: a secret sent with no prompt outstanding is answered
    // into whatever PAM asks NEXT.
    check(!AuthService.promptReady, "the field was live before PAM asked")
    AuthService.submit("tooearly")
    check(AuthService.stage === "ask",
          "submitting before a prompt moved the prompt to verifying")

    root.feed({ ev: "prompt", id: "r1", text: "Password:", echo: false })
    check(AuthService.promptReady, "a PAM prompt did not unlock the field")
    check(AuthService.stage === "ask", "a first prompt did not leave the panel in ask")

    AuthService.submit("hunter2")
    check(AuthService.stage === "verifying", "submitting did not lock the panel")
    check(!AuthService.promptReady,
          "the field stayed live while verifying, so a second Enter could be sent")

    // A second submit while verifying must not reach the daemon at all.
    AuthService.submit("again")

    // ------------------------------------------------------------------ 3 --
    // Wrong password: the count, and the fact that it survives the new PAM
    // session that asks again. Losing it there is how "3 of 3" would never be
    // seen by the person about to be locked out of the attempt.
    root.feed({ ev: "failed", id: "r1", tries: 1, max: 3 })
    check(AuthService.stage === "wrong", "a failure did not show as wrong")
    check(AuthService.tries === 1, `the attempt count is ${AuthService.tries}, expected 1`)
    check(!AuthService.promptReady, "the field was live between PAM sessions")

    root.feed({ ev: "prompt", id: "r1", text: "Password:", echo: false })
    check(AuthService.stage === "wrong",
          "the retry prompt reset the panel to ask and lost the n of 3 counter")
    check(AuthService.promptReady, "the retry prompt did not unlock the field")

    // ------------------------------------------------------------------ 4 --
    // The queue. One prompt on screen; the second waits, and does not steal
    // the field from the one being answered.
    root.feed(root.sudoReq)
    check(AuthService.requests.length === 2, "the second request was not queued")
    check(AuthService.current.id === "r1", "a queued request took over the live one")
    check(AuthService.waiting === 1, `waiting is ${AuthService.waiting}, expected 1`)

    root.feed({ ev: "close", id: "r1", ok: true })
    check(AuthService.current.id === "r2", "closing the head did not promote the next")
    check(AuthService.waiting === 0, "the promoted request still counted itself as waiting")

    root.feed({ ev: "active", id: "r2" })
    check(AuthService.tries === 0, "the new head inherited the old one's attempt count")
    check(AuthService.stage === "ask", "the new head inherited the old one's failure")

    root.feed({ ev: "close", id: "r2", ok: false })
    check(!AuthService.active, "the queue emptied but the window would have stayed up")

    // ------------------------------------------------------------------ 5 --
    // The alternate factor is never a dead end, and "use password" is only
    // reachable from it.
    root.feed(root.polkitReq)
    root.feed({ ev: "active", id: "r1" })
    AuthService.usePassword()
    check(AuthService.stage === "ask", "use password fired outside the factor state")

    root.feed({ ev: "factor", id: "r1", kind: "fingerprint",
                text: "Place your finger on the reader" })
    check(AuthService.stage === "factor", "a fingerprint offer did not switch state")
    check(AuthService.onFactor, "onFactor did not follow the factor state")
    AuthService.usePassword()
    check(AuthService.stage === "ask", "use password did not leave the fingerprint state")
    root.feed({ ev: "close", id: "r1", ok: false })

    // ------------------------------------------------------------------ 6 --
    // AuthPrompt's replaceable surface: the five things a caller may change,
    // in every state the design draws.
    const cases = [
      // polkit, the four states of 14a
      { req: root.polkitReq, stage: "ask",
        headline: "Authentication required", icon: "lock",
        primary: "authenticate", cancel: "cancel", placeholder: "password" },
      { req: root.polkitReq, stage: "wrong",
        headline: "Authentication failed", icon: "alert-triangle",
        primary: "try again", cancel: "cancel", placeholder: "password" },
      { req: root.polkitReq, stage: "verifying",
        headline: "Checking…", icon: "lock",
        primary: "authenticate", cancel: "cancel", placeholder: "password" },
      { req: root.polkitReq, stage: "factor",
        headline: "Touch the sensor", icon: "fingerprint",
        primary: "use password", cancel: "cancel",
        placeholder: "waiting for fingerprint" },
      // the per-caller variants of 14b
      { req: root.sudoReq, stage: "ask",
        headline: "Run as root", icon: "terminal",
        primary: "run", cancel: "cancel", placeholder: "password" },
      { req: { kind: "keyring", title: "Unlock keyring",
               detail: "Chromium wants your saved logins", root: false },
        stage: "ask", headline: "Unlock keyring", icon: "key",
        primary: "unlock", cancel: "deny", placeholder: "keyring password" },
      { req: { kind: "wifi", title: "c7-guest",
               detail: "wpa2 · asks the router, not the system", root: false },
        stage: "ask", headline: "c7-guest", icon: "wifi",
        primary: "connect", cancel: "cancel", placeholder: "network key" }
    ]

    for (const c of cases) {
      prompt.pamError = ""
      prompt.noticeText = ""
      prompt.promptText = ""
      prompt.request = c.req
      prompt.stage = c.stage
      const where = `${c.req.kind}/${c.stage}`
      check(prompt.headline === c.headline,
            `${where} headline is "${prompt.headline}", expected "${c.headline}"`)
      check(prompt.iconName === c.icon,
            `${where} icon is "${prompt.iconName}", expected "${c.icon}"`)
      check(prompt.primaryLabel === c.primary,
            `${where} primary button is "${prompt.primaryLabel}", expected "${c.primary}"`)
      check(prompt.cancelLabel === c.cancel,
            `${where} cancel button is "${prompt.cancelLabel}", expected "${c.cancel}"`)
      check(prompt.fieldPlaceholder === c.placeholder,
            `${where} placeholder is "${prompt.fieldPlaceholder}", expected "${c.placeholder}"`)
    }

    // ------------------------------------------------------------------ 7 --
    // Colour carries the privilege level and nothing else. A keyring or wifi
    // secret drawn in crimson would say "root" about something that is not.
    prompt.request = root.polkitReq
    check(prompt.privileged, "a root polkit prompt did not get the crimson tile")
    check(!prompt.compact, "the polkit prompt used the compact 38px variant")
    prompt.request = { kind: "wifi", title: "c7-guest", root: false }
    check(!prompt.privileged, "a network key was drawn as a root prompt")
    check(prompt.compact, "a per-caller variant did not use the compact size")

    // ------------------------------------------------------------------ 8 --
    // Never say "administrator privileges": the description is polkit's own
    // message, and the sudo variant names the process instead.
    prompt.request = root.polkitReq
    prompt.stage = "ask"
    check(prompt.description === "Install 23 packages",
          `the polkit description is "${prompt.description}"`)
    prompt.request = root.sudoReq
    check(prompt.description === "asked by foot · pid 41207",
          `the sudo prompt does not name its caller: "${prompt.description}"`)

    // A PAM notice outranks the caller's own description: pam_faillock's
    // "the account is locked" arrives this way and nothing else says it, so a
    // prompt that swallows it looks like a password that stopped working.
    prompt.request = root.polkitReq
    prompt.noticeText = "The account is locked due to 3 failed logins."
    check(prompt.description === "The account is locked due to 3 failed logins.",
          `a PAM notice was buried under the description: "${prompt.description}"`)

    // And a PAM error outranks even that.
    prompt.pamError = "Account expired"
    check(prompt.description === "Account expired",
          "a PAM error was buried under a PAM notice")
    prompt.pamError = ""
    prompt.noticeText = ""

    // A notice belongs to one conversation only: carried into the next
    // request it would explain a failure that did not happen.
    root.feed(root.polkitReq)
    root.feed({ ev: "info", id: "r1", text: "The account is locked" })
    check(AuthService.noticeText !== "", "a PAM notice was dropped")
    root.feed({ ev: "active", id: "r1" })
    check(AuthService.noticeText === "",
          "a PAM notice survived into the next request")
    root.feed({ ev: "close", id: "r1", ok: false })

    // ------------------------------------------------------------------ 9 --
    // PAM's own wording when it asks for something that is not the password.
    prompt.request = root.polkitReq
    prompt.promptText = "Password:"
    check(prompt.fieldPlaceholder === "password",
          "PAM's plain password prompt was echoed instead of the design's label")
    prompt.promptText = "YubiKey for alex:"
    check(prompt.fieldPlaceholder === "YubiKey for alex",
          `a non-password PAM prompt was not shown: "${prompt.fieldPlaceholder}"`)
    prompt.promptText = ""

    // ----------------------------------------------------------------- 10 --
    // The masked field must not say how long the password is. Seven dots,
    // whatever was typed -- an onlooker who watched someone authenticate must
    // not come away knowing the length.
    field.locked = true
    field.text = "abc"
    const few = field.shownDots
    field.text = "a-much-longer-passphrase-indeed"
    check(field.shownDots === few,
          `the dot row tracks the password length (${few} then ${field.shownDots})`)
    check(few === 7, `the locked field shows ${few} dots, expected a fixed 7`)
    field.locked = false
    check(field.shownDots === 0, "the dot row stayed up after verifying ended")

    // ----------------------------------------------------------------- 11 --
    // The failure message sits where the placeholder does, so the first
    // keystroke replaces it rather than typing underneath an error.
    field.text = ""
    field.error = "wrong password"
    check(field.failed, "an error string did not put the field in its failed look")
    field.error = ""
    check(!field.failed, "clearing the error left the field looking failed")

  }
}
