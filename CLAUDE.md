# c7shell

Hyprland desktop plus a Quickshell shell. Read `README.md` for the layout and
`docs/architecture.md` before you change anything under `quickshell/c7shell/`
or `plugin/`.

## The ownership rule

C++ owns the system side. QML and JavaScript own interaction and presentation
only: QML knows "the person clicked here" and dispatches a C7 action, or binds
to C7 state.

- Every integration with something c7shell does not control (PipeWire,
  UPower, BlueZ, NetworkManager, Hyprland, tuned, fprintd, grim, kitty, ...)
  is a plain C++ library in `plugin/lib/<name>/` (no QML, no Quickshell),
  adapted by a C++ contract in `plugin/src/contracts/` and a backend in
  `plugin/src/backends/<area>/`. The contract is a `QML_SINGLETON` (for
  example `Network`) whose `create()` returns the selected backend. This holds
  even with one backend, so any backend can be swapped later.
- No QML file imports a Quickshell integration module (`Quickshell.Services.*`,
  `.Networking`, `.Bluetooth`, `.Hyprland`, `.DBusMenu`) or starts a process.
  Qt and Quickshell's core (windows, `Quickshell.Wayland`, `FileView`,
  `JsonAdapter`, `IpcHandler`) are the framework and stay.
- Lists the UI shows are `QAbstractListModel`s with stable rows, never JS
  arrays of objects.
- Pure logic that does not decide how something looks or responds to input
  goes in the plugin too. Layout, bindings, handlers, animation, view state
  and display formatting stay in QML/JS.

- C++ with Qt 6 only. Quickshell (LGPL-3.0-only) may be read for ideas and
  is never copied, translated or paraphrased; c7shell is MIT.
- Test first, against per-test fakes from `plugin/lib/testing/`; no sleeps, no
  host state. Gates: 90% line / 80% branch coverage, 70% of mutants killed,
  50 consecutive runs. Three review agents approve every PR.

`docs/architecture.md` has the network feature as the worked example.

Use the `c7shell-native-boundary` skill whenever you add or change a service,
a contract, a backend, a `Process`, an `exec`, an `import Quickshell.*`,
D-Bus access, file parsing, or logic in a `.js` file.

`tests/test-native-boundary.sh` enforces the rule, and
`tests/test-native-boundary-selftest.sh` proves it catches violations. Never add an entry to any
of its `debt` tables; only remove them.

## Checks

- `for t in tests/*.sh; do "$t"; done` runs the suite (`PKGBUILD check()` runs
  the same).
- After changing code, run `graphify update .`.
