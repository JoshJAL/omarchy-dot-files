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

  // Titled mode draws its own icon+text row (see below) because the two
  // centring schemes collide: WidgetButton anchors its label centerIn parent
  // and BarIconButton anchors the icon canvas centerIn parent, so turning the
  // base label on would stack the text straight on top of the icon -- in the
  // icon font, at that. Vertical bars keep icons only; there is no width to
  // spend on a title.
  readonly property bool titled: !!button.host && button.host.showTitles && !button.vertical

  readonly property real titledWidth:
    Style.space(4) * 2 + button.iconPixelSize + Style.space(3) + titleLabel.width

  labelVisible: false
  hasVisualContent: true
  opticalSize: Math.max(button.iconPixelSize, Style.bar.iconCanvas)
  fixedWidth: button.vertical ? -1 : (button.titled ? button.titledWidth : button.slotSize)

  // The plain bar tooltip is the fallback identification while previews are
  // off; with previews on it would double up with the card, so it is cleared
  // (Bar.showTooltip early-returns on empty text).
  tooltipText: button.host && button.host.previewsEnabled ? "" : button.title

  // Inactive windows read back, the focused one reads forward. With
  // dimInactive off every window reads forward and only the urgent marker and
  // the bar's own hover treatment distinguish them.
  opacity: (!button.host || button.host.dimInactive) && !button.activated ? 0.5 : 1.0
  Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

  Component.onCompleted: if (button.host) button.host.delegateCreations++

  // Null in titled mode so the base draws nothing and titleRow owns the
  // rendering. hasVisualContent is pinned true above, so emptying the base
  // content cannot make the button vanish.
  iconComponent: button.titled ? null : iconOnly

  Component {
    id: iconOnly
    WindowIcon {
      appClass: button.appClass
      appLibrary: button.host && button.host.bar && button.host.bar.shell
        ? button.host.bar.shell.appLibrary : null
      overrides: button.host ? button.host.classIconOverrides : ({})
      size: button.iconPixelSize
      tint: button.foreground
    }
  }

  // ---- titled mode: icon and elided title, left-aligned.
  //
  // Explicit height rather than letting the Row derive it from its children:
  // the children anchor to the Row's verticalCenter, and deriving height from
  // them while they position against it is a binding loop.
  Row {
    id: titleRow
    visible: button.titled
    height: parent.height
    spacing: Style.space(3)
    anchors.left: parent.left
    anchors.leftMargin: Style.space(4)

    WindowIcon {
      anchors.verticalCenter: parent.verticalCenter
      appClass: button.appClass
      appLibrary: button.host && button.host.bar && button.host.bar.shell
        ? button.host.bar.shell.appLibrary : null
      overrides: button.host ? button.host.classIconOverrides : ({})
      size: button.iconPixelSize
      tint: button.foreground
    }

    // Natural, unelided width of the title. Measuring here rather than reading
    // titleLabel.implicitWidth is load-bearing: an eliding Text reports the
    // ELIDED width as its implicitWidth, so binding width to implicitWidth
    // feeds back on itself and ratchets the label down to a single character.
    TextMetrics {
      id: titleMetrics
      font: titleLabel.font
      text: button.title
    }

    Text {
      id: titleLabel
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: button.title
      color: button.foreground
      font.family: button.bar ? button.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.bodySmall
      renderType: Text.NativeRendering
      elide: Text.ElideRight
      // Width feeds titledWidth -> fixedWidth, so it must depend only on the
      // measured text and the cap, never on the button's own width.
      //
      // The +2 is not slop. TextMetrics.width is the font's advance sum, but
      // NativeRendering paints a hair wider (hinting, glyph overhang), so a
      // title that genuinely fits still tripped ElideRight and lost its last
      // couple of characters -- "T3 Code (Alpha)" came out "T3 Code (Alph…"
      // against a 300px cap. Measure generously, then let the cap do the
      // actual limiting.
      readonly property real naturalWidth:
        Math.ceil(Math.max(titleMetrics.width, titleMetrics.boundingRect.width)) + 2
      width: Math.min(naturalWidth, Math.max(0, button.host ? button.host.maxTitleWidth : 140))
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
    if (which === Qt.RightButton)
      button.host.runClickAction(button.host.rightClick, button, button.address)
    else if (which === Qt.MiddleButton)
      button.host.runClickAction(button.host.middleClick, button, button.address)
    else
      button.host.focusWindow(button.address)
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
