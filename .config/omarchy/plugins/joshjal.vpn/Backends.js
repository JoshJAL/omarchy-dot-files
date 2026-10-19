.pragma library

// One definition per VPN backend. `cmd` runs through `sh -c`; exit 127 means
// the CLI is missing, which hides the backend. Entry shape:
//   { backend, key, name, detail, kind, active, ref }
// NordVPN and Mullvad parsers are written against the documented CLI output
// and are UNVERIFIED (neither CLI is installed on this machine).

var MARK = "@@SPLIT@@"

function guard(bin, body) {
  return "command -v " + bin + " >/dev/null 2>&1 || exit 127; " + body
}

function nmSplit(line) {
  // `nmcli -t` escapes ':' and '\' with a backslash.
  var parts = []
  var cur = ""
  for (var i = 0; i < line.length; i++) {
    var c = line[i]
    if (c === "\\" && i + 1 < line.length) { cur += line[++i]; continue }
    if (c === ":") { parts.push(cur); cur = ""; continue }
    cur += c
  }
  parts.push(cur)
  return parts
}

function parseNm(out) {
  var entries = []
  var lines = String(out || "").split(/\r?\n/)
  for (var i = 0; i < lines.length; i++) {
    if (lines[i] === "") continue
    var f = nmSplit(lines[i])
    if (f.length < 4) continue
    var type = f[2]
    if (type !== "vpn" && type !== "wireguard") continue
    entries.push({
      backend: "networkmanager", key: f[1], name: f[0],
      detail: type === "wireguard" ? "WireGuard" : "VPN",
      kind: "profile", active: f[3] !== "", ref: f[1]
    })
  }
  return entries
}

function parseTailscale(out) {
  var data
  try { data = JSON.parse(out) } catch (e) { return [] }
  var running = data.BackendState === "Running"
  var needsLogin = data.BackendState === "NeedsLogin"
  var entries = [{
    backend: "tailscale", key: "toggle", kind: "toggle",
    name: needsLogin ? "Tailscale (needs login)" : "Tailscale",
    detail: running ? "Connected" : (needsLogin ? "Open the Tailscale panel to log in" : "Disconnected"),
    active: running, ref: ""
  }]
  if (!running) return entries
  var peers = data.Peer || {}
  var nodes = []
  for (var id in peers) {
    var p = peers[id]
    if (p.ExitNodeOption !== true || !p.TailscaleIPs || p.TailscaleIPs.length === 0) continue
    var host = String(p.DNSName || p.HostName || "").replace(/\.$/, "")
    nodes.push({
      backend: "tailscale", key: "exit:" + host, kind: "exit",
      name: String(p.HostName || host), detail: "Exit node",
      active: p.ExitNode === true, ref: String(p.TailscaleIPs[0])
    })
  }
  nodes.sort(function (a, b) { return a.name.localeCompare(b.name) })
  return entries.concat(nodes)
}

function parseNord(out) {
  var parts = String(out || "").split(MARK)
  var status = parts[0] || ""
  var connected = /Status:\s*Connected/i.test(status)
  var m = status.match(/Country:\s*(.+)/i)
  var current = connected && m ? m[1].trim().replace(/\s+/g, "_") : ""
  var entries = []
  var words = (parts[1] || "").split(/[\s,]+/)
  for (var i = 0; i < words.length; i++) {
    var w = words[i]
    if (!/^[A-Za-z][A-Za-z_]+$/.test(w)) continue
    entries.push({
      backend: "nordvpn", key: w, kind: "country", name: w.replace(/_/g, " "),
      detail: "", active: current !== "" && current.toLowerCase() === w.toLowerCase(), ref: w
    })
  }
  return entries
}

function parseMullvad(out) {
  var parts = String(out || "").split(MARK)
  var status = parts[0] || ""
  var connected = /^Connected/i.test(status.trim())
  var entries = []
  var lines = (parts[1] || "").split(/\r?\n/)
  for (var i = 0; i < lines.length; i++) {
    var m = lines[i].match(/^(\S.*?)\s+\(([a-z]{2})\)\s*$/)
    if (!m) continue
    entries.push({
      backend: "mullvad", key: m[2], kind: "country", name: m[1], detail: "",
      active: connected && status.toLowerCase().indexOf(m[1].toLowerCase()) !== -1, ref: m[2]
    })
  }
  return entries
}

var defs = [
  {
    id: "networkmanager", label: "NETWORKMANAGER",
    cmd: guard("nmcli", "nmcli -t -f NAME,UUID,TYPE,DEVICE connection show"),
    parse: parseNm,
    connect: function (e) { return ["nmcli", "connection", "up", "uuid", e.ref] },
    disconnect: function (e) { return ["nmcli", "connection", "down", "uuid", e.ref] }
  },
  {
    id: "tailscale", label: "TAILSCALE",
    cmd: guard("tailscale", "tailscale status --json"),
    parse: parseTailscale,
    connect: function (e) {
      if (e.kind === "toggle") return ["tailscale", "up"]
      return ["tailscale", "set", "--exit-node=" + e.ref]
    },
    disconnect: function (e) {
      if (e.kind === "toggle") return ["tailscale", "down"]
      return ["tailscale", "set", "--exit-node="]
    }
  },
  {
    id: "nordvpn", label: "NORDVPN",
    cmd: guard("nordvpn", "nordvpn status; echo " + MARK + "; nordvpn countries"),
    parse: parseNord,
    connect: function (e) { return ["nordvpn", "connect", e.ref] },
    disconnect: function () { return ["nordvpn", "disconnect"] }
  },
  {
    id: "mullvad", label: "MULLVAD",
    cmd: guard("mullvad", "mullvad status; echo " + MARK + "; mullvad relay list"),
    parse: parseMullvad,
    connect: function (e) {
      return ["sh", "-c", 'mullvad relay set location "$1" && mullvad connect', "sh", e.ref]
    },
    disconnect: function () { return ["mullvad", "disconnect"] }
  }
]

function def(id) {
  for (var i = 0; i < defs.length; i++) if (defs[i].id === id) return defs[i]
  return null
}
