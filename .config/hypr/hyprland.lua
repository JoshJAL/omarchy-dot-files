-- Learn how to configure Hyprland: https://wiki.hypr.land/Configuring/Start/

-- Omarchy's bootstrap keeps path setup out of this user config.
dofile((os.getenv("OMARCHY_PATH") or "/usr/share/omarchy") .. "/default/hypr/bootstrap.lua")

-- Pin the DRM device order so the Intel iGPU is always the primary render
-- device, rather than leaving it to probe order. Ported from the old
-- envs.conf, which was never actually sourced by anything.
--
--   pci-0000:00:02.0  Intel Iris Xe   (eDP-1)
--   pci-0000:01:00.0  RTX 4070 Mobile (HDMI-A-1)
--   platform-evdi.0   DisplayLink     (DVI-I-1)
--
-- The by-path ids are the only stable way to name these: card numbers shift
-- between boots because evdi is a platform device that only appears when
-- DisplayLink is attached. But aquamarine splits AQ_DRM_DEVICES on ":", and
-- PCI by-path names are full of colons, so handing them over verbatim shreds
-- each path into fragments and drops every PCI card -- leaving only the
-- colon-free evdi entry, one monitor, and software rendering. In the log
-- (aquamarine 0.14.0) that reads:
--
--   ERR drm: Failed to canonicalize path /dev/dri/by-path/pci-0000
--   ERR drm: Explicit device 02.0-card not found
--
-- So resolve the symlinks here, at config-read time, and hand aquamarine the
-- colon-free /dev/dri/cardN paths for this boot. Entries that don't resolve
-- are dropped, which is what keeps this correct when DisplayLink is unplugged
-- and there is no evdi card at all.
local drm_cards = {}
for _, by_path in ipairs({
  "/dev/dri/by-path/pci-0000:00:02.0-card",
  "/dev/dri/by-path/pci-0000:01:00.0-card",
  "/dev/dri/by-path/platform-evdi.0-card",
}) do
  local probe = io.popen("readlink -e -- '" .. by_path .. "' 2>/dev/null")
  if probe then
    local node = probe:read("*l")
    probe:close()
    if node and node ~= "" then
      drm_cards[#drm_cards + 1] = node
    end
  end
end

-- Takes effect on a full Hyprland restart, not `hyprctl reload`. If a display
-- fails to come up after a relogin, delete this block from a TTY.
if #drm_cards > 0 then
  hl.env("AQ_DRM_DEVICES", table.concat(drm_cards, ":"))
end

-- Disable all Omarchy default bindings. Add your own in hypr/bindings.lua.
-- omarchy_default_bindings = false
--
-- Or disable only bindings for Omarchy's preinstalled apps/web apps while
-- keeping core window-manager bindings:
-- omarchy_preinstalled_bindings = false

-- Load Omarchy defaults.
require("default.hypr.omarchy")

-- Put your personal overrides in these files. They're loaded after Omarchy's
-- defaults so package updates can improve the defaults without rewriting your
-- ~/.config/hypr files.
require("hypr.monitors")
require("hypr.input")
require("hypr.bindings")
require("hypr.looknfeel")
require("hypr.autostart")

-- Toggle config flags dynamically.
require("default.hypr.toggles")

-- Add any other personal Hyprland configuration below.
-- o.window("qemu", { workspace = "5" })
-- Append to the bottom of the freshly installed ~/.config/hypr/hyprland.lua,
-- AFTER require("default.hypr.toggles").
--
-- Ported from the `plugin:dynamic-cursors { ... }` block in the old hyprland.conf.
-- Note the Lua key is `dynamic_cursors` with an underscore, where hyprlang used
-- a hyphen. This follows the plugin's own README:
-- https://github.com/VirtCode/hypr-dynamic-cursors

-- hyprpm rebuilds this .so for each Hyprland version; the path is stable.
-- Loading here rather than via `exec-once = hyprpm reload` is what makes the
-- config below take effect: exec-once fires after the config is read, so the
-- guard would still be false by then.
hl.plugin.load("/var/cache/hyprpm/joshjal/dynamic-cursors/dynamic-cursors.so")

-- The guard is the plugin author's documented pattern, and it is what keeps a
-- failed load (hyprpm not yet rebuilt for a new Hyprland) from turning into a
-- config error. If the plugin ever stops building, delete this whole block --
-- nothing else depends on it.
if hl.plugin.dynamic_cursors then
  hl.config({ plugin = { dynamic_cursors = {
    mode = "none",
    shake = {
      enabled = true,
      threshold = 6.0,
      base = 4.0,
      speed = 4.0,
      timeout = 2000,
    },
  }}})
end
