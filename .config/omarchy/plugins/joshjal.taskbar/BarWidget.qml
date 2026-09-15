import QtQuick
import QtQuick.Layouts
import QtQml.Models
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "WindowModel.js" as WindowModel
import "MenuModel.js" as MenuModel
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
  readonly property bool allOutputs: root.setting("allOutputs", false) === true
  readonly property string sortBy: String(root.setting("sortBy", "workspace"))
  readonly property int maxIcons: Number(root.setting("maxIcons", 0))
  readonly property int previewDelay: Number(root.setting("previewDelay", 320))
  readonly property int previewWidth: Number(root.setting("previewWidth", 320))
  readonly property int previewHeight: Number(root.setting("previewHeight", 200))
  readonly property var classIconOverrides: root.setting("classIconOverrides", ({}))
  readonly property bool previewsEnabled: root.previewDelay >= 0

  // Inactive windows read back by default. `!== false` rather than `=== true`
  // so the default stays on when the key is absent.
  readonly property bool dimInactive: root.setting("dimInactive", true) !== false
  readonly property bool showTitles: root.setting("showTitles", false) === true
  readonly property int maxTitleWidth: Number(root.setting("maxTitleWidth", 140))

  // Click actions: "focus", "close", "bring", "none", plus "menu" on right.
  // Defaults reproduce the hardcoded behavior these settings replaced, so an
  // untouched shell.json behaves exactly as before.
  readonly property string middleClick: String(root.setting("middleClick", "close"))
  readonly property string rightClick: String(root.setting("rightClick", "menu"))

  // Settings that decide WHICH rows exist, rather than how a row looks, are
  // read imperatively inside refresh() -- so changing one in shell.json moves
  // nothing until the next Hyprland event happens to rebuild the model. That
  // made allOutputs look like it did nothing when toggled back off: the list
  // simply kept whatever the last event left behind. Rebuild explicitly.
  //
  // callLater, not a direct call: a settings delta can land mid-event, and
  // refresh() must not re-enter from inside onRawEvent.
  onAllOutputsChanged: Qt.callLater(root.refresh)
  onIncludeSpecialChanged: Qt.callLater(root.refresh)
  onSortByChanged: Qt.callLater(root.refresh)

  // ---- the model.
  //
  // A ListModel, not a JS array, so delegates persist. Assigning a fresh array
  // to a Repeater destroys and recreates EVERY delegate, and the events that
  // drive a rebuild include windowtitlev2 -- which fires every time a terminal
  // changes its title. That churn reloaded every icon and broke hover identity.
  //
  // Roles are primitives only. A HyprlandToplevel in a model role becomes a
  // dangling pointer and segfaults QQmlListModel::data; see WindowModel.row().
  ListModel { id: windowModel }
  readonly property int windowCount: windowModel.count

  // Bumped only when a sync actually changed something, so a no-op sync wakes
  // no bindings.
  property int modelRevision: 0

  // address -> live HyprlandToplevel, for the one consumer that needs the real
  // object (the preview's capture source). Deliberately off the model.
  property var toplevelByAddress: ({})

  // Churn probe. If this climbs while windows are merely changing title, the
  // incremental sync has regressed. Surfaced in the sandbox harness.
  property int delegateCreations: 0

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
  // reorders its client list. Mutated in place on purpose.
  property var orderSeq: ({})
  property int orderNext: 0

  function ensureOrder(values) {
    var seen = {}
    for (var i = 0; i < values.length; i++) {
      var tl = values[i]
      if (!tl || !tl.address) continue
      var addr = String(tl.address)
      seen[addr] = true
      if (root.orderSeq[addr] === undefined) root.orderSeq[addr] = root.orderNext++
    }
    for (var key in root.orderSeq) if (!seen[key]) delete root.orderSeq[key]
  }

  // Index -> address, for the sandbox harness (no pointer synthesis is
  // available on this machine, so clicks are driven through the API).
  function addressAt(i) {
    return (i >= 0 && i < windowModel.count) ? windowModel.get(i).address : ""
  }

  function entryFor(address) {
    for (var i = 0; i < windowModel.count; i++) {
      var r = windowModel.get(i)
      if (r.address === address) return r
    }
    return null
  }

  function refresh() {
    var values = Hyprland.toplevels.values
    root.ensureOrder(values)
    // Toplevels can arrive before their Hyprland IPC blob does, leaving them
    // with no monitor or workspace. They would be dropped from every bar, so
    // ask for a refresh rather than lose them. The retry only fires while
    // something is actually still unplaced, so it cannot spin.
    if (WindowModel.pendingCount(values) > 0) pendingRetry.restart()

    root.toplevelByAddress = WindowModel.toplevelMap(values)

    var next = WindowModel.forMonitor(values, root.monitorId, {
      includeSpecial: root.includeSpecial,
      allOutputs: root.allOutputs,
      sortBy: root.sortBy,
      orderSeq: root.orderSeq
    })
    if (WindowModel.syncModel(windowModel, next)) root.modelRevision++

    root.syncHoverToplevel()
    root.reconcileAfterSync()
  }

  // Delegate persistence means nothing clears stale state for us any more, so
  // every address we are holding on to is re-checked against the live model.
  function reconcileAfterSync() {
    if (root.hoverAddress && !root.toplevelByAddress[root.hoverAddress]) root.closePreview()
    if (root.pendingAddress && !root.toplevelByAddress[root.pendingAddress]) {
      root.pendingTarget = null
      root.pendingAddress = ""
      hoverTimer.stop()
    }
    if (root.previewSuppressedAddress && !root.toplevelByAddress[root.previewSuppressedAddress])
      root.previewSuppressedAddress = ""
    if (root.menuOpen && root.menuAddress && !root.toplevelByAddress[root.menuAddress]) root.close()
    if (root.overflowOpen && root.overflowCount <= 0) root.overflowOpen = false
  }

  // ---- sizing.
  //
  // Icons shrink as the count grows. slotSize has to shrink with them:
  // BarIconButton.fixedWidth is slotSize, independent of the drawn glyph, so
  // shrinking the icon alone narrows nothing and the row stays the same width.
  readonly property int effectiveIconSize: {
    var n = root.windowCount
    if (n <= 8) return root.iconSize
    return Math.max(root.iconSizeMin, Math.round(root.iconSize - (n - 8) * 0.5))
  }
  readonly property int effectiveSlotSize:
    Math.max(root.iconSizeMin + Style.space(6),
             Style.bar.iconSlot - (root.iconSize - root.effectiveIconSize))

  // maxIcons is a count the user sets; 0 = unlimited. A plugin cannot measure
  // the room it has -- ModuleSlot asks the widget for its implicitWidth, so the
  // constraint only ever flows upward, and PluginBarApi carries no geometry.
  readonly property int visibleCount: {
    var n = root.windowCount
    if (root.maxIcons <= 0 || n <= root.maxIcons) return n
    return Math.max(1, root.maxIcons)
  }
  readonly property int overflowCount: Math.max(0, root.windowCount - root.visibleCount)

  // ---- actions. All keyed by address.
  // Hyprland.dispatch() goes down the IPC socket directly: no shell, no
  // quoting. Every form was validated against this Hyprland (0.56.2).
  function focusWindow(address) {
    if (address) Hyprland.dispatch(Dispatch.focusWindow(address))
  }
  function closeWindow(address) {
    if (address) Hyprland.dispatch(Dispatch.closeWindow(address))
  }

  // "Bring" pulls the window onto the workspace you are already looking at,
  // instead of jumping you to wherever it lives. follow=false because the
  // destination IS the current workspace -- following would be a no-op at best.
  function bringWindow(address) {
    if (!address) return
    var ws = root.activeWorkspaceId()
    if (ws !== null) Hyprland.dispatch(Dispatch.moveToWorkspace(address, ws, false))
    Hyprland.dispatch(Dispatch.focusWindow(address))
  }

  // This bar's own monitor decides where "here" is. One widget instance exists
  // per screen, so the taskbar that was clicked names the destination; a global
  // focused-workspace lookup would send windows to the wrong screen whenever
  // you click a bar that isn't the focused one.
  function activeWorkspaceId() {
    var ms = Hyprland.monitors ? Hyprland.monitors.values : []
    for (var i = 0; i < ms.length; i++) {
      var m = ms[i]
      if (!m || Number(m.id) !== Number(root.monitorId)) continue
      if (m.activeWorkspace && m.activeWorkspace.id !== undefined) return Number(m.activeWorkspace.id)
    }
    return null
  }

  // Single dispatch point for both click sites -- the bar buttons and the
  // overflow rows -- so a remapped button behaves identically in each. Unknown
  // values fall through to focus rather than doing nothing, so a typo in
  // shell.json degrades to the ordinary click instead of a dead icon.
  function runClickAction(kind, anchor, address) {
    if (!address) return
    switch (String(kind)) {
    case "none": return
    case "close": root.closeWindow(address); return
    case "bring": root.bringWindow(address); return
    case "menu": root.openMenu(anchor, address); return
    case "focus":
    default: root.focusWindow(address); return
    }
  }

  // Computed on demand, never bound -- same re-entrancy rule as resolveMonitor().
  // Safe here because it runs in a user-input callstack, not onRawEvent.
  function otherMonitors() {
    return Dispatch.otherMonitors(Hyprland.monitors.values, root.monitorId)
  }

  // ---- hover preview state machine.
  property var hoverTarget: null
  property string hoverAddress: ""
  property var pendingTarget: null
  property string pendingAddress: ""
  property bool previewOpen: false

  // Set on click so the preview cannot immediately re-latch while the pointer
  // is still sitting on the icon it just clicked.
  property string previewSuppressedAddress: ""

  readonly property var hoverEntry: {
    var dep = root.modelRevision
    if (!root.hoverAddress) return null
    return root.entryFor(root.hoverAddress)
  }

  // Guarded plain property, not a binding: a binding would rewrite
  // ScreencopyView.captureSource on every 40ms event burst, tearing the capture
  // session down and restarting it while the user is looking at it.
  property var hoverToplevel: null
  function syncHoverToplevel() {
    var tl = root.hoverAddress ? (root.toplevelByAddress[root.hoverAddress] || null) : null
    if (root.hoverToplevel !== tl) root.hoverToplevel = tl
  }
  onHoverAddressChanged: root.syncHoverToplevel()

  function requestPreview(button, address) {
    if (!root.previewsEnabled || root.menuOpen || !address) return
    if (address === root.previewSuppressedAddress) return
    root.previewSuppressedAddress = ""
    if (root.previewOpen) {
      // Already showing: slide straight to the new window, no second delay.
      root.hoverTarget = button
      root.hoverAddress = address
      return
    }
    root.pendingTarget = button
    root.pendingAddress = address
    hoverTimer.restart()
  }

  function cancelPreview(button, address) {
    if (address && address === root.previewSuppressedAddress) root.previewSuppressedAddress = ""
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

  // Called first on every click, before the action. Without this the card
  // survives the click: previewStillWanted() stays true while the pointer is on
  // the button, and any resulting model change used to re-target it instantly.
  function dismissPreviewForClick(address) {
    root.previewSuppressedAddress = String(address || "")
    hoverTimer.stop()
    closeTimer.stop()
    root.pendingTarget = null
    root.pendingAddress = ""
    root.closePreview()
    if (root.previewSuppressedAddress) suppressionWatchdog.restart()
  }

  function previewStillWanted() {
    if (preview.containsMouse) return true
    return root.hoverTarget !== null && root.hoverTarget.tooltipHovered === true
  }

  // ---- context menu state. Everything is snapshotted when the menu opens so
  // the rows cannot mutate under a stationary cursor mid-interaction.
  property bool menuOpen: false
  property var menuAnchor: null
  property string menuAddress: ""
  property string menuTitle: ""
  property int menuWorkspaceId: 0
  property bool menuFloating: false
  property var menuMonitors: []
  property int menuLevel: 0
  property bool menuLevelSettling: false

  // Captured BEFORE close(), because close() destroys the row delegate and its
  // ids stop resolving.
  property string pendingActionKind: ""
  property string pendingActionAddress: ""
  property int pendingActionWorkspace: 0

  readonly property var currentMenuRows: root.menuLevel === 1
    ? MenuModel.workspaceRows(root.menuWorkspaceId)
    : MenuModel.rootRows({ floating: root.menuFloating, monitors: root.menuMonitors })

  // PopupCard.close() calls owner.close(); the menu card sets owner: root.
  function close() { root.menuOpen = false }

  function openMenu(button, address) {
    var addr = String(address || "")
    if (!addr) return
    var entry = root.entryFor(addr)
    if (!entry) return

    root.menuMonitors = root.otherMonitors()
    root.menuAddress = addr
    root.menuTitle = entry.title
    root.menuWorkspaceId = entry.workspaceId
    root.menuFloating = entry.floating

    root.resetMenuLevel()
    root.menuAnchor = button
    root.menuOpen = true
  }

  function resetMenuLevel() {
    root.menuLevel = 0
    root.menuLevelSettling = false
    menuSettleTimer.stop()
  }

  // A level change rebuilds the rows synchronously under a cursor that has not
  // moved, so a second click would fire whatever row took that spot. "Move to
  // workspace" is row 2 of the root level and workspace "2" is row 2 of the
  // submenu, at the same y -- without this a stray double-click silently moves
  // the window.
  function settleMenuLevel() {
    root.menuLevelSettling = true
    menuSettleTimer.restart()
  }
  function enterMenuLevel(level) { root.menuLevel = level; root.settleMenuLevel() }
  function leaveMenuLevel() { root.menuLevel = 0; root.settleMenuLevel() }

  function requestMenuAction(kind, workspaceId) {
    root.pendingActionKind = String(kind)
    root.pendingActionAddress = root.menuAddress
    root.pendingActionWorkspace = Number(workspaceId || 0)
    root.close()
  }

  // Runs once the card has actually gone (end of its 140ms fade), not merely
  // once `open` went false. HyprlandFocusGrab.active flips immediately but the
  // compositor-side teardown is an async round trip, and dispatching a focus or
  // move while the grab is still live can land focus on the grab owner or
  // bounce it back to the bar.
  function runPendingMenuAction() {
    var kind = root.pendingActionKind
    if (!kind) return
    var addr = root.pendingActionAddress
    var ws = root.pendingActionWorkspace
    root.pendingActionKind = ""
    root.pendingActionAddress = ""
    root.pendingActionWorkspace = 0
    if (!addr) return

    if (kind === "close") Hyprland.dispatch(Dispatch.closeWindow(addr))
    else if (kind === "float") Hyprland.dispatch(Dispatch.toggleFloating(addr))
    // Follows, matching SUPER+SHIFT+n.
    else if (kind === "workspace") Hyprland.dispatch(Dispatch.moveToWorkspace(addr, ws, true))
    // Does NOT follow: the window becomes visible on the other screen anyway,
    // and following would yank focus across monitors.
    else if (kind === "monitor") Hyprland.dispatch(Dispatch.moveToWorkspace(addr, ws, false))
  }

  onMenuOpenChanged: {
    if (root.menuOpen) root.closePreview()
    else root.previewSuppressedAddress = ""
  }

  // ---- overflow
  property bool overflowOpen: false
  // Declarative, not left to reconcileAfterSync(): that only runs on Hyprland
  // events, so changing maxIcons alone would leave the flag set and the chip
  // needing two clicks to reopen.
  onOverflowCountChanged: if (root.overflowCount <= 0) root.overflowOpen = false


  implicitWidth: root.vertical ? root.barSize : layout.implicitWidth
  implicitHeight: root.vertical ? layout.implicitHeight : root.barSize
  visible: root.windowCount > 0

  Component.onCompleted: { root.resolveMonitor(); root.refresh() }
  onQsScreenChanged: coalesce.restart()
  // Deferred through the coalesce timer: bumping modelRevision straight from a
  // change handler that the model depends on is a binding loop.
  onMonitorIdChanged: coalesce.restart()

  // Clears suppression when the pointer leaves the widget entirely. A
  // HoverHandler is a pointer handler, not a MouseArea, so it does not block
  // hover delivery to the buttons underneath.
  HoverHandler {
    id: widgetHover
    onHoveredChanged: if (!hovered) root.previewSuppressedAddress = ""
  }

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
        // lastIpcObject.floating goes stale after a float toggle. Deferred
        // rather than called here: refreshToplevels() from inside the event
        // handler is the same re-entrancy that crashed the shell.
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

  Timer {
    id: coalesce
    interval: 40
    onTriggered: {
      // Everything that touches Hyprland state happens here, on the event loop,
      // never inside the IPC read callstack.
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
      Qt.callLater(function () { root.refresh() })
    }
  }

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

  // Grace period so the pointer can cross the gap from button to card.
  Timer {
    id: closeTimer
    interval: 160
    onTriggered: if (!root.previewStillWanted()) root.closePreview()
  }

  // Wayland drops leave events when a surface appears under the cursor, so a
  // poll is the only reliable way to notice the pointer has gone.
  Timer {
    interval: 120
    repeat: true
    running: root.previewOpen
    onTriggered: if (!root.previewStillWanted()) closeTimer.restart()
  }

  // Backstop for the same lost-leave-event problem: without it a dropped leave
  // could suppress previews on one icon forever. Timing out is harmless --
  // opening needs a fresh hover transition, so a pointer still parked on the
  // icon gets nothing.
  Timer {
    id: suppressionWatchdog
    interval: 4000
    onTriggered: root.previewSuppressedAddress = ""
  }

  Timer {
    id: menuSettleTimer
    interval: 250
    onTriggered: root.menuLevelSettling = false
  }

  // PopupCard.close() calls owner.close(). The owner must never be the card
  // itself: "close" in card is true, so card.close() would call itself until
  // the stack blew.
  QtObject {
    id: previewOwner
    function close() { root.closePreview() }
  }
  QtObject {
    id: overflowOwner
    function close() { root.overflowOpen = false }
  }

  PreviewBarShim {
    id: previewBar
    source: root.bar
  }

  PreviewCard {
    id: preview
    host: root
    entry: root.hoverEntry
    toplevel: root.hoverToplevel
    // Anchoring to one of our own buttons is what keeps the card on the right
    // screen: PopupCard derives popupScreen from anchorItem.QsWindow.window.
    anchorItem: root.hoverTarget ? root.hoverTarget : root
    bar: previewBar
    owner: previewOwner
    open: root.previewOpen && root.hoverTarget !== null && root.hoverEntry !== null
  }

  TaskMenu {
    id: taskMenu
    host: root
    anchorItem: root.menuAnchor ? root.menuAnchor : root
    bar: root.bar
    owner: root
    open: root.menuOpen
  }

  OverflowCard {
    id: overflowCard
    host: root
    model: windowModel
    anchorItem: overflowChip
    bar: root.bar
    owner: overflowOwner
    open: root.overflowOpen && root.overflowCount > 0
  }

  GridLayout {
    id: layout
    anchors.fill: parent
    columns: root.vertical ? 1 : Math.max(1, root.visibleCount + 1)
    columnSpacing: 0
    rowSpacing: 0

    Repeater {
      model: windowModel

      // address/title/appClass/urgent/activated/index are required properties
      // on TaskButton and are filled from the model roles automatically.
      TaskButton {
        bar: root.bar
        host: root
        iconPixelSize: root.effectiveIconSize
        slotSize: root.effectiveSlotSize
        visible: index < root.visibleCount
      }
    }

    // Declared after the Repeater so it lands last in the row.
    WidgetButton {
      id: overflowChip
      bar: root.bar
      visible: root.overflowCount > 0
      labelVisible: true
      // WidgetButton, not BarIconButton: the latter forces labelVisible false
      // and renders text through OpticalGlyph in the icon font, where "+3"
      // would come out as tofu.
      text: "+" + root.overflowCount
      fontSize: Style.font.bodySmall
      horizontalMargin: 5
      onPressed: function (which) {
        root.dismissPreviewForClick("")
        root.overflowOpen = !root.overflowOpen
      }
    }
  }
}
