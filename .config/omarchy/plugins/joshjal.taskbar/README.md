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
| `includeSpecial` | `false` | Include scratchpad / special workspaces. |
| `classIconOverrides` | `{}` | `{"SomeClass": "icon-name"}` for apps whose window class matches no desktop entry — common for Electron apps and PWAs. |

## Behavior

- **Scope:** every window on this monitor, across all of its workspaces. A bar
  exists per monitor, so each instance filters to its own.
- **Left click** focuses, **middle click** closes, **right click** opens a menu.
- **Hover** shows a live capture; a window with no capturable content falls back
  to a large icon, its class, title and workspace.

## Two things that will bite whoever edits this

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

## Other notes

- Quickshell reports `HyprlandToplevel.address` **without** the `0x` prefix, but
  Hyprland's `address:` selector requires it. Mismatched, dispatches fail
  *silently* — a warning and exit 0. `Dispatch.selector()` normalizes it.
- This Hyprland uses the Lua dispatcher dialect. `hyprctl dispatch workspace 5`
  is a parse error here; it is `hl.dsp.focus({ workspace = "5" })`.
- Toplevels can surface before their Hyprland IPC blob arrives, with `workspace`,
  `monitor` and `lastIpcObject` all empty. Without the `pendingRetry` path those
  windows are dropped from every bar. This is not rare — it happens on every
  shell start.
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
