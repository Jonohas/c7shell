pragma Singleton
import Quickshell

// One home for "which terminal, and how do I hand it a command". The launcher's
// three providers each carried their own `TERMINAL || kitty` fallback.
Singleton {
  id: root

  readonly property string program: Quickshell.env("TERMINAL") || "kitty"

  // argv is what the terminal should run, already split.
  function run(argv) {
    Quickshell.execDetached([root.program, "-e"].concat(argv))
  }
}
