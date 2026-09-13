.pragma library

// Pure helpers for turning Hyprland.toplevels into this monitor's window list.
//
// Every field on a HyprlandToplevel is defensively read. The spike turned up
// toplevels whose `lastIpcObject`, `workspace` and `monitor` were all undefined
// -- Quickshell surfaces the Wayland handle before the Hyprland IPC blob that
// describes it has arrived. Those windows must not crash the model or get
// silently dropped onto no bar at all, so they are held in a pending bucket
// until a refresh fills them in.

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

// A toplevel we cannot yet place: no monitor, or no workspace. Counting these
// is what lets the widget ask for an IPC refresh instead of losing the window.
function isPending(tl) {
  return monitorIdOf(tl) === null || workspaceIdOf(tl) === null
}

function pendingCount(values) {
  var n = 0
  for (var i = 0; i < (values ? values.length : 0); i++) if (isPending(values[i])) n++
  return n
}

// Build this monitor's list. `orderSeq` maps address -> first-seen sequence so
// icons keep their position when Hyprland reorders its client list; unknown
// addresses sort last rather than jumping to the front.
function forMonitor(values, monitorId, includeSpecial, orderSeq) {
  var out = []
  if (monitorId === null || monitorId === undefined) return out

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

    var ipc = ipcOf(tl)
    var seq = orderSeq && orderSeq[addr] !== undefined ? orderSeq[addr] : Number.MAX_SAFE_INTEGER

    out.push({
      address: addr,
      toplevel: tl,
      workspaceId: wsId,
      title: String(tl.title || ""),
      appClass: classOf(tl),
      floating: ipc.floating === true,
      urgent: tl.urgent === true,
      activated: tl.activated === true,
      seq: seq
    })
  }

  out.sort(function (a, b) {
    if (a.workspaceId !== b.workspaceId) return a.workspaceId - b.workspaceId
    if (a.seq !== b.seq) return a.seq - b.seq
    return a.address < b.address ? -1 : (a.address > b.address ? 1 : 0)
  })
  return out
}

// Addresses present in `values`, for pruning per-address bookkeeping.
function addressSet(values) {
  var set = {}
  for (var i = 0; i < (values ? values.length : 0); i++) {
    var tl = values[i]
    if (tl && tl.address) set[String(tl.address)] = true
  }
  return set
}
