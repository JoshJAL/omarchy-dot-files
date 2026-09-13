import QtQuick
import qs.Commons
import qs.Ui

// One window = one button.
BarIconButton {
  id: button

  property var host: null
  property var entry: null
  property real iconPixelSize: 14

  readonly property bool isActive: button.entry && button.entry.activated === true
  readonly property bool isUrgent: button.entry && button.entry.urgent === true

  labelVisible: false
  hasVisualContent: true
  opticalSize: Math.max(button.iconPixelSize, Style.bar.iconCanvas)

  // The plain bar tooltip is the fallback identification while previews are
  // off; with previews on it would double up with the card, so it is cleared
  // (Bar.showTooltip early-returns on empty text).
  tooltipText: button.host && button.host.previewsEnabled ? "" : (button.entry ? button.entry.title : "")

  // Inactive windows read back, the focused one reads forward.
  opacity: button.isActive ? 1.0 : 0.5
  Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

  iconComponent: Component {
    WindowIcon {
      appClass: button.entry ? button.entry.appClass : ""
      appLibrary: button.host && button.host.bar && button.host.bar.shell
        ? button.host.bar.shell.appLibrary : null
      overrides: button.host ? button.host.classIconOverrides : ({})
      size: button.iconPixelSize
      tint: button.foreground
    }
  }

  onPressed: function (which) {
    if (!button.host || !button.entry) return
    if (which === Qt.RightButton) button.host.openMenu(button, button.entry)
    else if (which === Qt.MiddleButton) button.host.closeWindow(button.entry)
    else button.host.focusWindow(button.entry)
  }

  onTooltipHoveredChanged: {
    if (!button.host) return
    if (button.tooltipHovered) button.host.requestPreview(button, button.entry)
    else button.host.cancelPreview(button)
  }

  // Urgent marker on the bar's inner edge. Geometry mirrors the open-panel
  // indicator in Bar.qml so it reads as part of the same bar language.
  Rectangle {
    visible: button.isUrgent
    color: button.bar ? button.bar.urgent : Color.urgent
    radius: Math.min(width, height) / 2
    width: button.vertical ? Style.space(2) : Math.max(4, button.width - Style.space(8))
    height: button.vertical ? Math.max(4, button.height - Style.space(8)) : Style.space(2)
    x: button.vertical
      ? (button.bar && button.bar.position === "left" ? button.width - width : 0)
      : Style.space(4)
    y: button.vertical
      ? Style.space(4)
      : (button.bar && button.bar.position === "bottom" ? 0 : button.height - height)
  }
}
