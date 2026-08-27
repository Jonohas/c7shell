import QtQuick

// Near-black ground, two crimson glows and a 56px grid -- the same backdrop
// the shell's wallpaper falls back to, so a greeter with no wallpaper set still
// looks like c7shell rather than like unstyled sddm.
//
// With `wallpaper` pointing at a readable image the photo takes over and the
// glows step aside; a scrim keeps the card legible over a bright one. That is
// the "boot -> desktop is one continuous image" case: set it to the same file
// hyprpaper uses, somewhere the sddm user can actually read.
Item {
  id: root

  property url wallpaper: ""
  property bool showGrid: true
  readonly property bool hasWallpaper: wallpaper != "" && picture.status === Image.Ready

  Rectangle {
    anchors.fill: parent
    color: Theme.bg
  }

  Image {
    id: picture
    anchors.fill: parent
    source: root.wallpaper
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
    cache: false
    visible: root.hasWallpaper
    // A 4K wallpaper on a 1080p panel is 4x the texture for the same pixels.
    // 0 means "the image's own size", which is the right fallback before the
    // window has a width.
    sourceSize.width: root.width
  }

  // Only over a photo: on the plain ground it would just mute the glows.
  Rectangle {
    anchors.fill: parent
    visible: root.hasWallpaper
    color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.55)
  }

  // radial-gradient(900x520 at 50% 120%) and (700x420 at 12% -15%), both
  // crimson. Canvas rather than QtQuick.Shapes: Shapes' RadialGradient only
  // fills a path, and Qt5Compat's RadialGradient item is a package this
  // greeter must not need.
  Canvas {
    id: glow
    anchors.fill: parent
    visible: !root.hasWallpaper
    renderStrategy: Canvas.Cooperative

    // The mockup's glow sizes are in its own 1120x630 frame; on a real screen
    // they scale with the smaller axis so the composition survives 21:9.
    readonly property real k: Math.max(root.width / 1120, root.height / 630)

    onPaint: {
      const ctx = getContext("2d")
      ctx.reset()
      const stops = function (grad, a) {
        grad.addColorStop(0, Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, a))
        grad.addColorStop(0.68, Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0))
        return grad
      }
      // Canvas gradients are circular, so each ellipse is a circle drawn on a
      // scaled canvas: save/scale/restore around it does the squashing.
      const ellipse = function (cx, cy, rx, ry, a) {
        ctx.save()
        ctx.translate(cx, cy)
        ctx.scale(1, ry / rx)
        const g = ctx.createRadialGradient(0, 0, 0, 0, 0, rx)
        ctx.fillStyle = stops(g, a)
        ctx.beginPath()
        ctx.arc(0, 0, rx, 0, Math.PI * 2)
        ctx.fill()
        ctx.restore()
      }
      ellipse(width * 0.5, height * 1.2, 900 * glow.k, 520 * glow.k, 0.20)
      ellipse(width * 0.12, height * -0.15, 700 * glow.k, 420 * glow.k, 0.10)
    }
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
  }

  // 56px grid at 2.2% white -- the shell's wallpaper grid, one line per step.
  Item {
    anchors.fill: parent
    visible: root.showGrid && !root.hasWallpaper
    readonly property int step: Theme.px(56)

    Repeater {
      model: parent.step > 0 ? Math.ceil(root.width / parent.step) + 1 : 0
      Rectangle {
        required property int index
        x: index * parent.step
        width: 1
        height: root.height
        color: Theme.grid
      }
    }
    Repeater {
      model: parent.step > 0 ? Math.ceil(root.height / parent.step) + 1 : 0
      Rectangle {
        required property int index
        y: index * parent.step
        width: root.width
        height: 1
        color: Theme.grid
      }
    }
  }
}
