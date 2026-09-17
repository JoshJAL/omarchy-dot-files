# joshjal.taskbar

One button per open window on **this monitor**, with a live hover preview.
Replaces waybar's `wlr/taskbar`, which Omarchy 4 ("Quattro") dropped along with
waybar itself.

Enable via `~/.config/omarchy/shell.json`:

```json
{ "id": "joshjal.taskbar", "previewDelay": 320 }
```

## Settings

All are optional and hot-reload when `shell.json` is saved.

| Key | Default | Meaning |
|---|---|---|
| `previewDelay` | `320` | ms to dwell before the preview opens. `-1` disables previews and restores the plain title tooltip. |
| `previewWidth` | `320` | Preview card width, in pixels. |
| `previewHeight` | `200` | Max height of the captured image; taller windows are letterboxed, not stretched. |
| `iconSize` | `14` | Icon size, matching the old waybar `icon-size`. |
| `iconSizeMin` | `10` | Floor that icons shrink to as the window count grows. |
| `maxIcons` | `0` | Show at most this many icons; the rest collapse behind a "+N" chip. `0` = unlimited. A count rather than a width because a plugin cannot measure the room it has — `ModuleSlot` asks the widget for its `implicitWidth`, so the constraint only ever flows upward, and `PluginBarApi` carries no geometry. |
| `includeSpecial` | `false` | Include scratchpad / special workspaces. Parked windows get a badge, sort last, appear on **every** bar regardless of `allOutputs`, and restore on left click. See *Scratchpad* below. |
| `allOutputs` | `false` | Off, each monitor's taskbar lists only its own windows. On, every taskbar lists every window — so the same window appears on all of them. |
| `sortBy` | `"workspace"` | `"workspace"` groups by workspace, then by first-seen order. `"creation"` drops the workspace term and orders purely by age, so icons keep their slot when a window changes workspace. |
| `showTitles` | `false` | Draw the window title beside each icon. Ignored on vertical bars — there is no width to spend on it. |
| `maxTitleWidth` | `140` | Titles wider than this are elided. Only applies with `showTitles`. |
| `dimInactive` | `true` | Unfocused windows render at half opacity. `false` renders every icon at full strength. |
| `middleClick` | `"close"` | Middle-click action: `close`, `bring`, `focus` or `none`. |
| `rightClick` | `"menu"` | Right-click action: `menu`, `close`, `bring`, `focus` or `none`. `menu` is the context menu below. |
| `classIconOverrides` | `{}` | `{"SomeClass": "icon-name"}` for apps whose window class matches no desktop entry — common for Electron apps and PWAs. |

`bring` pulls the window onto the workspace you are already looking at, rather
than jumping you to wherever it lives. The destination is the active workspace
of *the monitor whose taskbar you clicked*, since one widget instance exists per
screen. An unrecognised action string falls through to `focus`, so a typo
degrades to an ordinary click instead of a dead icon.

## Scratchpad

With `includeSpecial` on, a window parked in a special workspace appears with an
accent dot on its outer corner, and **left-clicking it brings it back** to the
workspace in front of you rather than focusing it in place.

Three deliberate departures from how ordinary windows are treated:

- **Parked windows ignore the monitor filter.** Hyprland pins a special
  workspace to whatever monitor it was opened on, but nothing about the
  scratchpad is per-monitor from the user's side: one key stows from anywhere
  and restores to wherever you are. Honouring the pin would show the icon only
  on a screen you may not be looking at, which is the exact failure the
  indicator exists to prevent. So they appear on every bar.
- **They sort last, not first.** Special workspaces carry negative ids, so the
  default `sortBy: "workspace"` would otherwise sort them to the front and shove
  every ordinary icon right the moment you park something. `sortBy: "creation"`
  is exempt — that mode promises icons keep their slot, and forcing specials
  last would break the one guarantee it exists to make.
- **They do not dim.** A parked window is not inactive, it is elsewhere.
  `dimInactive` would make the badge fight a faded icon and read as merely
  unfocused, which is the one thing it must not look like.

**Why this exists.** `SUPER+ALT+S` sends the focused window to
`special:scratchpad` with no feedback of any kind — the window simply vanishes.
Press it, see nothing happen, press again, and Hyprland has meanwhile moved
focus to the next window on that workspace, so the second press takes that one
too. Three presses empties a workspace and looks exactly like a bug. The badge
is the missing feedback.

