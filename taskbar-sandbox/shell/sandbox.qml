import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "taskbar" as Taskbar

// Development harness for joshjal.taskbar.
//
// Run:  qs -p ~/taskbar-sandbox/shell/sandbox.qml
//
// It lives OUTSIDE ~/.config/omarchy/plugins/ on purpose -- the plugin scanner
// walks that directory, and a second copy of the widget registering itself
// against the live bar is exactly the thing this harness exists to avoid. The
// `taskbar` entry here is a symlink to the real plugin directory, so there is
// one source of truth and no copy to keep in sync.
//
// Why a harness at all: a crash inside a live bar widget takes down the whole
// Omarchy shell -- bar, wallpaper, notifications, every popup -- and it
// crash-loops. The plugin's README documents two ways to do that in QML
// (mutating Hyprland state inside onRawEvent, and putting a HyprlandToplevel in
// a ListModel role). Both segfault. Neither should be discovered on the desktop
// you are working on.
//
// WHAT THIS HARNESS CANNOT PROVE (also in the README, repeated here because
// this is where you will be looking): PopupCard.availableCardHeight subtracts
// the anchor window's height, assuming that window is the ~26px bar strip. The
// FloatingWindow below is full-size, so that subtraction eats the screen and
// every popup clamps to its 120px floor. Popup SIZING, PLACEMENT and
// outside-click dismissal are only meaningful against the real bar. Logic,
// state, model churn and dispatch all validate fine here.
ShellRoot {
  id: sandbox

  // Settings handed to the widget, mirroring one layout entry in shell.json.
  // Edit and re-run; there is no hot reload of this object.
  property var widgetSettings: ({
    previewDelay: 320,
    includeSpecial: true,
    showTitles: true,
    maxIcons: 0,
    dimInactive: true
  })

  FloatingWindow {
    id: win
    implicitWidth: 1100
    implicitHeight: 220
    color: Color.bar ? Color.bar.background : "#1a1a1a"

    // Stand-in for the host Bar. The widget reads exactly six members off
    // `bar` (fontFamily, foreground, position, requestPopout, shell, urgent);
    // `vertical` and `barSize` come from the BarWidget base, which derives them
    // from this object. Verified by grep over the plugin -- Style.bar.iconSlot
    // and Style.bar.iconCanvas look like bar members but are Commons tokens.
    QtObject {
      id: mockBar

      property string position: "top"
      readonly property bool vertical: position === "left" || position === "right"
      readonly property int barSize: vertical ? Style.bar.sizeVertical : Style.bar.sizeHorizontal

      property string fontFamily: Style.font.family

      // Names taken from the real Bar, not invented. WidgetButton (the base of
      // BarIconButton) reads `bar.barForeground` -- NOT `bar.foreground` -- and
      // the Color singleton exposes `Color.bar.text`, not `Color.bar.foreground`.
      // Both mistakes are silent: QML assigns undefined to a color property with
      // only a warning, and the widget renders in a default that looks close
      // enough to miss.
      property color barForeground: Color.bar.text
      property color foreground: Color.bar.text
      property color background: Color.bar.background
      property color urgent: Color.bar.active

      // The real Bar animates foreground on theme change. Off here: a 420ms
      // color transition on every property poke makes screenshots inconsistent.
      property bool foregroundAnimationEnabled: false

      // WidgetButton calls these unconditionally on hover and on destruction.
      // Missing, they throw TypeError on every pointer movement and bury real
      // warnings in the noise.
      function showTooltip(target, text) {}
      function hideTooltip(target) {}

      // A bar-widget plugin never receives shell.appLibrary -- shell.qml hands
      // it only to plugins whose manifest declares the "menu" kind. null here
      // is CORRECT, not a harness shortcut: it is what the widget gets in
      // production, and it is why IconModel has to resolve icons itself.
      property var shell: null

      property var activePopout: null
      function requestPopout(owner) { mockBar.activePopout = owner }
      function releasePopout(owner) { if (mockBar.activePopout === owner) mockBar.activePopout = null }

      // The real Bar relays a call to every per-monitor instance. One instance
      // exists here, so broadcast() collapses to calling it on ourselves.
      function moduleWidgets(pluginId) { return [widget] }

      function run(command) { console.log("[sandbox] bar.run:", command) }
    }

    ColumnLayout {
      anchors.fill: parent
      spacing: 0

      // The bar strip. Height matches the real thing so icon sizing, title
      // eliding and the urgent marker geometry all land where they would.
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: mockBar.barSize
        color: Color.bar ? Color.bar.background : "#1a1a1a"

        Taskbar.BarWidget {
          id: widget
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          bar: mockBar
          moduleName: "joshjal.taskbar"
          settings: sandbox.widgetSettings
        }
      }

      // Live state readout. This is the actual point of the harness: this
      // machine has no pointer synthesis (no ydotool, and the user is not in
      // the `input` group so /dev/uinput is unreachable), so clicks cannot be
      // scripted and the model has to be inspected directly.
      Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        color: "#101010"

        Text {
          anchors.fill: parent
          anchors.margins: 10
          color: "#c8c8c8"
          font.family: "monospace"
          font.pixelSize: 11
          textFormat: Text.PlainText
          text: sandbox.stateText()
          // Cheap poll: the model mutates from a coalesce timer, and binding
          // to ListModel internals does not reliably re-evaluate.
          Timer {
            interval: 500; running: true; repeat: true
            onTriggered: parent.text = sandbox.stateText()
          }
        }
      }
    }
  }

  // NOTE: the harness's own FloatingWindow is a real Hyprland toplevel, so it
  // appears in its own taskbar -- and if a special workspace happens to be
  // revealed when it opens, Hyprland places it THERE and it shows up flagged
  // special. Harmless, and not a bug in the widget: the live bar is a layer
  // surface, not a toplevel, so it never lists itself.

  // Rendered into the panel above and returned by the `state` IPC call.
  function stateText() {
    if (!widget || !widget.model) return "(widget not ready)"
    var lines = []
    lines.push("monitorId=" + widget.monitorId
      + "  rows=" + widget.model.count
      + "  delegateCreations=" + (widget.delegateCreations !== undefined ? widget.delegateCreations : "n/a"))
    lines.push("")
    lines.push("  " + "ws".padEnd(6) + "special".padEnd(9) + "class".padEnd(26) + "title")
    for (var i = 0; i < widget.model.count; i++) {
      var r = widget.model.get(i)
      lines.push("  "
        + String(r.workspaceId).padEnd(6)
        + String(r.special === true ? "YES" : "-").padEnd(9)
        + String(r.appClass).substring(0, 24).padEnd(26)
        + String(r.title).substring(0, 44))
    }
    return lines.join("\n")
  }

  // Scripted pokes, since clicks cannot be synthesized here.
  //
  //   qs -p ~/taskbar-sandbox/shell/sandbox.qml ipc call tb state
  //   qs -p ~/taskbar-sandbox/shell/sandbox.qml ipc call tb click <address>
  //   qs -p ~/taskbar-sandbox/shell/sandbox.qml ipc call tb churn
  IpcHandler {
    target: "tb"

    function state(): string { return sandbox.stateText() }

    function churn(): string {
      return "delegateCreations=" + (widget && widget.delegateCreations !== undefined
        ? widget.delegateCreations : "n/a")
        + "  (should hold steady while windows merely change title)"
    }

    // Exercises the same path a left click takes, without a pointer.
    function click(address: string): string {
      if (!widget) return "widget not ready"
      for (var i = 0; i < widget.model.count; i++) {
        var r = widget.model.get(i)
        if (String(r.address) !== String(address)) continue
        if (r.special === true) { widget.bringWindow(r.address); return "bring " + address }
        widget.focusWindow(r.address)
        return "focus " + address
      }
      return "no such address in model: " + address
    }

    function refresh(): string { widget.refresh(); return "refreshed" }
  }
}
