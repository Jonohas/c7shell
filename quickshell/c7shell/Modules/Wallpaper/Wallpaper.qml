import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Services

// The wallpaper, painted by the shell on the background layer.
//
// Normally hyprpaper does this and none of these windows exist. It cannot on a
// virtual GPU: hyprpaper draws through hyprtoolkit, which has no software path
// and commits a dmabuf the compositor then fails to import --
//
//     CDRMRenderer(drm): Can't create renderer, no matching devices found
//     drm: initMgpu: no renderer
//
// -- and hyprpaper does not survive being dropped for it, it SIGABRTs. Which is
// why the check is not "did hyprpaper work": on those machines it is not
// running at all, having died on the first wallpaper request of the session.
// hypr/conf/gpu.lua decides, conf/autostart.lua leaves hyprpaper out, and
// conf/environment.lua sets C7SHELL_WALLPAPER=shell for this.
//
// The shell has no such trouble: it renders with llvmpipe (conf/environment.lua
// again) and the compositor imports its buffers fine -- the bar has been proof
// of that all along.
Scope {
  id: root

  // No wallpaper set is no window: an unpainted desktop should look the way it
  // does under hyprpaper, not like a black rectangle the shell put there.
  readonly property bool active:
    AppearanceStore.shellDrawsWallpaper && AppearanceStore.wallpaper !== ""

  Variants {
    model: root.active ? Quickshell.screens : []

    PanelWindow {
      id: win

      required property var modelData

      screen: win.modelData
      anchors { top: true; bottom: true; left: true; right: true }
      // A wallpaper reserves nothing and takes no input. Without the empty
      // mask this surface would swallow every click meant for the desktop
      // below it.
      exclusionMode: ExclusionMode.Ignore
      mask: Region {}
      color: "transparent"

      WlrLayershell.layer: WlrLayer.Background
      WlrLayershell.namespace: "c7shell-wallpaper"

      Image {
        anchors.fill: parent
        source: `file://${AppearanceStore.wallpaper}`
        // Cover, which is what hyprpaper does with a wallpaper that does not
        // match the output's aspect.
        fillMode: Image.PreserveAspectCrop
        // Decode at the size it is drawn at: a 6000px photo scaled into a
        // 2560px output otherwise costs its full decoded size in memory, per
        // screen, for a picture nobody can see at that resolution.
        sourceSize: Qt.size(win.screen.width * win.screen.devicePixelRatio,
                            win.screen.height * win.screen.devicePixelRatio)
        asynchronous: true
      }
    }
  }
}
