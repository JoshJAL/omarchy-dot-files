import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Hover preview: a live capture of the window, with an icon card underneath.
//
// The spike settled the hard question -- Hyprland's toplevel export re-renders
// the window rather than reading back the monitor, so a window sitting on a
// hidden workspace still captures. Both Slack and Chromium reported
// hasContent=true at full source size while their workspace was not on screen.
// That removed the whole snapshot-cache tier this was originally going to need.
PopupCard {
  id: card

  property var host: null
  property var entry: null

  readonly property string title: card.entry ? card.entry.title : ""
  readonly property string appClass: card.entry ? card.entry.appClass : ""
  readonly property int workspaceId: card.entry ? card.entry.workspaceId : 0

  // Set by the host, not derived from `entry`. The toplevel is deliberately
  // kept out of the ListModel (a QObject in a model role becomes a dangling
  // pointer and segfaults QQmlListModel::data), and the host hands it over via
  // a guarded plain property so captureSource is not rewritten -- and the
  // capture session torn down and restarted -- on every event burst.
  property var toplevel: null
  readonly property var waylandHandle: card.toplevel ? card.toplevel.wayland : null

  triggerMode: "hover"

  // previewWidth/previewHeight are plain pixels, so they are NOT passed through
  // Style.space() -- that multiplies by the spacing scale and would size the
  // card twice. fittedContentWidth still clamps to the screen.
  readonly property int stageWidth: card.host ? card.host.previewWidth : 320
  readonly property int stageMaxHeight: card.host ? card.host.previewHeight : 200

  contentWidth: card.fittedContentWidth(card.stageWidth)
  contentHeight: card.fittedContentHeight(column.implicitHeight)

  Column {
    id: column
    width: parent ? parent.width : card.stageWidth
    spacing: Style.space(6)

    // ---- the picture
    Item {
      id: stage
      width: parent.width
      // Track the real window aspect so a 3440x1440 ultrawide doesn't get
      // squashed into 16:9. Falls back to 16:10 before the first frame lands.
      readonly property real aspect: liveLoader.item && liveLoader.item.sourceSize
        && liveLoader.item.sourceSize.height > 0
        ? liveLoader.item.sourceSize.width / liveLoader.item.sourceSize.height
        : 1.6
      // Clamped, so a tall or portrait window (Slack at 1701x1390, a phone-shaped
      // dev tools pane) cannot stretch the card down the whole screen. The
      // capture is letterboxed inside rather than stretched to fill.
      height: Math.round(Math.min(width / Math.max(0.2, stage.aspect), card.stageMaxHeight))
      clip: true

      Rectangle {
        anchors.fill: parent
        color: Color.popups.background !== undefined ? Color.popups.background : Color.background
        radius: Style.space(4)
      }

      // ---- fallback tier: always present, underneath. A window that cannot
      // be captured at all still reads as itself rather than as a blank box.
      Column {
        anchors.centerIn: parent
        spacing: Style.space(6)
        opacity: liveLoader.item && liveLoader.item.hasContent ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: 120 } }

        WindowIcon {
          anchors.horizontalCenter: parent.horizontalCenter
          appClass: card.appClass
          appLibrary: card.host && card.host.bar && card.host.bar.shell
            ? card.host.bar.shell.appLibrary : null
          overrides: card.host ? card.host.classIconOverrides : ({})
          size: Style.space(48)
          tint: Color.foreground
        }
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: card.appClass
          color: Color.foreground
          opacity: 0.7
          font.pixelSize: Style.font.caption
          textFormat: Text.PlainText
        }
      }

      // ---- live tier. Loader.active is load-bearing: it tears the screencopy
      // session down the moment the card closes, so capture only ever runs
      // while the preview is actually on screen.
      Loader {
        id: liveLoader
        anchors.centerIn: parent
        // Letterbox: fit the real window aspect inside the clamped stage
        // instead of anchors.fill, which would stretch it.
        width: Math.min(stage.width, stage.height * Math.max(0.2, stage.aspect))
        height: Math.min(stage.height, stage.width / Math.max(0.2, stage.aspect))
        active: card.open && card.waylandHandle !== null
        sourceComponent: Component {
          ScreencopyView {
            captureSource: card.waylandHandle
            live: true
            paintCursor: false
            opacity: hasContent ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 120 } }
          }
        }
      }
    }

    // ---- caption. Always driven by the live entry, even when the picture
    // is a fallback, so the title and workspace are never stale.
    Row {
      width: parent.width
      spacing: Style.space(6)

      WindowIcon {
        anchors.verticalCenter: parent.verticalCenter
        appClass: card.appClass
        appLibrary: card.host && card.host.bar && card.host.bar.shell
          ? card.host.bar.shell.appLibrary : null
        overrides: card.host ? card.host.classIconOverrides : ({})
        size: Style.space(16)
        tint: Color.foreground
      }

      Column {
        width: parent.width - Style.space(22)
        spacing: 0

        Text {
          width: parent.width
          text: card.title
          color: Color.foreground
          elide: Text.ElideRight
          maximumLineCount: 1
          font.pixelSize: Style.font.body
          textFormat: Text.PlainText
        }
        Text {
          width: parent.width
          text: "Workspace " + card.workspaceId
          color: Color.foreground
          opacity: 0.6
          elide: Text.ElideRight
          font.pixelSize: Style.font.caption
          textFormat: Text.PlainText
        }
      }
    }
  }
}
