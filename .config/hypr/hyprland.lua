-- Learn how to configure Hyprland: https://wiki.hypr.land/Configuring/Start/

-- Omarchy's bootstrap keeps path setup out of this user config.
dofile((os.getenv("OMARCHY_PATH") or "/usr/share/omarchy") .. "/default/hypr/bootstrap.lua")

-- ---------------------------------------------------------------------------
-- GPU setup. Both blocks below describe the work laptop's hybrid Intel/NVIDIA
-- graphics and are guarded so they no-op on the desktop, which has an RTX 5080
-- and an AMD iGPU and no Intel anything. Omarchy 4 configures NVIDIA itself in
-- default/hypr/nvidia.lua (NVD_BACKEND, LIBVA_DRIVER_NAME, __GLX_VENDOR_-
-- LIBRARY_NAME), gated on actually detecting the card -- so on the desktop the
-- correct behavior is to leave all of this alone and let Omarchy do it.
--
-- The guard is the Intel iGPU's own by-path node. It exists only on the laptop.
local intel_igpu = "/dev/dri/by-path/pci-0000:00:02.0-card"
local function exists(path)
  local f = io.open(path, "r")
  if f then f:close() return true end
  -- by-path entries are symlinks to device nodes; io.open can fail on those
  -- even when present, so fall back to a stat.
  return os.execute("test -e '" .. path .. "'") == true
end
local on_work_laptop = exists(intel_igpu)

if on_work_laptop then
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
  --
  -- NOTE: this must stay behind the Intel guard. pci-0000:01:00.0-card resolves
  -- on the desktop too, where it is the RTX 5080 rather than the 4070 Mobile --
  -- so unguarded, this block would silently pin the desktop to one card and
  -- hide its AMD iGPU from aquamarine.
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

  -- NOTE: the VA-API driver pin that used to live here has moved to the BOTTOM
  -- of this file. It has to run after require("default.hypr.omarchy"). See the
  -- comment there before moving it back.
end
-- ---------------------------------------------------------------------------

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
--

-- ---------------------------------------------------------------------------
-- VA-API driver pin. MUST stay below require("default.hypr.omarchy").
--
-- 2026-09-03: Pin VA-API to the Intel media driver.
-- Both iHD_drv_video.so (Intel) and nvidia_drv_video.so are installed. With no
-- LIBVA_DRIVER_NAME, libva can select the NVIDIA driver, which allocates NV12
-- dmabuf frames that Intel's EGL (the GPU Hyprland composites on) cannot import.
-- Symptom was eglCreateImage EGL_BAD_MATCH ~30x/sec in every Chromium/Electron
-- app: stutter, missing page styles, unscrollable pages.
-- Measured on one media-heavy page: 908 EGL failures/16s default, 0 with iHD.
-- Benefits Slack, 1Password and other Electron apps too, not just browsers.
--
-- Desktop note: iHD_drv_video.so is not even installed there. Setting this
-- unguarded would point libva at a missing driver and lose hardware video
-- decode entirely -- hence the on_work_laptop guard.
--
-- ORDERING, learned the hard way (2026-09-16). This spent one commit inside the
-- GPU block at the top of the file and silently stopped working. Omarchy's
-- default/hypr/nvidia.lua sets LIBVA_DRIVER_NAME=nvidia, and it loads through
-- omarchy.lua -> envs.lua -> nvidia.lua at the require() above. hl.env is
-- last-write-wins, so anything set BEFORE that require is overwritten. Nothing
-- errors; the laptop just came back from a reboot on the NVIDIA VA-API driver
-- and every Chromium/Electron app rendered badly again.
--
-- It also hid on the desktop, where on_work_laptop is false and the block never
-- ran, so the regression only ever showed up here. Keep this last.
if on_work_laptop then
  hl.env("LIBVA_DRIVER_NAME", "iHD")
end
