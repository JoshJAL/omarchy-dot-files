import QtQuick
import qs.Commons
import qs.Ui

// One window = one button.
//
// Takes the ListModel roles as required properties rather than a single `entry`
// object. That is what lets a delegate survive: when a role changes, the
// Repeater updates that property in place instead of rebuilding the delegate.
// It also means `address` stays valid for the delegate's whole life, including
// on the hover-leave path, where an `entry` reference could already be stale.
BarIconButton {
  id: button

  required property string address
  required property string title
  required property string appClass
  required property bool urgent
  required property bool activated
  required property int index

  property var host: null
  property real iconPixelSize: 14

  labelVisible: false
  hasVisualContent: true
  opticalSize: Math.max(button.iconPixelSize, Style.bar.iconCanvas)

  // The plain bar tooltip is the fallback identification while previews are
  // off; with previews on it would double up with the card, so it is cleared
  // (Bar.showTooltip early-returns on empty text).
  tooltipText: button.host && button.host.previewsEnabled ? "" : button.title

  // Inactive windows read back, the focused one reads forward.
  opacity: button.activated ? 1.0 : 0.5
  Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

  Component.onCompleted: if (button.host) button.host.delegateCreations++

  iconComponent: Component {
    WindowIcon {
      appClass: button.appClass
      appLibrary: button.host && button.host.bar && button.host.bar.shell
        ? button.host.bar.shell.appLibrary : null
      overrides: button.host ? button.host.classIconOverrides : ({})
      size: button.iconPixelSize
      tint: button.foreground
    }
  }

  // WidgetButton emits `pressed` from onClicked, i.e. on RELEASE -- there is no
  // press-time hook to hang a menu off. Opening on release is therefore correct
  // here, and there is no trailing release to swallow. (Tray.qml can open on
  // press only because it hand-rolls its own MouseArea; stacking a second
  // hoverEnabled MouseArea over this one would break tooltipHovered, and with
  // it the whole preview state machine.)
  onPressed: function (which) {
    if (!button.host) return
    // Always first: the preview must not survive the click, and must not
    // re-latch while the pointer is still sitting on this icon.
    button.host.dismissPreviewForClick(button.address)
    if (which === Qt.RightButton) button.host.openMenu(button, button.address)
    else if (which === Qt.MiddleButton) button.host.closeWindow(button.address)
    else button.host.focusWindow(button.address)
  }

  onTooltipHoveredChanged: {
    if (!button.host) return
    if (button.tooltipHovered) button.host.requestPreview(button, button.address)
    else button.host.cancelPreview(button, button.address)
  }

  // Urgent marker on the bar's inner edge. Geometry mirrors the open-panel
  // indicator in Bar.qml so it reads as part of the same bar language.
  Rectangle {
    visible: button.urgent
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