The companion half is `~/.local/bin/hypr-scratchpad-toggle` on `SUPER+grave`:
empty scratchpad stows the focused window, occupied scratchpad restores all of
it. Omarchy's stock `hl.dsp.workspace.toggle_special` only *reveals* the
scratchpad as an overlay — the window never leaves it — which is why it is not
bound here.

## Behavior

- **Scope:** every window on this monitor, across all of its workspaces. A bar
  exists per monitor, so each instance filters to its own.
- **Left click** focuses — or restores, if the window is parked in a
  scratchpad. **Middle click** closes, **right click** opens a menu:
  Close window · Move to workspace ▸ · Toggle floating · Move to `<monitor>`.
  Moving to a workspace **follows** the window, matching `SUPER+SHIFT+n`; moving
  to a monitor does not, since the window becomes visible there anyway and
  following would yank focus across screens. The monitor rows are named for the
  actual monitors and disappear on a single-monitor machine.
- The menu acts on the window you **right-clicked**, which is usually not the
  focused one — that is the whole point, and why the card carries a title header
  naming its target.
- **Hover** shows a live capture; a window with no capturable content falls back
  to a large icon, its class, title and workspace.

## Four things that will bite whoever edits this

**1. Never touch Hyprland state from inside `onRawEvent`.**

The handler runs inside Quickshell's IPC socket read. Mutating a property that a
binding reacts to — or calling `Hyprland.monitorFor()` / `refreshToplevels()` —
re-enters that machinery while it is still parsing the event, and segfaults the
whole shell:

```
Qt::endPropertyUpdateGroup            (libQt6Core)
QAbstractSocketPrivate::canReadNotification  (libQt6Network)
```

A crash-looping shell takes the bar, the wallpaper and every popup with it, so
this is not a cosmetic bug. `onRawEvent` here only sets flags and restarts
timers; everything that reaches into Hyprland happens in the coalesce timer,
off the IPC callstack. `monitorId` is a plain property set by `resolveMonitor()`,
never a binding.

**2. The preview must not use the real `bar`.**

`PopupCard.onOpenChanged` calls `bar.requestPopout()` unconditionally, and
`Bar.requestPopout` closes whatever popout is currently open. For a click popup
that is correct. For a *hover* preview it means sweeping the pointer along the
taskbar would slam shut an open clock calendar or audio panel. `PreviewBarShim`
mirrors the four members `PopupCard` actually reads and makes the popout calls
inert. The context menu keeps the real `bar`, where taking the slot is correct.

**3. Never put a `HyprlandToplevel` in a `ListModel` role.**

A QObject stored in a model role becomes a dangling C++ pointer the moment its
owner destroys it, and the next read of that role segfaults inside
`QQmlListModel::data`. Omarchy hit this itself and documented it in
`plugins/notifications/Service.qml`. The model here holds primitives only; the
toplevel lives in a plain JS map on the widget root, keyed by address. Nothing
in a delegate needs it — every action dispatches by address, and the preview
gets its capture source handed over separately.

Related: `ListModel` fixes each role's type from the **first** row inserted. A
`null` at that moment poisons the role for the life of the process, and rows
carrying keys the model has not seen are silently dropped. `WindowModel.row()`
is the single factory precisely so every row has all eight keys, always coerced.

**4. Never make a `PopupCard` its own `owner`.**

`PopupCard.close()` does `if ("close" in owner) owner.close()`, and
`"close" in card` is true — so `owner: theCard` is unbounded recursion. The menu
uses `owner: root` (and the root defines `close()`); the preview and overflow
each get a dedicated owner `QtObject`. Distinct owners also give each popup its
own `coordinatorKey`, which is what makes them close each other correctly.

## Other notes

- **A bar-widget plugin never gets `shell.appLibrary`.** `shell.qml` hands it
  only to plugins whose manifest declares the `"menu"` kind, so `bar.shell.appLibrary`
  is `null` here and `IconModel.iconUrlFor()` has to do the job itself:
  absolute `Icon=` paths become percent-encoded `file://` URLs, names go through
  `Quickshell.iconPath()`, and the last stop is `application-x-executable`.
  Going through `Quickshell.iconPath()` alone returns `""` for both an absolute
  path and an unknown name, and an empty `Image.source` is what dropped windows
  through to the letter fallback.
