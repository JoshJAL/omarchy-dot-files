-- See https://wiki.hypr.land/Configuring/Basics/Monitors/
-- List current monitors and supported resolutions with: hyprctl monitors all

-- GDK_SCALE is set per machine below, since GTK only honors whole numbers and
-- the machines differ: the work laptop and the desktop run every display at
-- scale 1.0 (GDK_SCALE 1, not Omarchy's default of 2, which assumes a HiDPI
-- panel), while the Surface Book's 3000x2000 panel is HiDPI and keeps 2.
local machine = require("hypr.machine")

-- Both laptops' panels are eDP-1, and Omarchy's lid/wake script
-- (omarchy-hyprland-monitor-clamshell) reads this file as text, taking the
-- FIRST eDP-1 rule's scale and ignoring the branches below. With literals it
-- saw the work laptop's 1.0 and forced the Surface to 1 on every lid open,
-- unlock and screensaver wake. Every eDP-1 rule therefore names this local,
-- whose value is an expression the script cannot resolve, so it leaves the
-- compositor's (correct) scale alone.
local internal_scale = machine.is(machine.SURFACE) and 2.0 or 1.0

-- Three machines share this repo and their connector names overlap -- the laptop
-- and the desktop both have an HDMI-A-1 -- so the layouts cannot simply be
-- concatenated: the desktop would pick up the laptop's 3440x1440 HDMI rule the
-- moment anything was plugged into its HDMI port. Branch on the machine's DMI
-- id (hypr/machine.lua), not on connector presence: a second laptop has an
-- eDP-1 too, and the old test sent it to the work laptop's layout.
--
-- An unrecognised machine gets NO explicit rules, deliberately. With no
-- hl.monitor call Hyprland auto-arranges every display at its preferred mode,
-- which is a working desktop; a guessed layout is not. See NEW-MACHINE.md.
if machine.is(machine.LAPTOP) then
  hl.env("GDK_SCALE", "1")

  -- Work laptop, 2026-10-01. DVI-I-1 (DisplayLink) is rotated to portrait
  -- (transform = 3), so it occupies 1080x1920 in layout space. Origin is 0x0.
  --
  --   DVI-I-1   top-left (3440, 0)    1080x1920, right of the ultrawide
  --   HDMI-A-1  top-left (0, 480)     3440x1440; y = 1920 - 1440 puts its bottom
  --                                   edge level with the portrait panel's
  --   eDP-1     top-left (2480, 1920) 1920x1200; flush under both bottom edges and
  --                                   centred on the x = 3440 seam (3440 - 1920/2)
  --
  -- The DisplayLink connector number is not stable: evdi hands out a new one
  -- whenever the dock re-enumerates (it became DVI-I-2 on 2026-10-07 after a
  -- port swap, which silently dropped the rotation). Match the panel by EDID
  -- description instead of by connector name.
  hl.monitor({ output = "desc:LG Electronics LG IPS FULLHD 0x0003B989", mode = "1920x1080@60.0", position = "3440x0", scale = 1.0, vrr = 0, transform = 3 })
  hl.monitor({ output = "HDMI-A-1", mode = "3440x1440@59.97", position = "0x480",     scale = 1.0, vrr = 0 })
  hl.monitor({ output = "eDP-1",    mode = "1920x1200@165.0", position = "2480x1920", scale = internal_scale, vrr = 0 })
elseif machine.is(machine.DESKTOP) then
  hl.env("GDK_SCALE", "1")

  -- Desktop (RTX 5080, both outputs on the NVIDIA card). LG ultrawide on top,
  -- Acer centered underneath: (3440 - 2560) / 2 = 440.
  --
  -- Two corrections to what nwg-displays generated on 2026-09-13:
  --   * DP-1 is a 240 Hz panel and had been left at 59.95, its lowest
  --     advertised mode.
  --   * the origin is normalized to 0x0. nwg-displays had started the pair at
  --     x=2560, leaving 2560px of dead coordinate space left of every window.
  hl.monitor({ output = "DP-2", mode = "3440x1440@99.98",  position = "0x0",      scale = 1.0 })
  hl.monitor({ output = "DP-1", mode = "2560x1440@240.00", position = "440x1440", scale = 1.0 })
elseif machine.is(machine.SURFACE) then
  -- Surface Book (Intel HD 520 only). One 13.5" 3000x2000 panel, ~263 DPI, so it
  -- runs HiDPI at scale 2 -- 1500x1000 logical -- and GTK gets GDK_SCALE 2.
  -- Mode string copied exactly as `hyprctl monitors all` lists it (59.98, the
  -- panel's own 59.985 rounded as the mode list rounds it).
  --
  -- Anything plugged in is placed to the right of the panel at its preferred
  -- mode and an auto-picked scale. That catch-all rule comes first; the panel's
  -- explicit rule after it wins for eDP-1. Lower the eDP-1 scale (e.g. 1.5) if
  -- 1500x1000 logical is too cramped.
  hl.env("GDK_SCALE", "2")
  hl.monitor({ output = "",      mode = "preferred",        position = "auto",  scale = "auto" })
  hl.monitor({ output = "eDP-1", mode = "3000x2000@59.98",  position = "0x0",   scale = internal_scale })
end
