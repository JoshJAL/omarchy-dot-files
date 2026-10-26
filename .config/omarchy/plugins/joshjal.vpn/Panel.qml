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
  // Section ids the user has expanded. Empty on every open = all collapsed.
  property var openGroups: ({})

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color barIconColor: vpn.anyActive ? barForeground : Qt.darker(barForeground, 1.55)
  readonly property color hoverFill: bar ? Style.hoverFillFor(bar.foreground, Commons.Color.accent) : "transparent"
  readonly property color selectedFill: bar ? Style.selectedFillFor(bar.foreground, Commons.Color.accent) : "transparent"
  readonly property string vpnGlyph: String.fromCodePoint(0xF0582)

  readonly property string query: search.text.trim().toLowerCase()
  // What the list shows: backend groups at the top level, or one group of
  // cities while drilled into a country. Both honour the search box.
  readonly property var viewGroups: buildView(vpn.groups, vpn.drilling, vpn.drillEntries, vpn.drillTitle, vpn.drillError, query, openGroups)
  readonly property var viewFlat: {
    var out = []
    for (var i = 0; i < viewGroups.length; i++) out = out.concat(viewGroups[i].entries)
    return out
  }
  readonly property string drillTitle: vpn.drillTitle

  function toggleGroup(id) {
    var next = {}
    for (var k in openGroups) next[k] = openGroups[k]
    next[id] = !openGroups[id]
    openGroups = next
  }

  function buildView(groups, drilling, drillEntries, drillCountry, drillError, q, open) {
    var src = drilling
      ? [{ id: "drill", label: drillCountry.toUpperCase(), entries: drillEntries, error: drillError }]
      : groups
    var out = []
    var n = 0
    for (var i = 0; i < src.length; i++) {
      // Sections collapse only at the top level with no search; a search or a
      // drill-down always shows rows.
      var collapsible = !drilling && q === ""
      var collapsed = collapsible && open[src[i].id] !== true
      var header = null
      if (collapsible) header = { kind: "header", groupId: src[i].id, name: src[i].label, flatIndex: n++ }
      var summary = []
      var conn = []
      var entries = []
      for (var j = 0; j < src[i].entries.length; j++) {
        var e = {}
        for (var k in src[i].entries[j]) e[k] = src[i].entries[j][k]
        if (e.active) { summary.push(e); if (e.kind === "connection") conn.push(e) }
        if (collapsed) continue
        if (q !== "" && e.name.toLowerCase().indexOf(q) === -1) continue
        e.flatIndex = n++
        entries.push(e)
      }
      if (q !== "" && entries.length === 0 && !drilling) continue
      var shown = conn.length > 0 ? conn : summary
      out.push({
        id: src[i].id, label: src[i].label, entries: entries, error: src[i].error,
        header: header, collapsed: collapsed, total: src[i].entries.length,
        summary: shown.map(function (x) { return x.brief || x.name }).join(", ")
      })
    }
    return out
  }

  function selected() {
    if (viewFlat.length === 0) return null
    return viewFlat[Math.max(0, Math.min(cursorIndex, viewFlat.length - 1))]
  }

  function ensureCursor() {
    if (cursorIndex >= viewFlat.length) cursorIndex = Math.max(0, viewFlat.length - 1)
  }

  function move(dy) {
    cursorActive = true
    cursorIndex = Math.max(0, Math.min(viewFlat.length - 1, cursorIndex + dy))
    scrollIntoView()
  }

  function activate(entry) {
    if (!entry) return
    if (entry.kind === "header") { toggleGroup(entry.groupId); return }
    if (entry.drillable === true) {
      search.text = ""
      cursorIndex = 0
      vpn.openCountry(entry)
      flick.contentY = 0
    } else {
      vpn.toggle(entry)
    }
  }

  function goBack() {
    vpn.back()
    search.text = ""
    cursorIndex = 0
    flick.contentY = 0
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
      if (col.headerRow.entry && col.headerRow.entry.flatIndex === flatIndex) return col.headerRow
      for (var r = 0; r < col.rows.count; r++) {
        var row = col.rows.itemAt(r)
        if (row && row.entry && row.entry.flatIndex === flatIndex) return row
      }
    }
    return null
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onViewFlatChanged: ensureCursor()

  onOpenedChanged: if (opened) {
    cursorActive = false
    cursorIndex = 0
    openGroups = ({})
    flick.contentY = 0
    vpn.back()
    search.text = ""
    vpn.refresh()
    Qt.callLater(function() { search.forceActiveFocus() })
  }

  Service {
    id: vpn
    settings: root.settings
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
    focusTarget: search
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(520))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // The search field owns the keyboard while focused; it forwards the
      // navigation keys itself (see search.Keys.onPressed).
      blocked: search.activeFocus
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dy !== 0) root.move(dy)
      }
      onActivateRequested: if (root.cursorActive) root.activate(root.selected())
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) { search.forceActiveFocus(); search.text = search.text + t }

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

          MouseArea {
            visible: vpn.drilling
            width: parent.width
            height: visible ? backLabel.implicitHeight + Style.space(6) : 0
            cursorShape: Qt.PointingHandCursor
            onClicked: { root.goBack(); search.forceActiveFocus() }

            Text {
              id: backLabel
              anchors.verticalCenter: parent.verticalCenter
              text: "\u2039 " + root.drillTitle
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }
          }

          TextField {
            id: search
            width: parent.width
            foreground: root.foreground
            placeholderText: vpn.drilling ? "Search cities" : "Search countries"
            onTextChanged: { root.cursorIndex = 0; root.cursorActive = text !== "" || root.cursorActive; flick.contentY = 0 }

            Keys.priority: Keys.BeforeItem
            Keys.onPressed: function(event) {
              var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
              if (event.key === Qt.Key_Escape) {
                if (search.text !== "") search.text = ""
                else if (vpn.drilling) root.goBack()
                else root.close()
                event.accepted = true
              } else if (event.key === Qt.Key_Backspace && search.text === "" && vpn.drilling) {
                root.goBack()
                event.accepted = true
              } else if (event.key === Qt.Key_Down) {
                root.move(1); event.accepted = true
              } else if (event.key === Qt.Key_Up) {
                root.move(-1); event.accepted = true
              } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                if (!root.cursorActive) root.cursorActive = true
                root.activate(root.selected())
                event.accepted = true
              } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                root.switchPanel((event.modifiers & Qt.ShiftModifier) || event.key === Qt.Key_Backtab ? -1 : 1)
                event.accepted = true
              } else if (ctrl && event.key === Qt.Key_D) {
                vpn.disconnect(root.selected()); event.accepted = true
              } else if (ctrl && event.key === Qt.Key_R) {
                vpn.refresh(); event.accepted = true
              }
            }
          }

          Text {
            visible: vpn.busy
            width: parent.width
            text: "Connecting\u2026"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
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
            model: root.viewGroups

            Column {
              id: group
              required property var modelData
              readonly property alias rows: rowRepeater
              readonly property alias headerRow: hdr
              width: column.width
              spacing: Style.space(10)

              PanelSeparator { foreground: root.foreground }

              GroupHeader {
                id: hdr
                width: parent.width
                entry: group.modelData.header
                label: group.modelData.label
                collapsible: group.modelData.header !== null
                collapsed: group.modelData.collapsed
                summary: group.modelData.collapsed ? group.modelData.summary : ""
                total: group.modelData.total
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
                visible: !group.modelData.collapsed && group.modelData.error === "" && group.modelData.entries.length === 0
                width: parent.width
                text: vpn.drilling && vpn.drillLoading ? "Loading cities\u2026" : (root.query !== "" ? "No matches." : "Nothing to connect to.")
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
            text: vpn.drilling ? "enter connect  ·  esc back  ·  ctrl+d disconnect" : "enter select  ·  esc close  ·  ctrl+d disconnect  ·  ctrl+r refresh"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
          }
        }
      }
    }
  }

  component GroupHeader: CursorSurface {
    id: gh
    property var entry: null
    property string label: ""
    property bool collapsible: false
    property bool collapsed: false
    property string summary: ""
    property int total: 0

    hasCursor: collapsible && root.cursorActive && entry && root.cursorIndex === entry.flatIndex
    foreground: root.foreground
    fill: root.hoverFill
    currentFill: root.selectedFill
    implicitHeight: ghRow.implicitHeight + Style.spacing.xl

    RowLayout {
      id: ghRow
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(8)

      Text {
        visible: gh.collapsible
        text: gh.collapsed ? "\u25B8" : "\u25BE"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        Layout.preferredWidth: Style.space(14)
      }

      PanelSectionHeader {
        text: gh.label
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      Text {
        textFormat: Text.PlainText
        Layout.fillWidth: true
        visible: text !== ""
        text: gh.summary !== "" ? "\u00B7 " + gh.summary : (gh.collapsed && gh.total > 0 ? "\u00B7 " + gh.total : "")
        color: gh.summary !== "" ? Commons.Color.accent : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      Item { Layout.fillWidth: !gh.summary && !(gh.collapsed && gh.total > 0) }
    }

    MouseArea {
      anchors.fill: parent
      enabled: gh.collapsible
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: { root.cursorActive = true; if (gh.entry) root.cursorIndex = gh.entry.flatIndex }
      onClicked: root.activate(gh.entry)
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
        color: row.isActive ? Commons.Color.accent : root.dim
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
      onClicked: root.activate(row.entry)
    }
  }
}