- **Chromium web apps have no `StartupWMClass` and no desktop id.** A `--app=URL`
  window's class is built from the URL — `host + "_" + path` with every
  filename-illegal character replaced by `_`, wrapped as
  `<browser>-<app name>-<profile>`, so `https://teams.microsoft.com/v2/` arrives
  as `chrome-teams.microsoft.com__v2_-Default`. The only link back to the
  `.desktop` is the URL on its `Exec` line. `IconModel` matches on that, comparing
  alphanumerics-only keys by **common prefix** rather than equality: the mangling
  is lossy (a URL that went through desktop-entry field-code stripping arrives
  with `%2F` as `F`), and prefix length is also what separates two entries on one
  host, such as Outlook mail from Outlook calendar.
- Quickshell reports `HyprlandToplevel.address` **without** the `0x` prefix, but
  Hyprland's `address:` selector requires it. Mismatched, dispatches fail
  *silently* — a warning and exit 0. `Dispatch.selector()` normalizes it.
- This Hyprland uses the Lua dispatcher dialect. `hyprctl dispatch workspace 5`
  is a parse error here; it is `hl.dsp.focus({ workspace = "5" })`.
- Toplevels can surface before their Hyprland IPC blob arrives, with `workspace`,
  `monitor` and `lastIpcObject` all empty. Without the `pendingRetry` path those
  windows are dropped from every bar. This is not rare — it happens on every
  shell start.
- `BarIconButton` has no press-time hook: `WidgetButton` emits `pressed` from
  `onClicked`, i.e. on **release**. So the menu opens on release, and there is
  no trailing release to swallow. Stacking a second `hoverEnabled` MouseArea to
  get press-time events would break `tooltipHovered`, and with it the whole
  preview state machine.
- The menu closes **before** it dispatches. `HyprlandFocusGrab.active` is still
  true while a row handler runs, and dispatching a focus or move command then
  can land focus on the grab owner or bounce it to the bar. The target is
  captured into plain properties first (closing destroys the row delegate and
  its ids stop resolving), and the dispatch runs from `onVisibleChanged` at the
  end of the card's 140ms fade — a real barrier, where `Timer{interval:0}` only
  yields the event loop and can still land inside a live grab.
- Live capture works on windows sitting on **hidden workspaces**: Hyprland's
  toplevel export re-renders the window rather than reading back the monitor.
  That is why there is no snapshot cache.

## Developing safely

Do not iterate against the live shell. Run a second Quickshell instance with a
mock bar, outside `~/.config/omarchy/plugins/` so the plugin scanner cannot see
it, and a crash costs you nothing:

```
qs -p ~/taskbar-sandbox/shell/sandbox.qml
```

Its `taskbar/` directory is symlinked to this one, so there is a single source
of truth. It exposes an IPC handler (`qs -p … ipc call tb state|menu|hover|…`)
because this machine has no pointer synthesis — no ydotool, and the user is no
longer in the `input` group, so `/dev/uinput` is unreachable — and clicks
therefore cannot be scripted.

**What the sandbox cannot prove.** `PopupCard.availableCardHeight` subtracts the
anchor window's height on the assumption that window is the bar, a ~26px strip.
The harness anchors to a full-size `FloatingWindow`, so that subtraction eats
the screen and every popup clamps to the 120px floor. Popup **sizing and
placement**, and outside-click dismissal, are only meaningful against the real
bar. Logic, state and churn all validate fine in the sandbox.

`delegateCreations` on the widget root is the churn probe: if it climbs while
windows are merely changing title, the incremental sync has regressed.

**Two mock-bar names that fail silently.** `WidgetButton` reads
`bar.barForeground`, *not* `bar.foreground`, and the Color singleton exposes
`Color.bar.text`, *not* `Color.bar.foreground`. Get either wrong and QML assigns
undefined to a color property with only a warning, then renders a default close
enough to miss. `WidgetButton` also calls `bar.showTooltip`/`bar.hideTooltip`
unconditionally, so a mock lacking them throws a TypeError on every pointer
movement and buries every real warning in the noise. The harness defines all of
them; a clean run is one portal warning and nothing else.

The harness window is itself a Hyprland toplevel, so it lists itself in its own
taskbar — and if a special workspace is revealed when it opens, Hyprland places
it there and it shows up flagged special. The live bar is a layer surface, not a
toplevel, so it never lists itself.
