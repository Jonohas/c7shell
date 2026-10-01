pragma ComponentBehavior: Bound
import QtQuick
import qs.Theme
import qs.Common
import qs.Services
import qs.Modules.Settings

// Settings -> fingerprints: the enrolled fingers, one row each with a remove,
// and a picker to enroll another. What unlocks with them is the second card --
// the lock screen follows enrolment on its own, the password prompt needs the
// PAM line c7shell-bootstrap writes.
SettingsPage {
  id: root

  title: "Fingerprints"
  subtitle: FingerprintService.available ? FingerprintService.device
          : "fprintd · enrolled fingers"

  Component.onCompleted: FingerprintService.refresh()

  // The label last picked. Enrolling it takes it out of the options, so the
  // dropdown falls back to the first finger still free rather than pointing at
  // one that is already enrolled.
  property string chosen: ""

  // -- no reader -------------------------------------------------------------
  SettingsCard {
    width: parent.width
    visible: FingerprintService.loaded && !FingerprintService.available

    Text {
      width: parent.width
      wrapMode: Text.Wrap
      text: "no fingerprint reader found. install fprintd, and check that "
          + "fprintd-list sees your reader."
      font { family: Theme.fontMono; pixelSize: 11; weight: 400 }
      color: Theme.text2
    }
  }

  // -- enrolled --------------------------------------------------------------
  SectionLabel {
    text: "enrolled"
    visible: FingerprintService.available
  }

  SettingsCard {
    width: parent.width
    visible: FingerprintService.available
    padH: 0
    padV: 0
    spacing: 0

    Repeater {
      model: FingerprintService.enrolled

      SettingsListRow {
        id: fingerRow

        required property string modelData
        required property int index

        width: parent.width
        divider: index > 0
        title: FingerprintService.label(modelData)

        Chip {
          text: "remove"
          enabled: !FingerprintService.busy
          onTriggered: FingerprintService.remove(fingerRow.modelData)
        }
      }
    }

    SettingsListRow {
      width: parent.width
      divider: false
      visible: FingerprintService.enrolled.length === 0
      title: "no fingers enrolled"
      subtitle: "the lock screen and the password prompt only take a password"
    }
  }

  // -- add -------------------------------------------------------------------
  SettingsCard {
    width: parent.width
    visible: FingerprintService.available && FingerprintService.unenrolled.length > 0
    padH: 0
    padV: 0
    spacing: 0

    SettingsListRow {
      width: parent.width
      divider: false
      title: FingerprintService.enrolling !== ""
        ? `enrolling ${FingerprintService.label(FingerprintService.enrolling)}`
        : "add a finger"
      subtitle: FingerprintService.error !== "" ? FingerprintService.error
              : FingerprintService.hint !== "" ? FingerprintService.hint
              : FingerprintService.enrolling !== ""
                ? `touch the sensor, lift, repeat · ${FingerprintService.scans} scans recorded`
              : "pick a finger, then touch the sensor until it is recorded"

      Dropdown {
        id: pick
        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: 140
        visible: FingerprintService.enrolling === ""
        options: FingerprintService.unenrolled.map(f => FingerprintService.label(f))
        current: options.includes(root.chosen) ? root.chosen
               : options.length > 0 ? options[0] : ""
        onPicked: v => root.chosen = v
      }

      Chip {
        anchors.verticalCenter: parent.verticalCenter
        text: FingerprintService.enrolling !== "" ? "cancel" : "enroll"
        accented: FingerprintService.enrolling === ""
        enabled: FingerprintService.enrolling !== "" || !FingerprintService.busy
        onTriggered: {
          if (FingerprintService.enrolling !== "") {
            FingerprintService.cancelEnroll()
            return
          }
          const i = pick.options.indexOf(pick.current)
          if (i >= 0) FingerprintService.enroll(FingerprintService.unenrolled[i])
        }
      }
    }
  }

  // -- where it unlocks ------------------------------------------------------
  SectionLabel {
    text: "unlocks"
    visible: FingerprintService.available
  }

  SettingsCard {
    width: parent.width
    visible: FingerprintService.available
    padH: 0
    padV: 0
    spacing: 0

    SettingsListRow {
      width: parent.width
      divider: false
      title: "lock screen"
      subtitle: FingerprintService.enrolled.length > 0
        ? "on · from the next lock"
        : "off until a finger is enrolled"
    }

    SettingsListRow {
      width: parent.width
      title: "password prompt"
      subtitle: FingerprintService.promptOn
        ? "on · polkit prompts take a finger before the password"
        : "off · run c7shell-bootstrap to add pam_fprintd to polkit"
    }
  }
}
