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

  // 1. Quickshell's own fuzzy matcher, purpose-built for this problem.
  try {
    entry = DesktopEntries.heuristicLookup(cls)
  } catch (e) {
    entry = null
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
