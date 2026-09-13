-- See https://wiki.hypr.land/Configuring/Basics/Monitors/
-- List current monitors and supported resolutions with: hyprctl monitors all

-- Every display on both machines runs at scale 1.0, so GDK_SCALE is 1, not
-- Omarchy's default of 2 (which assumes a HiDPI panel). GTK only honors whole
-- numbers.
hl.env("GDK_SCALE", "1")

-- Two machines share this repo and their connector names overlap -- both have
-- an HDMI-A-1 -- so the two layouts cannot simply be concatenated: the desktop
-- would pick up the laptop's 3440x1440 HDMI rule the moment anything was
-- plugged into its HDMI port. Branch on the laptop's built-in panel instead.
-- An eDP-1 connector exists under /sys/class/drm only on the laptop, and it is
-- there whether or not the lid display is currently active, which makes it a
-- stabler discriminator than the hostname (both machines answer "omarchy").
local function has_internal_panel()
  local probe = io.popen("ls -d /sys/class/drm/*-eDP-1 2>/dev/null")
  if not probe then
    return false
  end
  local found = probe:read("*l")
  probe:close()
  return found ~= nil and found ~= ""
end

if has_internal_panel() then
  -- Work laptop. Ported from monitors.conf (nwg-displays, 2026-08-21).
  hl.monitor({ output = "eDP-1",    mode = "1920x1200@165.0", position = "2351x1440", scale = 1.0 })
  hl.monitor({ output = "HDMI-A-1", mode = "3440x1440@59.97", position = "0x0",       scale = 1.0 })
  hl.monitor({ output = "DVI-I-1",  mode = "1920x1080@60.0",  position = "3440x360",  scale = 1.0 })
else
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
end
