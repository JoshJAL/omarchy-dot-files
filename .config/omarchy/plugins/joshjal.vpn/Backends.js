.pragma library

// One definition per VPN backend. `cmd` runs through `sh -c`; exit 127 means
// the CLI is missing, which hides the backend. Entry shape:
//   { backend, key, name, detail, kind, active, ref, brief? }
// `brief` is an optional short label for the bar/header; falls back to `name`.
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
    active: running, ref: "", brief: "Tailscale"
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
  var cm = status.match(/City:\s*(.+)/i)
  var hm = status.match(/Hostname:\s*(\S+)/i)
  var im = status.match(/\bIP:\s*(\S+)/i)
  var countryName = connected && m ? m[1].trim() : ""
  var cityName = connected && cm ? cm[1].trim() : ""
  var current = countryName.replace(/\s+/g, "_")
  var entries = []
  if (connected && countryName) {
    var info = []
    if (hm) info.push(hm[1].split(".")[0])
    if (im) info.push(im[1])
    info.push("Connected")
    entries.push({
      backend: "nordvpn", key: "current", kind: "connection",
      name: cityName ? countryName + " · " + cityName : countryName,
      detail: info.join(" · "),
      brief: "NordVPN: " + (cityName ? cityName + ", " : "") + countryName,
      active: true, ref: ""
    })
  }
  var words = (parts[1] || "").split(/[\s,]+/)
  for (var i = 0; i < words.length; i++) {
    var w = words[i]
    if (!/^[A-Za-z][A-Za-z_]+$/.test(w)) continue
    var isCur = current !== "" && current.toLowerCase() === w.toLowerCase()
    entries.push({
      backend: "nordvpn", key: w, kind: "country", name: w.replace(/_/g, " "),
      detail: isCur ? "Connected" : "", active: isCur, ref: w, drillable: true
    })
  }
  return entries
}

// NordVPN country/city refs are interpolated into a shell string, so only
// plain identifiers are allowed through.
function safeName(w) {
  return /^[A-Za-z_]+$/.test(String(w || ""))
}

function nordCitiesCmd(country) {
  if (!safeName(country)) return guard("nordvpn", "exit 2")
  return guard("nordvpn", "nordvpn status; echo " + MARK + "; nordvpn cities " + country)
}

function parseNordCities(out, country) {
  var parts = String(out || "").split(MARK)
  var status = parts[0] || ""
  var connected = /Status:\s*Connected/i.test(status)
  var cm = status.match(/Country:\s*(.+)/i)
  var ym = status.match(/City:\s*(.+)/i)
  var inCountry = connected && cm && cm[1].trim().replace(/\s+/g, "_").toLowerCase() === country.toLowerCase()
  var currentCity = inCountry && ym ? ym[1].trim().replace(/\s+/g, "_").toLowerCase() : ""
  var entries = [{
    backend: "nordvpn", key: country + ":fastest", kind: "fastest", name: "Fastest in country",
    detail: "", active: false, ref: country, country: country
  }]
  var words = (parts[1] || "").split(/[\s,]+/)
  for (var i = 0; i < words.length; i++) {
    var w = words[i]
    if (!safeName(w)) continue
    var isCur = currentCity !== "" && currentCity === w.toLowerCase()
    entries.push({
      backend: "nordvpn", key: country + ":" + w, kind: "city", name: w.replace(/_/g, " "),
      detail: isCur ? "Connected" : "", active: isCur, ref: w, country: country
    })
  }
  return entries
}

