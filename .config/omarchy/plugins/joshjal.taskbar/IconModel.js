.pragma library

// Window class -> desktop entry resolution, memoized.
//
// Nothing in the Omarchy shell does this mapping: AppLibrary.iconSource() takes
// an icon *name* off an already-resolved DesktopEntry, and the bar widgets that
// use it (menu, tray) always have the entry in hand. A taskbar only ever has a
// window class, so the class -> entry hop is ours to make.

var _cache = {}          // lowercased class -> DesktopEntry | null
var _generation = -1     // invalidated when the app list changes

function _resetIfStale(entriesLength) {
  if (_generation !== entriesLength) {
    _cache = {}
    _generation = entriesLength
  }
}

// --- Chromium web apps -------------------------------------------------------
//
// A `--app=URL` window gets no StartupWMClass and no desktop id. Chromium builds
// its class from the URL instead: app name = host + "_" + path, every character
// illegal in a filename (notably "/") becomes "_", and the window class is
// "<browser>-<app name>-<profile>". So
//
//   https://teams.microsoft.com/v2/  ->  chrome-teams.microsoft.com__v2_-Default
//
// The only surviving link back to the .desktop is the URL in its Exec line, so
// that is what we match on. The mangling is not reversible character for
// character -- a path that went through desktop-entry field-code stripping loses
// bytes ("%2F" arrives as "F") -- so we compare alphanumerics-only keys by
// common prefix rather than demanding equality, and require the host to match
// outright. That also separates two entries on the same host, such as Outlook
// mail and Outlook calendar.

var _BROWSER_PREFIXES = [
  "chrome-", "chromium-", "brave-browser-", "brave-",
  "microsoft-edge-", "msedge-", "vivaldi-", "opera-"
]

function _key(value) {
  return String(value || "").toLowerCase().replace(/[^a-z0-9]/g, "")
}

function _commonPrefixLength(a, b) {
  var n = Math.min(a.length, b.length)
  var i = 0
  while (i < n && a.charAt(i) === b.charAt(i)) i++
  return i
}

// The "<host><mangled path>" middle of a web-app class, or "" if `cls` is not
// one. The host test is what keeps ordinary classes such as "brave-browser" out.
function _webappClassCore(cls) {
  var raw = String(cls || "")
  var lower = raw.toLowerCase()
  var body = null
  for (var i = 0; i < _BROWSER_PREFIXES.length; i++) {
    if (lower.indexOf(_BROWSER_PREFIXES[i]) === 0) {
      body = raw.slice(_BROWSER_PREFIXES[i].length)
      break
    }
  }
  if (body === null) return ""
  // Trailing profile segment. Left alone when it is not one we recognise: an
  // unstripped tail only shortens the prefix score, it never picks a wrong entry.
  body = body.replace(/-(default|profile[_ ]?\d+)$/i, "")
  var host = body.split("_")[0]
  return host.indexOf(".") > 0 ? body : ""
}

