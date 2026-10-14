-- Personal keybinding overrides, ported from Omarchy 3's ~/.config/hypr/bindings.conf.
--
-- 25 of your 31 old bindings were byte-for-byte repeats of Omarchy defaults
-- (Terminal, Browser, Tmux, Signal, Obsidian, ChatGPT, Email, X, ...). Omarchy 4
-- ships all of them in default/hypr/bindings/applications.lua, so they are gone
-- from here. Only the 6 genuine differences remain.
--
-- Check what's bound with: omarchy menu keybindings --print

-- Typora, where Omarchy 4 puts Omawrite on SUPER+SHIFT+W. That slot now belongs
-- to "Reopen closed window" (further down), so Typora moves up one modifier
-- tier to SUPER+CTRL+SHIFT+W. The unbind is still needed: it clears Omawrite.
hl.unbind("SUPER + SHIFT + W")
o.bind("SUPER + CTRL + SHIFT + W", "Typora", { launch = "typora --enable-wayland-ime" })

-- Claude, where Omarchy 4 puts Grok.
hl.unbind("SUPER + SHIFT + ALT + A")
o.bind("SUPER + SHIFT + ALT + A", "Claude", { webapp = "https://claude.ai" })

-- Toggle window split on SUPER+Y. Free in Omarchy 4, which uses SUPER+J.
o.bind("SUPER + Y", "Toggle window split", hl.dsp.layout("togglesplit"))

-- Window width save/restore on End. This keyboard has no Home key, and Omarchy 4
-- puts both halves of the pair there (SUPER+Home restores, SUPER+ALT+Home saves),
-- so neither was reachable. End is unbound everywhere in Omarchy 4, so the pair
-- moves there keeping the same modifier split.
hl.unbind("SUPER + Home")
o.bind("SUPER + End", "Restore window width", "omarchy-hyprland-window-width restore")

hl.unbind("SUPER + ALT + Home")
o.bind("SUPER + ALT + End", "Save window width", "omarchy-hyprland-window-width save")

-- Reset a window to its full tile size. The restore half above only puts back a
-- width that was saved earlier with the save half, and it never touches height,
-- so there is no stock key for "undo the resize I just did by accident". This
-- recomputes the tile from the window's own monitor, so it needs no saved state
-- and is correct on all three displays. Absolute path for the same reason as
-- the screensaver below: the exec dispatcher gets no login shell, so the PATH
-- entry for ~/.local/bin is not there.
o.bind("SUPER + SHIFT + End", "Reset window to full size", os.getenv("HOME") .. "/.local/bin/hypr-window-reset-size")

-- Capture bindings on SUPER+SHIFT (this keyboard has no PrintScreen key).
-- Omarchy 4 puts these on PRINT / SUPER+PRINT / SUPER+CTRL+PRINT.
hl.unbind("SUPER + SHIFT + S") -- Omarchy 4: Google Maps
o.bind("SUPER + SHIFT + S", "Screenshot", "omarchy-capture-screenshot")
o.bind("SUPER + SHIFT + T", "Extract text (OCR) from screen", "omarchy-capture-text")
o.bind("SUPER + SHIFT + I", "Color picker", "pkill hyprpicker || hyprpicker -a")

-- Screensaver on demand, with random artwork. Absolute path on purpose:
-- Hyprland's exec dispatcher does not use a login shell, so the PATH shadow in
-- ~/.local/bin that covers the *automatic* idle screensaver would not apply
-- here. Both routes end up in the same script.
hl.unbind("SUPER + S") -- Omarchy 4: Toggle scratchpad
o.bind("SUPER + S", "Random screensaver", os.getenv("HOME") .. "/.local/bin/omarchy-launch-screensaver")

-- Taking SUPER+S above left the scratchpad with no way back: SUPER+ALT+S still
-- sends a window to special:scratchpad, but nothing reveals it again, and every
-- other SUPER+<mods>+S is spoken for (screenshot, share, move-to-scratchpad).
-- SUPER+grave is unbound and is the usual Quake-style drop-down key anyway.
--
-- Not hl.dsp.workspace.toggle_special: that only *reveals* the scratchpad as an
-- overlay and the window never leaves it, so there is still no way to get a
-- window properly back. The script is a real round trip -- empty scratchpad
-- stows the focused window, occupied scratchpad empties onto the workspace in
-- front of you. Absolute path for the same reason as the bindings above: the
-- exec dispatcher gets no login shell, so ~/.local/bin is not on PATH.
o.bind("SUPER + grave", "Scratchpad stow/restore", os.getenv("HOME") .. "/.local/bin/hypr-scratchpad-toggle")

-- Workspace cycling stays on the focused monitor. Omarchy 4 binds these to
-- e+1/e-1, which walk every open workspace across all displays -- with three
-- monitors that means Tab can yank focus onto a different screen. "m+1"/"m-1"
-- are the same thing scoped to the current monitor, and they wrap at the ends.
hl.unbind("SUPER + TAB") -- Omarchy 4: Next workspace (e+1, all monitors)
o.bind("SUPER + TAB", "Next workspace on this monitor", hl.dsp.focus({ workspace = "m+1" }))

