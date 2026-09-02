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

-- Dropped from the old config, deliberately:
--
--   SUPER+L -> hyprlock. hyprlock is gone in Quattro and Omarchy 4 already
--   binds omarchy-system-lock to SUPER + CTRL + L, so SUPER+L goes back to
--   its default, "Toggle workspace layout".
