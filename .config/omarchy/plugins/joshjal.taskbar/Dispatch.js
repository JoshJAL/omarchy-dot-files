.pragma library

// Hyprland dispatcher strings.
//
// This Omarchy runs Hyprland's Lua dispatcher dialect. The legacy hyprlang
// form is not merely deprecated here, it errors:
//
//   $ hyprctl dispatch workspace 5
//   error: [string "return hl.dispatch(workspace 5)"]:1: ')' expected near '5'
//
// These go through Hyprland.dispatch(), straight down the IPC socket -- no
// shell, so no quoting to get wrong. Util.shellQuote + bar.run("hyprctl ...")
// is the fallback if a form ever trips on the IPC path.
// (Note bar.shellQuote does NOT exist on PluginBarApi despite the bar README
// listing it; Util.shellQuote from qs.Commons is the real one.)

// Quickshell reports HyprlandToplevel.address WITHOUT the 0x prefix
// ("562598ec1b70"), but Hyprland's address: selector requires it. Mismatched,
// the dispatch fails *silently*: "window not found" as a warning, exit 0.
function selector(address) {
  var a = String(address || "")
  if (!a) return ""
  return "address:" + (a.indexOf("0x") === 0 ? a : "0x" + a)
}

function focusWindow(address) {
  return 'hl.dsp.focus({ window = "' + selector(address) + '" })'
}

function focusWorkspace(workspaceId) {
  return 'hl.dsp.focus({ workspace = "' + String(workspaceId) + '" })'
}

function focusMonitor(name) {
  return 'hl.dsp.focus({ monitor = "' + String(name) + '" })'
}

function closeWindow(address) {
  return 'hl.dsp.window.close({ window = "' + selector(address) + '" })'
}

function toggleFloating(address) {
  return 'hl.dsp.window.float({ window = "' + selector(address) + '", action = "toggle" })'
}

// follow=false keeps the current workspace in view when shunting a window away.
function moveToWorkspace(address, workspaceId, follow) {
  return 'hl.dsp.window.move({ window = "' + selector(address) + '", workspace = "'
    + String(workspaceId) + '"' + (follow ? '' : ', follow = false') + ' })'
}

// hl.window.move accepts no monitor key -- its own error string lists only
// "direction, x+y(+relative), workspace, into_group, out_of_group". So moving
// a window to another monitor means moving it to a workspace that monitor is
// showing. Returns null when there is nowhere else to send it.
function otherMonitors(monitors, currentMonitorId) {
  var out = []
  for (var i = 0; i < (monitors ? monitors.length : 0); i++) {
    var m = monitors[i]
    if (!m || Number(m.id) === Number(currentMonitorId)) continue
    if (!m.activeWorkspace) continue
    out.push({ id: Number(m.id), name: String(m.name || ""), workspaceId: Number(m.activeWorkspace.id) })
  }
  return out
}
