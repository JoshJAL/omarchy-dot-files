import QtQuick
import qs.Commons
import qs.Ui

// The "+N" list: windows past `maxIcons`, with the same click behavior as a
// real taskbar button. Hover previews are deliberately not offered here.
PopupCard {
  id: card

  property var host: null
  property var model: null

  readonly property color fg: card.bar ? card.bar.foreground : Color.foreground
  readonly property string fontFamily: card.bar ? card.bar.fontFamily : Style.font.family
  readonly property int rowHeight: Style.space(30)

  padding: Style.space(8)
  borderColor: Qt.rgba(card.fg.r, card.fg.g, card.fg.b, 0.45)
  contentWidth: card.fittedContentWidth(Style.space(280))
  contentHeight: card.fittedContentHeight(column.implicitHeight, Style.space(420))

  Column {
    id: column
    width: parent ? parent.width : Style.space(280)
    spacing: 0

    Repeater {
      model: card.model

      Item {
        id: overflowRow
        required property string address
        required property string title
        required property string appClass
        required property int index

        width: column.width
        implicitHeight: card.rowHeight
        // A Column positions only visible children, so the hidden head of the
        // list leaves no gap.
        visible: card.host ? overflowRow.index >= card.host.visibleCount : false

        Rectangle {
          anchors.fill: parent
          radius: Math.max(2, Style.cornerRadius)
          color: rowMouse.containsMouse ? Style.hoverFillFor(card.fg, card.fg) : "transparent"
        }

        WindowIcon {
          id: rowIcon
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
          anchors.leftMargin: Style.space(6)
          appClass: overflowRow.appClass
          appLibrary: card.host && card.host.bar && card.host.bar.shell
            ? card.host.bar.shell.appLibrary : null
          overrides: card.host ? card.host.classIconOverrides : ({})
          size: Style.space(16)
          tint: card.fg
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: rowIcon.right
          anchors.leftMargin: Style.space(8)
          anchors.right: parent.right
          anchors.rightMargin: Style.space(8)
          text: overflowRow.title
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: card.fg
          font.family: card.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        MouseArea {
          id: rowMouse
          anchors.fill: parent
          hoverEnabled: true
          acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
          cursorShape: Qt.PointingHandCursor
          onClicked: function (mouse) {
            if (!card.host) return
            card.host.overflowOpen = false
            // Anchor any menu to the CHIP, not to this row. PopupCard resolves
            // its screen from anchorItem.QsWindow.window, and anchoring inside
            // this popup would nest a popup in a popup and resolve the wrong
            // surface -- landing the menu on the wrong monitor.
            if (mouse.button === Qt.RightButton) {
              card.host.runClickAction(card.host.rightClick, card.anchorItem, overflowRow.address)
            } else if (mouse.button === Qt.MiddleButton) {
              card.host.runClickAction(card.host.middleClick, card.anchorItem, overflowRow.address)
            } else {
              card.host.focusWindow(overflowRow.address)
            }
          }
        }
      }
    }
  }
}
