.pragma library

// Pure helpers for turning Hyprland.toplevels into this monitor's window list,
// and for syncing that list into a ListModel incrementally.
//
// Every field on a HyprlandToplevel is defensively read. Toplevels routinely
// surface before the Hyprland IPC blob that describes them arrives, with
// `lastIpcObject`, `workspace` and `monitor` all empty -- it happens on every
// shell start. Those windows must not crash the model or be silently dropped
// onto no bar at all, hence the `pending` bucket and the caller's retry.
//
// NOTHING in here may hold a reference to a HyprlandToplevel that ends up in a
// ListModel role. See the note on row() below.

function ipcOf(tl) {
  var ipc = tl ? tl.lastIpcObject : null
  return ipc ? ipc : {}
}

function workspaceIdOf(tl) {
  if (tl && tl.workspace && tl.workspace.id !== undefined) return Number(tl.workspace.id)
  var ipc = ipcOf(tl)
  if (ipc.workspace && ipc.workspace.id !== undefined) return Number(ipc.workspace.id)
  return null
}

function monitorIdOf(tl) {
  if (tl && tl.monitor && tl.monitor.id !== undefined) return Number(tl.monitor.id)
  // `hyprctl clients` reports monitor as a bare integer id, not an object.
  var ipc = ipcOf(tl)
  if (ipc.monitor !== undefined && ipc.monitor !== null) return Number(ipc.monitor)
  return null
}

function classOf(tl) {
  var ipc = ipcOf(tl)
  var cls = ipc["class"] || ipc.initialClass || ""
  if (!cls && tl && tl.wayland && tl.wayland.appId) cls = tl.wayland.appId
  return String(cls || "")
}

function isPending(tl) {
  return monitorIdOf(tl) === null || workspaceIdOf(tl) === null
}

function pendingCount(values) {
  var n = 0
  for (var i = 0; i < (values ? values.length : 0); i++) if (isPending(values[i])) n++
  return n
}

// The ONLY place a model row is constructed.
//
// Two rules, both load-bearing:
//
// 1. No QObject. A HyprlandToplevel stored in a ListModel role becomes a
//    dangling C++ pointer the moment its owner destroys it, and the next read
//    of that role segfaults inside QQmlListModel::data. Omarchy hit this itself
//    and documented it in plugins/notifications/Service.qml. The toplevel lives
//    in a plain JS map on the widget root instead, keyed by address; nothing in
//    a delegate needs it.
//
// 2. Every key, every time, coerced. ListModel fixes each role's type from the
//    first element inserted -- a null or undefined at that moment poisons the
//    role for the life of the process, and rows carrying keys the model has
//    never seen are silently dropped with a warning.
var ROLES = ["title", "appClass", "workspaceId", "floating", "urgent", "activated", "seq"]

function row(tl, workspaceId, seq) {
  var ipc = ipcOf(tl)
  return {
    address: String(tl.address || ""),
    title: String(tl.title || ""),
    appClass: String(classOf(tl) || ""),
    workspaceId: Number(workspaceId),
    floating: ipc.floating === true,
    urgent: tl.urgent === true,
    activated: tl.activated === true,
    seq: Number(seq)
  }
}

// This monitor's rows, sorted by (workspace, first-seen sequence). `orderSeq`
// maps address -> sequence so icons keep their slot when Hyprland reorders its
// client list; unknown addresses sort last rather than jumping to the front.
function forMonitor(values, monitorId, includeSpecial, orderSeq) {
  var out = []
  if (monitorId === null || monitorId === undefined || Number(monitorId) < 0) return out

  for (var i = 0; i < (values ? values.length : 0); i++) {
    var tl = values[i]
    if (!tl) continue

    var wsId = workspaceIdOf(tl)
    if (wsId === null) continue
    // Special/scratchpad workspaces carry negative ids.
    if (!includeSpecial && wsId < 0) continue
    if (monitorIdOf(tl) !== Number(monitorId)) continue

    var addr = String(tl.address || "")
    if (!addr) continue

    var seq = orderSeq && orderSeq[addr] !== undefined ? orderSeq[addr] : Number.MAX_SAFE_INTEGER
    out.push(row(tl, wsId, seq))
  }

  out.sort(function (a, b) {
    if (a.workspaceId !== b.workspaceId) return a.workspaceId - b.workspaceId
    if (a.seq !== b.seq) return a.seq - b.seq
    return a.address < b.address ? -1 : (a.address > b.address ? 1 : 0)
  })
  return out
}

// Reconcile `model` to `next` in place: remove what's gone, insert what's new,
// move what's out of order, and setProperty only the fields that actually
// differ. Delegates for unchanged rows are never destroyed, which is the whole
// point -- a fresh array assigned to a Repeater rebuilds every delegate, and
// windowtitlev2 fires on every terminal title change.
//
// Returns true if anything changed, so the caller can skip waking bindings on
// a no-op sync.
function syncModel(model, next) {
  var changed = false

  // Removals first, back to front so indices stay valid as we splice.
  var wanted = {}
  for (var i = 0; i < next.length; i++) wanted[next[i].address] = true
  for (var r = model.count - 1; r >= 0; r--) {
    if (!wanted[model.get(r).address]) {
      model.remove(r)
      changed = true
    }
  }

  // Then insert / reorder / update, front to back. The inner search starts at
  // j because everything before it is already settled.
  for (var j = 0; j < next.length; j++) {
    var want = next[j]
    var at = -1
    for (var k = j; k < model.count; k++) {
      if (model.get(k).address === want.address) { at = k; break }
    }

    if (at === -1) {
      model.insert(j, want)
      changed = true
      continue
    }
    if (at !== j) {
      model.move(at, j, 1)
      changed = true
    }

    var have = model.get(j)
    for (var p = 0; p < ROLES.length; p++) {
      var key = ROLES[p]
      if (have[key] !== want[key]) {
        model.setProperty(j, key, want[key])
        changed = true
      }
    }
  }

  return changed
}

// address -> toplevel, for the one consumer that genuinely needs the live
// object (the preview's ScreencopyView captureSource). Kept off the model on
// purpose; see row().
function toplevelMap(values) {
  var map = {}
  for (var i = 0; i < (values ? values.length : 0); i++) {
    var tl = values[i]
    if (tl && tl.address) map[String(tl.address)] = tl
  }
  return map
}
