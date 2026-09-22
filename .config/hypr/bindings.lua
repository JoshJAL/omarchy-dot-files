-- Personal keybinding overrides, ported from Omarchy 3's ~/.config/hypr/bindings.conf.
--
-- 25 of your 31 old bindings were byte-for-byte repeats of Omarchy defaults
-- (Terminal, Browser, Tmux, Signal, Obsidian, ChatGPT, Email, X, ...). Omarchy 4
-- ships all of them in default/hypr/bindings/applications.lua, so they are gone
-- from here. Only the 6 genuine differences remain.
--
-- Check what's bound with: omarchy menu keybindings --print

-- Typora, where Omarchy 4 puts Omawrite.
hl.unbind("SUPER + SHIFT + W")
o.bind("SUPER + SHIFT + W", "Typora", { launch = "typora --enable-wayland-ime" })

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
-- only free slot left in the W family (SHIFT=Typora, CTRL=Network,
-- CTRL+ALT=Weather) and reads as the escalation of SUPER+W next door.
--
-- Two or more windows get a confirmation listing the count and the apps;
-- a single window closes outright, same as SUPER+W. Absolute path for the same
-- reason as the bindings above: the exec dispatcher gets no login shell, so the
-- PATH entry for ~/.local/bin is not there.
o.bind("SUPER + ALT + W", "Close all windows on workspace", os.getenv("HOME") .. "/.local/bin/hypr-workspace-close-all")

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
