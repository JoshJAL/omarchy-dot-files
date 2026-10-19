import QtQuick
import QtQml
import Quickshell
import Quickshell.Io
import "Backends.js" as Backends

Item {
  id: root

  property var settings: ({})

  // { backendId: { installed: bool, entries: [], error: "" } }
  property var results: ({})
  property string actionStatus: ""
  property string lastError: ""

  readonly property int refreshIntervalSec: {
    var n = parseInt(String(settings && settings.refreshIntervalSec !== undefined ? settings.refreshIntervalSec : 30), 10)
    return isFinite(n) ? Math.max(5, Math.min(3600, n)) : 30
  }

  // Visible groups, with a flat cursor index stamped on every entry.
  readonly property var groups: buildGroups(results)
  readonly property var flat: flatten(groups)
  readonly property var activeEntries: flat.filter(function (e) { return e.active })
  readonly property bool anyActive: activeEntries.length > 0
  readonly property string activeLabel: {
    if (activeEntries.length === 0) return "No VPN connected"
    return activeEntries.map(function (e) { return e.name }).join(", ")
  }
  readonly property bool busy: actionProcess.running

  function buildGroups(res) {
    var out = []
    var n = 0
    for (var i = 0; i < Backends.defs.length; i++) {
      var d = Backends.defs[i]
      var r = res[d.id]
      if (!r || !r.installed) continue
      var entries = []
      for (var j = 0; j < r.entries.length; j++) {
        var e = {}
        for (var k in r.entries[j]) e[k] = r.entries[j][k]
        e.flatIndex = n++
        entries.push(e)
      }
      out.push({ id: d.id, label: d.label, entries: entries, error: r.error })
    }
    return out
  }

  function flatten(gs) {
    var out = []
    for (var i = 0; i < gs.length; i++) out = out.concat(gs[i].entries)
    return out
  }

  function refresh() {
    for (var i = 0; i < probes.count; i++) {
      var p = probes.objectAt(i)
      if (p && !p.running) { p.command = ["sh", "-c", p.cmdText]; p.running = true }
    }
    if (!watchdog.running) watchdog.start()
  }

  function setResult(id, value) {
    var next = {}
    for (var k in results) next[k] = results[k]
    next[id] = value
    results = next
  }

  function elide(text) {
    var v = String(text || "").replace(/\s+/g, " ").trim()
    return v.length > 140 ? v.substring(0, 137) + "…" : v
  }

  function run(command) {
    if (actionProcess.running || !command) return
    actionStatus = ""
    lastError = ""
    actionProcess.command = command
    actionProcess.running = true
  }

  function connect(entry) {
    if (!entry) return
    run(Backends.def(entry.backend).connect(entry))
  }

  function disconnect(entry) {
    if (!entry) return
    run(Backends.def(entry.backend).disconnect(entry))
  }

  function toggle(entry) {
    if (!entry) return
    if (entry.active) disconnect(entry)
    else connect(entry)
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: delayedRefresh
    interval: 800
    onTriggered: root.refresh()
  }

  Timer {
    id: errorClear
    interval: 4000
    onTriggered: root.actionStatus = ""
  }

  // A CLI that hangs (daemon down, network flapping) would block its own
  // polling forever; reap anything still running well inside the interval.
  Timer {
    id: watchdog
    interval: 15000
    onTriggered: {
      for (var i = 0; i < probes.count; i++) {
        var p = probes.objectAt(i)
        if (p && p.running) p.running = false
      }
    }
  }

  Instantiator {
    id: probes
    model: Backends.defs.length
    delegate: Process {
      id: probe
      required property int index
      readonly property var def: Backends.defs[index]
      readonly property string cmdText: def.cmd
      running: false
      command: []
      stdout: StdioCollector { id: out; waitForEnd: true }
      stderr: StdioCollector { id: err; waitForEnd: true }
      onExited: function (exitCode) {
        if (exitCode === 127) {
          root.setResult(def.id, { installed: false, entries: [], error: "" })
          return
        }
        if (exitCode !== 0) {
          root.setResult(def.id, { installed: true, entries: [], error: root.elide(err.text || out.text || (def.id + " failed")) })
          return
        }
        root.setResult(def.id, { installed: true, entries: def.parse(String(out.text || "")), error: "" })
      }
    }
  }

  Process {
    id: actionProcess
    running: false
    command: []
    stdout: StdioCollector { id: actionOut; waitForEnd: true }
    stderr: StdioCollector { id: actionErr; waitForEnd: true }
    onExited: function (exitCode) {
      if (exitCode !== 0) {
        root.lastError = root.elide(actionErr.text || actionOut.text || "VPN command failed")
        root.actionStatus = root.lastError
        errorClear.restart()
      }
      delayedRefresh.restart()
    }
  }
}
