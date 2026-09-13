import QtQuick
import qs.Commons
import qs.Ui

// Right-click context menu.
//
// One PopupCard with an in-card drill-down (level 0 -> workspace list), never a
// second surface. Rows are hand-rolled because the shell ships no reusable menu
// row; this follows Tray.qml's idiom deliberately so it reads as the same bar.
//
// Mouse-only by construction: a third-party bar widget's popup cannot receive
// key events at all -- the bar's layer surface is keyboardFocus: None and a
// plugin has no handle on it. Dismissal is outside-click (HyprlandFocusGrab,
// which PopupCard wires up for triggerMode "click") plus the back row.
PopupCard {
  id: card

  property var host: null

  readonly property color fg: card.bar ? card.bar.foreground : Color.foreground
  readonly property string fontFamily: card.bar ? card.bar.fontFamily : Style.font.family
  readonly property int rowHeight: Style.space(30)
  readonly property int gutter: Style.space(22)

  padding: Style.space(8)
  borderColor: Qt.rgba(card.fg.r, card.fg.g, card.fg.b, 0.45)
  contentWidth: card.fittedContentWidth(Style.space(220))
  contentHeight: card.fittedContentHeight(column.implicitHeight, Style.space(420))

  // The card's `visible` stays true for its whole 140ms fade (visible: open ||
  // opacity > 0). Resetting on `open` instead would swap a live workspace
  // submenu for the root level mid-fade -- a visible flash plus a resize as ten
  // rows become three. This is also the moment the focus grab is provably gone,
  // which is why the pending action is dispatched from here.
  onVisibleChanged: {
    if (visible || !card.host) return
    card.host.resetMenuLevel()
    card.host.runPendingMenuAction()
  }

  Column {
    id: column
    width: parent ? parent.width : Style.space(220)
    spacing: 0

    // Which window this menu is acting on. Worth the row: the menu deliberately
    // targets the window you right-clicked, which is usually NOT the focused
    // one, and nothing else on screen tells you which.
    Item {
      width: parent.width
      implicitHeight: card.rowHeight
      visible: card.host && card.host.menuLevel === 0 && card.host.menuTitle !== ""

      Text {
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: Style.space(8)
        anchors.right: parent.right
        anchors.rightMargin: Style.space(8)
        text: card.host ? card.host.menuTitle : ""
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: card.fg
        opacity: 0.6
        font.family: card.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    // Back row, submenu only.
    Item {
      id: backRow
      width: parent.width
      implicitHeight: card.rowHeight
      visible: card.host && card.host.menuLevel === 1

      Rectangle {
        anchors.fill: parent
        radius: Math.max(2, Style.cornerRadius)
        color: backMouse.containsMouse ? Style.hoverFillFor(card.fg, card.fg) : "transparent"
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        width: card.gutter
        horizontalAlignment: Text.AlignHCenter
        text: "‹"
        color: card.fg
        font.family: card.fontFamily
        font.pixelSize: Style.font.body
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: Style.space(28)
        anchors.right: parent.right
        anchors.rightMargin: Style.space(8)
        text: card.host ? card.host.menuTitle : ""
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: card.fg
        font.family: card.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
      MouseArea {
        id: backMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          if (!card.host || card.host.menuLevelSettling) return
          card.host.leaveMenuLevel()
        }
      }
    }

    // Separator under the back row.
    Item {
      width: parent.width
      implicitHeight: Style.space(11)
      visible: backRow.visible
      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Style.space(10)
        anchors.rightMargin: Style.space(10)
        height: 1
        color: Color.popups.border
        opacity: 0.45
      }
    }

    Repeater {
      model: card.host ? card.host.currentMenuRows : []

      Item {
        id: menuRow
        required property var modelData
        width: column.width
        implicitHeight: card.rowHeight

        Rectangle {
          anchors.fill: parent
          radius: Math.max(2, Style.cornerRadius)
          color: rowMouse.containsMouse ? Style.hoverFillFor(card.fg, card.fg) : "transparent"
        }

        // Checkmark gutter. Always present, empty when unchecked, so every
        // label starts at the same x whether or not anything is checked.
        Text {
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
          width: card.gutter
          horizontalAlignment: Text.AlignHCenter
          text: menuRow.modelData.checked ? "" : ""
          color: card.fg
          font.family: card.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Text {
          id: rowLabel
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
          anchors.leftMargin: Style.space(28)
          anchors.right: submenuGlyph.left
          anchors.rightMargin: Style.space(8)
          text: menuRow.modelData.label
          // PlainText unconditionally: window titles reach these rows and any
          // rich-text path is an injection surface.
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: card.fg
          font.family: card.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Text {
          id: submenuGlyph
          visible: menuRow.modelData.submenu === true
          anchors.verticalCenter: parent.verticalCenter
          anchors.right: parent.right
          anchors.rightMargin: Style.space(10)
          width: visible ? implicitWidth : 0
          text: "›"
          color: card.fg
          font.family: card.fontFamily
          font.pixelSize: Style.font.body
        }

        MouseArea {
          id: rowMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (!card.host || card.host.menuLevelSettling) return
            if (menuRow.modelData.submenu === true) {
              card.host.enterMenuLevel(1)
              return
            }
            // Captures the target and closes; the dispatch itself runs once the
            // card has faded out and the focus grab is gone.
            card.host.requestMenuAction(menuRow.modelData.action, menuRow.modelData.workspaceId)
          }
        }
      }
    }
  }
}
