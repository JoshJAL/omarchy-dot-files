import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "WindowModel.js" as WindowModel
import "Dispatch.js" as Dispatch

// joshjal.taskbar -- one button per open window on THIS monitor.
//
// A bar surface exists per monitor (Bar.qml: Variants { model: Quickshell.screens }),
// so this widget is constructed once per screen and must filter to its own.
BarWidget {
  id: root
  moduleName: "joshjal.taskbar"

  // ---- settings (manifest `defaults` are documentation-only in this build, so
  // every fallback is restated here). Read as bindings: the bar reassigns
  // `settings` wholesale when shell.json changes (Bar.qml applySettingsDelta).
  readonly property int iconSize: Number(root.setting("iconSize", 14))
  readonly property int iconSizeMin: Number(root.setting("iconSizeMin", 10))
  readonly property bool includeSpecial: root.setting("includeSpecial", false) === true
  readonly property int maxIcons: Number(root.setting("maxIcons", 0))
  readonly property int previewDelay: Number(root.setting("previewDelay", 320))
  readonly property int previewWidth: Number(root.setting("previewWidth", 320))
  readonly property int previewHeight: Number(root.setting("previewHeight", 200))
  readonly property var classIconOverrides: root.setting("classIconOverrides", ({}))
  readonly property bool previewsEnabled: root.previewDelay >= 0

  // Invalidates the `windows` binding for churn that doesn't change the
  // identity of Hyprland.toplevels.values. Only ever bumped from a timer.
  property int modelRevision: 0

  readonly property var qsScreen: root.QsWindow.window ? root.QsWindow.window.screen : null

  // Plain properties, never a binding.
  //
  // Hyprland.monitorFor() reaches into Quickshell's live Hyprland state. Called
  // from a BINDING, it re-evaluates whenever a dependency changes -- including
  // from inside the IPC event handler, i.e. while Quickshell is still parsing
  // the very event that triggered it. That re-entrancy segfaulted the whole
  // shell (Qt::endPropertyUpdateGroup under QAbstractSocket::canReadNotification),
  // and a crash-looping shell takes the bar, the wallpaper and every popup with
  // it. So the monitor is resolved only from timers and onCompleted, never
  // reactively.
  property int monitorId: -1
  property string monitorName: ""

  function resolveMonitor() {
    var m = root.qsScreen ? Hyprland.monitorFor(root.qsScreen) : null
    root.monitorId = m ? m.id : -1
    root.monitorName = m ? String(m.name || "") : ""
  }

  // address -> first-seen sequence, so icons keep their slot when Hyprland
  // reorders its client list. Mutated in place on purpose: invalidation is
  // driven by modelRevision, not by reassigning this object.
  property var orderSeq: ({})
  property int orderNext: 0

  readonly property var windows: {
    var dep = root.modelRevision
    var values = Hyprland.toplevels.values
    return WindowModel.forMonitor(values, root.monitorId, root.includeSpecial, root.orderSeq)
  }

  // Icons shrink as the count grows, down to a floor; past that the row is
  // capped and the remainder goes behind a "+N" chip (phase 7).
  readonly property int effectiveIconSize: {
    var n = root.windows.length
    if (n <= 8) return root.iconSize
    var shrunk = Math.round(root.iconSize - (n - 8) * 0.5)
    return Math.max(root.iconSizeMin, shrunk)
  }

  function ensureOrder(values) {
    var seen = {}
    for (var i = 0; i < values.length; i++) {
      var tl = values[i]
      if (!tl || !tl.address) continue
      var addr = String(tl.address)
      seen[addr] = true
      if (root.orderSeq[addr] === undefined) root.orderSeq[addr] = root.orderNext++
    }
    // Drop bookkeeping for windows that are gone.
    for (var key in root.orderSeq) if (!seen[key]) delete root.orderSeq[key]
  }

  function refresh() {
    var values = Hyprland.toplevels.values
    root.ensureOrder(values)
    // Some toplevels arrive before their Hyprland IPC blob does, leaving them
    // with no monitor or workspace. They would be dropped from every bar, so
    // ask for a refresh rather than lose them. Guarded against looping: the
    // retry only fires while something is actually still unplaced.
    if (WindowModel.pendingCount(values) > 0) pendingRetry.restart()
    root.modelRevision++
  }

  // ---- actions.
  // Hyprland.dispatch() goes down the IPC socket directly: no shell, no
  // quoting. Every form here was validated against this Hyprland (0.56.2)
  // before being wired up.
  function focusWindow(entry) {
    if (!entry) return
    Hyprland.dispatch(Dispatch.focusWindow(entry.address))
  }

  function closeWindow(entry) {
    if (!entry) return
    Hyprland.dispatch(Dispatch.closeWindow(entry.address))
  }

  function toggleFloating(entry) {
    if (!entry) return
    Hyprland.dispatch(Dispatch.toggleFloating(entry.address))
  }

  function moveToWorkspace(entry, workspaceId) {
    if (!entry) return
    Hyprland.dispatch(Dispatch.moveToWorkspace(entry.address, workspaceId, false))
  }

  function moveToMonitor(entry, target) {
    if (!entry || !target) return
    Hyprland.dispatch(Dispatch.moveToWorkspace(entry.address, target.workspaceId, false))
  }

  // Computed on demand (when the menu opens), not bound -- same re-entrancy
  // rule as resolveMonitor().
  function otherMonitors() {
    return Dispatch.otherMonitors(Hyprland.monitors.values, root.monitorId)
  }

  // ---- hover preview state machine.
  //
  // The hovered window is tracked by ADDRESS and the entry is derived from the
  // live model, never stored. Storing it meant writing back into `windows`
  // from inside onWindowsChanged to keep the caption fresh, which QML flagged
  // as a binding loop. Deriving it also makes the "window closed while its
  // preview was open" case fall out for free: the lookup returns null and the
  // card's `open` binding goes false on its own.
  property var hoverTarget: null
  property string hoverAddress: ""
  property var pendingTarget: null
  property string pendingAddress: ""
  property bool previewOpen: false
  property bool menuOpen: false

  readonly property var hoverEntry: {
    if (!root.hoverAddress) return null
    var list = root.windows
    for (var i = 0; i < list.length; i++) if (list[i].address === root.hoverAddress) return list[i]
    return null
  }

  function requestPreview(button, entry) {
    if (!root.previewsEnabled || root.menuOpen || !entry) return
    if (root.previewOpen) {
      // Already showing: slide straight to the new window, no second delay.
      root.hoverTarget = button
      root.hoverAddress = entry.address
      return
    }
    root.pendingTarget = button
    root.pendingAddress = entry.address
    hoverTimer.restart()
  }

  function cancelPreview(button) {
    if (root.pendingTarget === button) {
      root.pendingTarget = null
      root.pendingAddress = ""
      hoverTimer.stop()
    }
    if (root.hoverTarget === button) closeTimer.restart()
  }

  function closePreview() {
    root.previewOpen = false
    root.hoverTarget = null
    root.hoverAddress = ""
  }

  // Still-hovered means: the pointer is on the button, or it has travelled
  // into the card itself.
  function previewStillWanted() {
    if (preview.containsMouse) return true
    return root.hoverTarget !== null && root.hoverTarget.tooltipHovered === true
  }

  function openMenu(button, entry) {}

  Timer {
    id: hoverTimer
    interval: Math.max(0, root.previewDelay)
    onTriggered: {
      if (!root.pendingTarget || root.pendingTarget.tooltipHovered !== true) {
        root.pendingTarget = null
        root.pendingAddress = ""
        return
      }
      root.hoverTarget = root.pendingTarget
      root.hoverAddress = root.pendingAddress
      root.pendingTarget = null
      root.pendingAddress = ""
      root.previewOpen = true
    }
  }

  // Grace period so the pointer can cross the gap from button to card without
  // the card vanishing underneath it.
  Timer {
    id: closeTimer
    interval: 160
    onTriggered: if (!root.previewStillWanted()) root.closePreview()
  }

  // Wayland drops leave events when a surface appears under the cursor, so a
  // poll is the only reliable way to notice the pointer has gone. Bar.qml
  // carries the same watchdog for its own tooltips.
  Timer {
    interval: 120
    repeat: true
    running: root.previewOpen
    onTriggered: if (!root.previewStillWanted()) closeTimer.restart()
  }

  implicitWidth: root.vertical ? root.barSize : layout.implicitWidth
  implicitHeight: root.vertical ? layout.implicitHeight : root.barSize
  visible: root.windows.length > 0

  Component.onCompleted: { root.resolveMonitor(); root.refresh() }
  // Deferred through the coalesce timer: bumping modelRevision straight from
  // a change handler that `windows` depends on is a binding loop.
  onQsScreenChanged: coalesce.restart()
  onMonitorIdChanged: coalesce.restart()

  // Set by onRawEvent, acted on by the coalesce timer. The handler itself must
  // never touch Hyprland state or any property a binding reacts to.
  property bool topologyDirty: false
  property bool needsToplevelRefresh: false

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      switch (String(event.name)) {
      case "monitoradded":
      case "monitoraddedv2":
      case "monitorremoved":
      case "monitorremovedv2":
      case "focusedmon":
      case "focusedmonv2":
        root.topologyDirty = true
        coalesce.restart()
        break
      case "changefloatingmode":
        // Quickshell's own toplevel-refresh event set omits this one, so
        // lastIpcObject.floating goes stale after a float toggle. The refresh
        // is deferred rather than called here: refreshToplevels() from inside
        // the event handler is the same re-entrancy that crashed the shell.
        root.needsToplevelRefresh = true
        coalesce.restart()
        break
      case "openwindow":
      case "closewindow":
      case "movewindowv2":
      case "workspace":
      case "workspacev2":
      case "activewindowv2":
      case "windowtitlev2":
      case "urgent":
      case "fullscreen":
      case "moveworkspace":
      case "moveworkspacev2":
        coalesce.restart()
        break
      }
    }
  }

  Connections {
    target: Hyprland.toplevels
    function onValuesChanged() { coalesce.restart() }
  }

  // Hyprland emits bursts (openwindow + activewindowv2 + workspace within the
  // same millisecond); rebuilding once per burst keeps the model cheap.
  Timer {
    id: coalesce
    interval: 40
    onTriggered: {
      // Everything that touches Hyprland state happens here, on the event
      // loop, never inside the IPC read callstack.
      if (root.needsToplevelRefresh) {
        root.needsToplevelRefresh = false
        Hyprland.refreshToplevels()
      }
      if (root.topologyDirty || root.monitorId < 0) {
        root.topologyDirty = false
        root.resolveMonitor()
      }
      root.refresh()
    }
  }

  Timer {
    id: pendingRetry
    interval: 200
    onTriggered: {
      Hyprland.refreshToplevels()
      Qt.callLater(function () {
        root.ensureOrder(Hyprland.toplevels.values)
        root.modelRevision++
      })
    }
  }

  PreviewBarShim {
    id: previewBar
    source: root.bar
  }

  PreviewCard {
    id: preview
    host: root
    entry: root.hoverEntry
    // Anchoring to one of our own buttons is what keeps the card on the right
    // screen: PopupCard derives popupScreen from anchorItem.QsWindow.window.
    anchorItem: root.hoverTarget ? root.hoverTarget : root
    bar: previewBar
    owner: preview
    open: root.previewOpen && root.hoverTarget !== null && root.hoverEntry !== null
  }

  GridLayout {
    id: layout
    anchors.fill: parent
    columns: root.vertical ? 1 : Math.max(1, root.windows.length)
    columnSpacing: 0
    rowSpacing: 0

    Repeater {
      model: root.windows

      TaskButton {
        required property var modelData
        bar: root.bar
        host: root
        entry: modelData
        iconPixelSize: root.effectiveIconSize
      }
    }
  }
}
