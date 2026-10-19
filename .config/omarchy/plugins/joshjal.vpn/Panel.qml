import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// joshjal.vpn -- one picker for every installed VPN backend.
Panel {
  id: root
  moduleName: "joshjal.vpn"
  ipcTarget: "joshjal.vpn"
  manageIpc: false

  property int cursorIndex: 0
  property bool cursorActive: false

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color barIconColor: vpn.anyActive ? barForeground : Qt.darker(barForeground, 1.55)
  readonly property color hoverFill: bar ? Style.hoverFillFor(bar.foreground, Commons.Color.accent) : "transparent"
  readonly property color selectedFill: bar ? Style.selectedFillFor(bar.foreground, Commons.Color.accent) : "transparent"
  readonly property string vpnGlyph: String.fromCodePoint(0xF0582)

  function selected() {
    if (vpn.flat.length === 0) return null
    return vpn.flat[Math.max(0, Math.min(cursorIndex, vpn.flat.length - 1))]
  }

  function ensureCursor() {
    if (cursorIndex >= vpn.flat.length) cursorIndex = Math.max(0, vpn.flat.length - 1)
  }

  function move(dy) {
    cursorActive = true
    cursorIndex = Math.max(0, Math.min(vpn.flat.length - 1, cursorIndex + dy))
    scrollIntoView()
  }

  function scrollIntoView() {
    Qt.callLater(function() {
      var item = rowAt(cursorIndex)
      if (!item) return
      var margin = Style.space(6)
      var top = item.mapToItem(flick.contentItem, 0, 0).y
      var bottom = top + item.height
      var maxY = Math.max(0, flick.contentHeight - flick.height)
      if (top < flick.contentY + margin) flick.contentY = Math.max(0, top - margin)
      else if (bottom > flick.contentY + flick.height - margin) flick.contentY = Math.min(maxY, bottom + margin - flick.height)
    })
  }

  function rowAt(flatIndex) {
    for (var g = 0; g < groupRepeater.count; g++) {
      var col = groupRepeater.itemAt(g)
      if (!col) continue
      for (var r = 0; r < col.rows.count; r++) {
        var row = col.rows.itemAt(r)
        if (row && row.entry && row.entry.flatIndex === flatIndex) return row
      }
    }
    return null
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursorActive = false
    flick.contentY = 0
    vpn.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Service {
    id: vpn
    settings: root.settings
    onFlatChanged: root.ensureCursor()
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { vpn.refresh(); return "ok" }
    function status(): string { return vpn.activeLabel }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        Text {
          anchors.centerIn: parent
          text: root.vpnGlyph
          color: root.barIconColor
          font.family: root.fontFamily
          font.pixelSize: Style.font.icon
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.MiddleButton) vpn.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(520))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dy !== 0) root.move(dy)
      }
      onActivateRequested: if (root.cursorActive) vpn.toggle(root.selected())
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "d" || t === "D") vpn.disconnect(root.selected())
        else if (t === "r" || t === "R") vpn.refresh()
      }

      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: flick.width
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: "VPN"
            meta: vpn.activeLabel
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: vpn.anyActive ? 1.0 : 0.5
            iconComponent: Component {
              Text {
                text: root.vpnGlyph
                color: vpn.anyActive ? root.foreground : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: vpn.actionStatus !== ""
            width: parent.width
            text: vpn.actionStatus
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Text {
            visible: vpn.groups.length === 0
            width: parent.width
            text: "No VPN backends found. Install NetworkManager, Tailscale, NordVPN or Mullvad and they appear here."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
          }

          Repeater {
            id: groupRepeater
            model: vpn.groups

            Column {
              id: group
              required property var modelData
              readonly property alias rows: rowRepeater
              width: column.width
              spacing: Style.space(10)

              PanelSeparator { foreground: root.foreground }

              PanelSectionHeader {
                text: group.modelData.label
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Text {
                textFormat: Text.PlainText
                visible: group.modelData.error !== ""
                width: parent.width
                text: group.modelData.error
                color: root.urgent
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
              }

              Text {
                visible: group.modelData.error === "" && group.modelData.entries.length === 0
                width: parent.width
                text: "Nothing to connect to."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                horizontalAlignment: Text.AlignHCenter
              }

              Column {
                width: parent.width
                spacing: Style.space(6)

                Repeater {
                  id: rowRepeater
                  model: group.modelData.entries

                  VpnRow {
                    required property var modelData
                    width: parent.width
                    entry: modelData
                  }
                }
              }
            }
          }

          Text {
            width: parent.width
            text: "enter connect  ·  d disconnect  ·  r refresh"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
          }
        }
      }
    }
  }

  component VpnRow: CursorSurface {
    id: row
    property var entry: null
    readonly property bool isActive: entry && entry.active === true

    hasCursor: root.cursorActive && entry && root.cursorIndex === entry.flatIndex
    current: isActive
    foreground: root.foreground
    fill: root.hoverFill
    currentFill: root.selectedFill
    implicitHeight: inner.implicitHeight + Style.spacing.xl

    RowLayout {
      id: inner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(8)

      Text {
        text: row.isActive ? String.fromCodePoint(0xF012C) : String.fromCodePoint(0xF0130)
        color: row.isActive ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        Layout.preferredWidth: Style.space(22)
        horizontalAlignment: Text.AlignHCenter
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: row.entry ? row.entry.name : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: row.isActive
          elide: Text.ElideRight
        }

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          visible: text !== ""
          text: row.entry ? row.entry.detail : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: { root.cursorActive = true; if (row.entry) root.cursorIndex = row.entry.flatIndex }
      onClicked: vpn.toggle(row.entry)
    }
  }
}
