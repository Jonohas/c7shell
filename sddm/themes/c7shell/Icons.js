.pragma library

// The greeter's icon paths, all drawn in the same 16x16 box the shell's SVG
// assets use, so a glyph here and the same glyph in the bar match stroke for
// stroke. `stroke` is outlined at 1.3-1.6 units, `fill` is filled.
//
// Assets/icons/*.svg cannot simply be pointed at: they live in the c7shell
// config, which is under a user's $HOME and not readable by the sddm user.
var lock = {
  stroke: [
    "M5 6.5h6a2 2 0 0 1 2 2v3.5a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8.5a2 2 0 0 1 2-2z",
    "M5.5 6.5V4.6a2.5 2.5 0 0 1 5 0v1.9"
  ]
}
var warning = {
  stroke: ["M8 3.2 14 13H2L8 3.2Z", "M8 6.8v2.6"],
  fill: ["M8 10.3a0.8 0.8 0 1 0 0 1.6a0.8 0.8 0 1 0 0-1.6z"]
}
var capsLock = { stroke: ["M4 12.5h8", "M5.5 3.5h5", "M8 3.5v9"] }
var chevronDown = { stroke: ["M4 6.5 8 10.5l4-4"], width: 1.6 }
var chevronUp = { stroke: ["M4 9.5 8 5.5l4 4"], width: 1.6 }
var keyboard = {
  stroke: ["M2 4.5h12a1 1 0 0 1 1 1v5a1 1 0 0 1-1 1H2a1 1 0 0 1-1-1v-5a1 1 0 0 1 1-1z",
           "M4 7h.01M6.5 7h.01M9 7h.01M11.5 7h.01M5 9.5h6"]
}
var wifi = {
  stroke: ["M2 6.5a9 9 0 0 1 12 0", "M4.3 9a6 6 0 0 1 7.4 0"],
  fill: ["M8 10.8a1.2 1.2 0 1 0 0 2.4a1.2 1.2 0 1 0 0-2.4z"]
}
var ethernet = {
  stroke: ["M8 3.2v4.4", "M3.4 12.8v-2.6a1 1 0 0 1 1-1h7.2a1 1 0 0 1 1 1v2.6"],
  fill: ["M6.4 2h3.2a0.8 0.8 0 0 1 0.8 0.8v1.6a0.8 0.8 0 0 1-0.8 0.8H6.4a0.8 0.8 0 0 1-0.8-0.8V2.8A0.8 0.8 0 0 1 6.4 2z",
         "M2.4 12h2a0.8 0.8 0 0 1 0.8 0.8v1.4a0.8 0.8 0 0 1-0.8 0.8h-2a0.8 0.8 0 0 1-0.8-0.8v-1.4a0.8 0.8 0 0 1 0.8-0.8z",
         "M11.6 12h2a0.8 0.8 0 0 1 0.8 0.8v1.4a0.8 0.8 0 0 1-0.8 0.8h-2a0.8 0.8 0 0 1-0.8-0.8v-1.4a0.8 0.8 0 0 1 0.8-0.8z"]
}
// The battery's charge bar is drawn separately, so it can track the real level.
var batteryShell = {
  stroke: ["M3.1 5h7.8a1.6 1.6 0 0 1 1.6 1.6v3.3a1.6 1.6 0 0 1-1.6 1.6H3.1a1.6 1.6 0 0 1-1.6-1.6V6.6A1.6 1.6 0 0 1 3.1 5z",
           "M14 7v2.5"],
  width: 1.2
}
var sleep = { stroke: ["M8 8.5v-5", "M4.6 4.8a4.6 4.6 0 1 0 6.8 0"], width: 1.45 }
var reboot = { stroke: ["M13 8a5 5 0 1 1-2.2-4.1", "M13 2.6V6h-3.3"], width: 1.4 }
var shutdown = {
  stroke: ["M5 2.5h6a2.5 2.5 0 0 1 2.5 2.5v6a2.5 2.5 0 0 1-2.5 2.5H5a2.5 2.5 0 0 1-2.5-2.5V5A2.5 2.5 0 0 1 5 2.5z",
           "M6 6l4 4", "M10 6l-4 4"]
}