hl.unbind("SUPER + SHIFT + TAB") -- Omarchy 4: Previous workspace (e-1, all monitors)
o.bind("SUPER + SHIFT + TAB", "Previous workspace on this monitor", hl.dsp.focus({ workspace = "m-1" }))

-- Close every window on the focused workspace. Omarchy 4 has SUPER+W for one
-- window and CTRL+ALT+DELETE for every window on every workspace -- on three
-- monitors the latter wipes all three screens and dumps you on workspace 1, so
-- there was nothing for "clear the screen I am looking at". SUPER+ALT+W is the
-- only free slot left in the W family (SHIFT=Reopen closed window,
-- CTRL=Network, CTRL+ALT=Weather) and reads as the escalation of SUPER+W next
-- door.
--
-- Two or more windows get a confirmation listing the count and the apps;
-- a single window closes outright, same as SUPER+W. Absolute path for the same
-- reason as the bindings above: the exec dispatcher gets no login shell, so the
-- PATH entry for ~/.local/bin is not there.
o.bind("SUPER + ALT + W", "Close all windows on workspace", os.getenv("HOME") .. "/.local/bin/hypr-workspace-close-all")

-- Reopen the window you just closed, on SUPER+SHIFT+W. Hyprland keeps no
-- history of closed windows, so SUPER+W (or SUPER+ALT+W, or an app quitting) was
-- final. This records each close and ~/.local/bin/hypr-window-reopen relaunches
-- the newest one. Repeated presses walk backwards, so a bulk close from
-- SUPER+ALT+W or CTRL+ALT+DELETE can be undone one window at a time. Only the
-- app comes back; its contents and position do not.
--
-- The record is a tmpfs file, not an in-memory table: `hyprctl reload` re-runs
-- this whole file in a fresh Lua state (checked: a table here is empty after a
-- reload), so a table would lose the history on every config edit. The file is
-- in $XDG_RUNTIME_DIR, so it is gone at logout and never lands on disk. It stays
-- short by construction: at most CLOSED_MAX lines, and a line older than
-- CLOSED_MAX_AGE is dropped on the next close and ignored by the script. Those
-- two numbers are duplicated in hypr-window-reopen (MAX_AGE) -- keep them in step.
--
-- Line format, one per close, oldest first: <epoch> TAB <class> TAB <argv>,
-- with the argv joined by 0x1f. The argv is a fallback for apps with no .desktop
-- entry; the script prefers the entry, because Helium webapps and ordinary Helium
-- windows are one process and share an argv. It is read at window.open (the
-- process may be gone by the time of the close) and again at close for windows
-- that were already open before the last reload.
--
-- window.close fires for every kind of close, so an app quitting itself is
-- recorded too; the expiry bounds how long it lingers. Windows with an empty
-- class are skipped: they are transient dialogs, like the Chromium "Profile
-- error occurred" ones. The window.destroy payload has no fields (address is
-- nil), so the per-window argv table is cleared at close instead.
local CLOSED_FILE = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/hypr-closed-windows.tsv"
local CLOSED_MAX = 10
local CLOSED_MAX_AGE = 60 * 60 -- seconds
local opened_argv = {}

local function read_argv(pid)
  local f = pid and io.open("/proc/" .. pid .. "/cmdline", "rb")
  if not f then
    return nil
  end
  local raw = f:read("a")
  f:close()
  if not raw or raw == "" then
    return nil
  end
  return (raw:gsub("[\t\r\n]", " "):gsub("%z$", ""):gsub("%z", "\31"))
end

hl.on("window.open", function(window)
  pcall(function()
    opened_argv[window.address] = read_argv(window.pid)
  end)
end)

