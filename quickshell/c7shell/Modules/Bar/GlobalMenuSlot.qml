import QtQuick
import qs.Theme
import qs.Services

// Global menu: the focused app's name, then the menu bar it exports over
// dbusmenu. Nothing exported (the normal case on Hyprland today -- see
// INTEGRATION.md) means the name alone, which is what SP1 shipped.
Row {
  id: root
  spacing: 2
  // The bar clamps this slot's width; without clipping, a long menu bar would
  // paint straight over the clock.
  clip: true

  // The dropdown's focus grab covers the bar as well as the popup, and Hyprland
  // hands the keyboard to the BAR surface, not the popup -- so the menu's keys
  // have to be handled here, on the bar, rather than in the dropdown window.
  // (Measured: with the dropdown open, esc/left/right arrive on the bar whether
  // the pointer is over the bar or over the dropdown.)
  focus: true
  Keys.onPressed: event => {
    if (root.openIndex < 0) return
    if (event.key === Qt.Key_Escape) root.hide()
    else if (event.key === Qt.Key_Left) root.step(-1)
    else if (event.key === Qt.Key_Right) root.step(1)
    else return
    event.accepted = true
  }

  // Index of the open top-level menu, -1 for none.
  property int openIndex: -1

  function menuName(i) {
    return `menu:${(AppMenuService.menus[i]?.label ?? "").toLowerCase()}`
  }

  function show(i) {
    if (i < 0 || i >= AppMenuService.menus.length) {
      root.hide()
      return
    }
    // Set this BEFORE touching PopoverManager: the current-changed handler
    // below compares against it and would otherwise close what just opened.
    root.openIndex = i
    const name = root.menuName(i)
    if (PopoverManager.current !== name) PopoverManager.toggle(name, labels.itemAt(i))
    else PopoverManager.anchorItem = labels.itemAt(i)
  }

  function hide() {
    root.openIndex = -1
    if (PopoverManager.current.startsWith("menu:")) PopoverManager.close()
  }

  function toggle(i) {
    if (root.openIndex === i) root.hide()
    else root.show(i)
  }

  function step(dir) {
    const n = AppMenuService.menus.length
    if (root.openIndex < 0 || n === 0) return
    root.show((root.openIndex + dir + n) % n)
  }

  Connections {
    target: PopoverManager
    // Something else in the bar claimed the popover slot -- ours is gone.
    function onCurrentChanged() {
      if (root.openIndex >= 0 && PopoverManager.current !== root.menuName(root.openIndex))
        root.openIndex = -1
    }
  }

  Connections {
    target: AppMenuService
    // The exporting app can vanish, or focus can move, with a menu open. Drop
    // the dropdown rather than leaving it pointed at a model that is already
    // gone -- this is the reset guard the model itself cannot provide.
    function onMenusChanged() { root.hide() }
    function onActiveToplevelChanged() { root.hide() }
  }

  Text {
    anchors.verticalCenter: parent.verticalCenter
    leftPadding: 8
    rightPadding: 8
    text: AppMenuService.appName
    font { family: Theme.fontMono; pixelSize: 11; weight: 700 }
    color: Theme.text
    elide: Text.ElideRight
    maximumLineCount: 1
  }

  Repeater {
    id: labels
    // A plain JS array of plain JS objects, not a rebuilt view of an
    // ObjectModel -- the Repeater rule in CONVENTIONS is about live QObjects
    // being freed underneath the delegates, which cannot happen here.
    model: AppMenuService.menus

    Rectangle {
      id: chip
      required property var modelData
      required property int index

      anchors.verticalCenter: parent.verticalCenter
      implicitWidth: label.implicitWidth + 16   // 8px each side
      implicitHeight: label.implicitHeight + 6  // 3px each side
      radius: Theme.radiusMenuRow
      color: root.openIndex === chip.index || mouse.containsMouse ? Theme.hairlineStrong : "transparent"

      Text {
        id: label
        anchors.centerIn: parent
        text: chip.modelData.label ?? ""
        font { family: Theme.fontMono; pixelSize: 11; weight: 500 }
        color: root.openIndex === chip.index ? Theme.text : Theme.alpha(Theme.text, 0.6)
      }

      MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.toggle(chip.index)
        // With a menu already open, sliding across the bar switches menus --
        // the usual menu-bar behaviour, and what left/right does by keyboard.
        onEntered: if (root.openIndex >= 0) root.show(chip.index)
      }
    }
  }

  GlobalMenuDropdown {
    id: dropdown
    anchorItem: root.openIndex >= 0 ? labels.itemAt(root.openIndex) : null
    items: root.openIndex >= 0 ? AppMenuService.menus[root.openIndex]?.items ?? [] : []
    open: dropdown.anchorItem !== null && dropdown.items.length > 0
    onItemActivated: item => {
      AppMenuService.trigger(AppMenuService.menus[root.openIndex]?.label ?? "", item)
      root.hide()
    }
  }
}