// Proton VPN CLI (1.0.5). Verified output:
//   status:        "Status: Connected" / "Server: US-FL#287 in Miami, United States" / "Load: 12%" / "Protocol: wireguard"
//   countries list: table, "Name<2+ spaces>CC"
//   cities list CC: "Cities in X:" then table "City<2+ spaces>Features"
// The CLI refuses to run while the GUI app is open; that error surfaces as the group error.
function protonStatus(status) {
  if (!/^\s*Status:\s*Connected/mi.test(status)) return null
  var m = status.match(/Server:\s*(\S+)\s+in\s+(.+?),\s*([^,\n]+?)\s*$/mi)
  var lm = status.match(/Load:\s*(\S+)/i)
  var pm = status.match(/Protocol:\s*(\S+)/i)
  return {
    server: m ? m[1] : "", city: m ? m[2].trim() : "", country: m ? m[3].trim() : "",
    load: lm ? lm[1] : "", protocol: pm ? pm[1] : ""
  }
}

function parseProton(out) {
  var parts = String(out || "").split(MARK)
  var cur = protonStatus(parts[0] || "")
  var entries = []
  if (cur && cur.country) {
    var info = []
    if (cur.server) info.push(cur.server)
    if (cur.load) info.push("load " + cur.load)
    if (cur.protocol) info.push(cur.protocol)
    info.push("Connected")
    entries.push({
      backend: "proton", key: "current", kind: "connection",
      name: cur.city ? cur.country + " · " + cur.city : cur.country,
      detail: info.join(" · "),
      brief: "Proton: " + (cur.city ? cur.city + ", " : "") + cur.country,
      active: true, ref: ""
    })
  }
  var lines = (parts[1] || "").split(/\r?\n/)
  for (var i = 0; i < lines.length; i++) {
    var m = lines[i].match(/^(\S.*?)\s{2,}([A-Z]{2})\s*$/)
    if (!m || m[1] === "Country") continue
    var isCur = !!cur && cur.country.toLowerCase() === m[1].toLowerCase()
    entries.push({
      backend: "proton", key: m[2], kind: "country", name: m[1],
      detail: isCur ? "Connected" : "", active: isCur, ref: m[2], drillable: true
    })
  }
  return entries
}

function protonCitiesCmd(code) {
  if (!/^[A-Z]{2}$/.test(String(code || ""))) return guard("protonvpn", "exit 2")
  return guard("protonvpn", "protonvpn status 2>/dev/null; echo " + MARK + "; protonvpn cities list " + code)
}

function parseProtonCities(out, code, title) {
  var parts = String(out || "").split(MARK)
  var cur = protonStatus(parts[0] || "")
  var inCountry = !!cur && cur.country.toLowerCase() === String(title || "").toLowerCase()
  var entries = [{
    backend: "proton", key: code + ":fastest", kind: "fastest", name: "Fastest in country",
    detail: "", active: false, ref: code, country: code
  }]
  var lines = (parts[1] || "").split(/\r?\n/)
  for (var i = 0; i < lines.length; i++) {
    var l = lines[i]
    if (!l.trim() || /^Cities in/i.test(l) || /^City\s/.test(l) || /^-+/.test(l)) continue
    var name = l.split(/\s{2,}/)[0].trim()
    if (!name) continue
    var isCur = inCountry && cur.city.toLowerCase() === name.toLowerCase()
    entries.push({
      backend: "proton", key: code + ":" + name, kind: "city", name: name,
      detail: isCur ? "Connected" : "", active: isCur, ref: name, country: code
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
    connect: function (e) {
      if (e.kind === "city") return ["nordvpn", "connect", e.country, e.ref]
      return ["nordvpn", "connect", e.ref]
    },
    disconnect: function () { return ["nordvpn", "disconnect"] },
    citiesCmd: nordCitiesCmd,
    parseCities: function (out, ref) { return parseNordCities(out, ref) }
  },
  {
    id: "proton", label: "PROTON VPN",
    cmd: guard("protonvpn", "protonvpn status 2>/dev/null; echo " + MARK + "; protonvpn countries list"),
    parse: parseProton,
    connect: function (e) {
      if (e.kind === "city") return ["protonvpn", "connect", "--country", e.country, "--city", e.ref]
      return ["protonvpn", "connect", "--country", e.ref]
    },
    disconnect: function () { return ["protonvpn", "disconnect"] },
    citiesCmd: protonCitiesCmd,
    parseCities: parseProtonCities
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