hl.on("window.close", function(window)
  pcall(function()
    local argv = opened_argv[window.address] or read_argv(window.pid)
    opened_argv[window.address] = nil

    local class = (window.class or ""):gsub("[\t\r\n]", " ")
    if class == "" then
      return
    end

    local now = os.time()
    local keep = {}
    local f = io.open(CLOSED_FILE, "r")
    if f then
      for line in f:lines() do
        local t = tonumber(line:match("^(%d+)\t"))
        if t and now - t < CLOSED_MAX_AGE then
          keep[#keep + 1] = line
        end
      end
      f:close()
    end
    keep[#keep + 1] = table.concat({ now, class, argv or "" }, "\t")
    while #keep > CLOSED_MAX do
      table.remove(keep, 1)
    end

    -- Write beside the file and rename over it, so the script never reads half
    -- of one.
    local tmp = CLOSED_FILE .. ".lua"
    local out = io.open(tmp, "w")
    if out then
      out:write(table.concat(keep, "\n"), "\n")
      out:close()
      os.rename(tmp, CLOSED_FILE)
    end
  end)
end)

-- Takes SUPER+SHIFT+W from Typora (now SUPER+CTRL+SHIFT+W, see the top of this
-- file); the unbind up there already cleared Omarchy's Omawrite. Absolute path:
-- the exec dispatcher gets no login shell, so ~/.local/bin is not on PATH.
o.bind("SUPER + SHIFT + W", "Reopen closed window", os.getenv("HOME") .. "/.local/bin/hypr-window-reopen")

-- Dropped from the old config, deliberately:
--
--   SUPER+L -> hyprlock. hyprlock is gone in Quattro and Omarchy 4 already
--   binds omarchy-system-lock to SUPER + CTRL + L, so SUPER+L goes back to
--   its default, "Toggle workspace layout".

-- Screens off without locking, on SUPER+SHIFT+L. Omarchy gives you Lock
-- (SUPER+CTRL+L, blanks *and* takes a password to get back) and Suspend, but
-- nothing for "just turn the monitors off, I'm still here". This is that:
-- DPMS off, session untouched, any key or mouse move brings them back, because
-- Omarchy sets key_press_enables_dpms and mouse_move_enables_dpms in
-- default/hypr/input.lua.
--
-- SUPER+L is "Toggle workspace layout" and SUPER+CTRL+L is the lock, so SHIFT
-- is the free slot in the L family and reads as the softer sibling of the lock
-- next door.
--
-- The 1s delay is load-bearing: letting go of the keys is itself an input
-- event, so blanking immediately would wake the screens right back up. The
-- sleep puts the blank after the key release. Same one-liner is on the
-- "Screens Off" row in ~/.config/omarchy/extensions/omarchy-menu.jsonc.
o.bind("SUPER + SHIFT + L", "Screens off (no lock)", "sleep 1; omarchy-brightness-display off")

hl.bind("CTRL + SHIFT + 2", hl.dsp.global("com.t3tools.T3Code:capture-window"))

-- Launch the work trio (Outlook, Teams, Slack) in one go. Skips apps that are
-- already open. SUPER+SHIFT+ALT+W is free; W for "work". Absolute path because
-- the exec dispatcher gets no login shell, so ~/.local/bin is not on PATH.
o.bind("SUPER + SHIFT + ALT + W", "Launch work apps", os.getenv("HOME") .. "/.local/bin/launch-work-apps")

-- Rounded corners on/off, for every theme. SUPER+BACKSPACE (transparency),
-- SUPER+SHIFT+BACKSPACE (gaps) and SUPER+CTRL+BACKSPACE (square aspect) are
-- Omarchy's look'n'feel toggles; ALT is the free slot in that family.
-- The script writes a toggle flag that loads after the theme, so it overrides
-- whatever rounding the theme sets. `omarchy-corners-toggle auto` hands control
-- back to the theme. Absolute path: exec gets no login shell, so ~/.local/bin
-- is not on PATH.
o.bind("SUPER + ALT + BACKSPACE", "Toggle rounded corners", os.getenv("HOME") .. "/.local/bin/omarchy-corners-toggle")

-- Universal select all on SUPER+A, the missing sibling of Omarchy's universal
-- copy/cut/paste on SUPER+C/X/V (default/hypr/bindings/clipboard.lua). Plain
-- SUPER+A was unbound; only the modified variants (Agent, Audio, ChatGPT,
-- Claude) use A.
--
-- Same send_key_state down/up split as the stock clipboard bindings, which
-- works around Hyprland leaving synthetic key state stuck. Ghostty gets
-- CTRL+SHIFT+A, its built-in select_all (the whole scrollback), because plain
-- Ctrl+A there is the tmux-style prefix set in ~/.config/ghostty/config. Follow
-- with SUPER+C to copy it. Other terminals are skipped: they have no select-all
-- and Ctrl+A is readline "start of line". Terminal tag comes from
-- default/hypr/apps/terminals.lua, as in the stock file.
local function send_select_all(mods)
  hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = "A", state = "down" }))
  hl.timer(function()
    hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = "A", state = "up" }))
  end, { timeout = 50, type = "oneshot" })
end

o.bind("SUPER + A", "Universal select all", function()
  local window = hl.get_active_window()
  for _, tag in ipairs(window and window.tags or {}) do
    if tag:gsub("%*$", "") == "terminal" then
      if window.class == "com.mitchellh.ghostty" then
        send_select_all("CTRL SHIFT")
      end
      return
    end
  end

  send_select_all("CTRL")
end)

-- Bar transparency on/off. Window transparency is SUPER+BACKSPACE and that
-- family is full (gaps, square aspect, rounded corners), so the bar gets
-- SUPER+ALT+T, next to SUPER+T (floating/tiling). Stock command; it flips
-- bar.transparent in ~/.config/omarchy/shell.json, which the shell hot-reloads.
o.bind("SUPER + ALT + T", "Toggle bar transparency", "omarchy bar transparent toggle")