// host + path of the first http(s) URL in an Exec line. Query and fragment are
// dropped because Chromium's app name is built from host and path only.
function _entryUrlHostPath(entry) {
  var exec = String((entry && entry.execString) || "")
  var match = exec.match(/https?:\/\/[^\s"']+/)
  if (!match) return ""
  return match[0].replace(/^https?:\/\//, "").split("#")[0].split("?")[0]
}

function _matchWebappEntry(values, cls) {
  var core = _webappClassCore(cls)
  if (!core) return null
  var classKey = _key(core)
  if (!classKey) return null

  var best = null
  var bestScore = 0
  var bestLength = 0
  for (var i = 0; i < values.length; i++) {
    var entry = values[i]
    if (!entry) continue
    var hostPath = _entryUrlHostPath(entry)
    if (!hostPath) continue
    var hostKey = _key(hostPath.split("/")[0])
    if (!hostKey || classKey.indexOf(hostKey) !== 0) continue

    var entryKey = _key(hostPath)
    var score = _commonPrefixLength(classKey, entryKey)
    if (score < hostKey.length) continue
    // Ties go to the shorter URL, so a bare https://github.com/ entry is not
    // beaten by https://github.com/notifications on the bare github.com class.
    if (score > bestScore || (score === bestScore && entryKey.length < bestLength)) {
      best = entry
      bestScore = score
      bestLength = entryKey.length
    }
  }
  return best
}

// `overrides` is the user's classIconOverrides map: class -> icon name. It wins
// outright, because Electron apps and PWAs routinely report a class that
// matches no desktop entry at all.
function resolve(DesktopEntries, cls, overrides) {
  var key = String(cls || "").toLowerCase()
  if (!key) return null

  var values = DesktopEntries.applications ? DesktopEntries.applications.values : []
  _resetIfStale(values.length)

  if (_cache[key] !== undefined) return _cache[key]

  var entry = null

  // 0. Chromium web apps. Most specific: a class that encodes a URL can only
  // belong to the entry launching that URL, and the fuzzy matcher below has
  // nothing to work with.
  entry = _matchWebappEntry(values, cls)

  // 1. Quickshell's own fuzzy matcher, purpose-built for this problem.
  if (!entry) {
    try {
      entry = DesktopEntries.heuristicLookup(cls)
    } catch (e) {
      entry = null
    }
  }

  // 2. Exact id, as given and lowercased.
  if (!entry) {
    try { entry = DesktopEntries.byId(cls) } catch (e2) { entry = null }
  }
  if (!entry) {
    try { entry = DesktopEntries.byId(key) } catch (e3) { entry = null }
  }

  // 3. Linear scan, most-specific field first. startupClass is the field the
  // freedesktop spec actually reserves for matching a window to an entry.
  if (!entry) {
    var bySuffix = null
    var byName = null
    for (var i = 0; i < values.length; i++) {
      var e = values[i]
      if (!e) continue
      if (String(e.startupClass || "").toLowerCase() === key) { entry = e; break }
      var id = String(e.id || "").toLowerCase()
      if (id === key) { entry = e; break }
      // "org.gnome.Nautilus" for class "nautilus"
      if (!bySuffix && id.length > key.length && id.slice(-(key.length + 1)) === "." + key) bySuffix = e
      if (!byName && String(e.name || "").toLowerCase() === key) byName = e
    }
    if (!entry) entry = bySuffix || byName
  }

  _cache[key] = entry || null
  return _cache[key]
}

// The icon NAME to hand to AppLibrary.iconSource(). Overrides first, then the
// resolved entry's icon, then the bare class -- iconSource() itself falls back
// to application-x-executable when that resolves to nothing.
function iconNameFor(DesktopEntries, cls, overrides) {
  var raw = String(cls || "")
  if (overrides) {
    if (overrides[raw]) return String(overrides[raw])
    var lower = raw.toLowerCase()
    for (var k in overrides) {
      if (String(k).toLowerCase() === lower) return String(overrides[k])
    }
  }
  var entry = resolve(DesktopEntries, raw, overrides)
  if (entry && entry.icon) return String(entry.icon)
  return raw
}

// The icon URL for an icon name.
//
// `appLibrary` is the shell's AppLibrary when the host hands one over, but a
// bar-widget plugin is never given one: shell.qml grants appLibrary only to
// plugins whose manifest declares the "menu" kind. Without it every name went
// through Quickshell.iconPath(), which returns "" for an absolute path and ""
// for a name no theme has -- and an empty source is what made unresolved
// windows fall through to the letter. So this mirrors AppLibrary.iconSource()
// for the no-library case, ending at the generic executable glyph rather than
// at nothing.
function iconUrlFor(Quickshell, appLibrary, name) {
  if (appLibrary) return appLibrary.iconSource(name)

  var value = String(name || "")
  if (value.length === 0) return Quickshell.iconPath("application-x-executable", true)
  if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
  // Percent-encode per segment so spaces in paths such as "Disk Usage.png"
  // don't break Image.source. Same shape as Commons/Util.fileUrl.
  if (value.charAt(0) === "/")
    return "file://" + value.split("/").map(encodeURIComponent).join("/")

  var themed = Quickshell.iconPath(value, true)
  if (themed.length > 0) return themed
  return Quickshell.iconPath("application-x-executable", true)
}

function displayNameFor(DesktopEntries, cls) {
  var entry = resolve(DesktopEntries, cls, null)
  return entry && entry.name ? String(entry.name) : String(cls || "")
}

// Freedesktop convention: a "-symbolic" icon ships a fixed near-white fill and
// the host is expected to recolor it. Same detection Tray.qml uses.
function isSymbolic(name) {
  var base = String(name || "").split("?")[0]
  return base.slice(-9) === "-symbolic"
}
