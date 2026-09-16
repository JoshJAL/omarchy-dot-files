import QtQuick
import QtQuick.Effects
import Quickshell
import qs.Commons
import "IconModel.js" as IconModel

// App icon for one window class.
//
// Plain Image rather than Quickshell.Widgets.IconImage on purpose: IconImage
// decodes at the logical size, which leaves PNG icons upscaled and blurry on
// HiDPI. Same reasoning and same sourceSize trick as Tray.qml.
Item {
  id: root

  property string appClass: ""
  property var appLibrary: null
  property var overrides: ({})
  property real size: 14
  property color tint: Color.foreground

  readonly property string iconName: IconModel.iconNameFor(DesktopEntries, root.appClass, root.overrides)
  readonly property bool symbolic: IconModel.isSymbolic(root.iconName)
  readonly property string iconUrl: IconModel.iconUrlFor(Quickshell, root.appLibrary, root.iconName)

  implicitWidth: root.size
  implicitHeight: root.size

  Image {
    id: image
    anchors.centerIn: parent
    width: root.size
    height: root.size
    fillMode: Image.PreserveAspectFit
    asynchronous: true
    // Decode at physical pixels, not logical ones.
    sourceSize.width: Math.round(root.size * Screen.devicePixelRatio)
    sourceSize.height: Math.round(root.size * Screen.devicePixelRatio)
    source: root.iconUrl
    visible: !root.symbolic && status === Image.Ready
    layer.enabled: root.symbolic
  }

  MultiEffect {
    anchors.fill: image
    source: image
    visible: root.symbolic && image.status === Image.Ready
    colorization: 1.0
    colorizationColor: root.tint
  }

  // Last resort: a letter, so a window with no resolvable icon is still
  // identifiable and the slot never renders empty.
  Text {
    anchors.centerIn: parent
    visible: image.status !== Image.Ready
    text: root.appClass.length > 0 ? root.appClass.charAt(0).toUpperCase() : "?"
    color: root.tint
    font.pixelSize: Math.round(root.size * 0.8)
    font.bold: true
    renderType: Text.NativeRendering
    textFormat: Text.PlainText
  }

}
