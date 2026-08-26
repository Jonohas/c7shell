import QtQuick
import Quickshell
import "Calc.js" as Calc

// Inline arithmetic. The expression is parsed, never eval()'d -- see Calc.js.
// ↵ copies the result to the clipboard.
Item {
  id: root

  readonly property string name: "calc"
  property var results: []

  function search(query) {
    const expression = query.trim()
    if (expression === "") { root.results = []; return }

    const outcome = Calc.tryEval(expression)
    root.results = [outcome.ok ? {
      value: outcome.value,
      title: outcome.value,
      sub: `calc · ${expression}`,
      meta: "copy",
      mono: "="
    } : {
      title: "—",
      sub: `calc · ${outcome.error}`,
      meta: "",
      mono: "="
    }]
  }

  function activate(row) {
    if (row.value !== undefined) Quickshell.clipboardText = row.value
  }
}
