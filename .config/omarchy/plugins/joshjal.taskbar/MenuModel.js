.pragma library

// Rows for the right-click context menu.
//
// Pure functions over a snapshot taken when the menu opened. Nothing here reads
// live Hyprland state: the rows must not mutate under a stationary cursor while
// the user is deciding which one to click.

// Level 0.
//
// `ctx.monitors` comes from Dispatch.otherMonitors(), which already excludes the
// current monitor -- so on a single-monitor machine it is empty and the monitor
// rows simply do not exist. With three or more monitors there is one row each,
// which removes the "which other monitor?" ambiguity a single item would have.
function rootRows(ctx) {
  var monitors = (ctx && ctx.monitors) ? ctx.monitors : []
  var rows = [
    { action: "close", label: "Close window", submenu: false, checked: false, workspaceId: 0 },
    { action: "workspace", label: "Move to workspace", submenu: true, checked: false, workspaceId: 0 },
    { action: "float", label: "Toggle floating", submenu: false, checked: ctx && ctx.floating === true, workspaceId: 0 }
  ]
  for (var i = 0; i < monitors.length; i++) {
    rows.push({
      action: "monitor",
      label: "Move to " + String(monitors[i].name || "other monitor"),
      submenu: false,
      checked: false,
      // hl.window.move takes no monitor key, so moving to a monitor means
      // moving to the workspace that monitor is currently showing.
      workspaceId: Number(monitors[i].workspaceId)
    })
  }
  return rows
}

// Level 1.
function workspaceRows(currentWorkspaceId) {
  var rows = []
  for (var i = 1; i <= 10; i++) {
    rows.push({
      action: "workspace",
      label: String(i),
      submenu: false,
      checked: Number(currentWorkspaceId) === i,
      workspaceId: i
    })
  }
  return rows
}
