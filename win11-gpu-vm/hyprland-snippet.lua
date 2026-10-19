-- hyprland-snippet.lua  -  let Hyprland let go of the passthrough GPU.
--
-- Merge this block into your own ~/.config/hypr/hyprland.lua (Omarchy 4, Lua config).
-- Do not paste it in blindly. If your config already sets AQ_DRM_DEVICES (or the EGL/Vulkan/GLX
-- variables below), merge the logic instead of setting the variable twice: the last hl.env()
-- call for a name wins, and a second AQ_DRM_DEVICES would silently undo this one.
--
-- WHY IT EXISTS
-- A GPU can only go to the Windows VM (vfio-pci) when nothing on the host has it open. Hyprland, its
-- children (Xwayland, ...) and even the NVIDIA EGL/Vulkan libraries open the card just by
-- enumerating GPUs, and that blocks the unbind. So while the VM owns the GPU, Hyprland must be
-- started without it.
--
-- HOW IT IS SWITCHED
-- `winvm-gpu on` creates the flag file ~/.config/hypr/gpu-vm-mode and `winvm-gpu off` removes it.
-- This block does nothing at all unless that file exists, so it is safe to leave in permanently.
--
-- IMPORTANT: this file is read only when Hyprland starts. Creating or removing the flag does
-- nothing until you LOG OUT AND BACK IN (`hyprctl reload` is not enough).
--   winvm-gpu on   1st run: creates the flag.  Log out/in.  2nd run: binds the GPU to vfio-pci.
--   winvm-gpu off  removes the flag.  Log out/in to give the GPU back to the desktop.
--
-- If a display fails to come up after you log in, switch to a TTY (Ctrl+Alt+F3), delete this
-- block (or the flag file, which disables it) and log in again.

-- ===== CONFIGURE THIS =====
-- PCI address of the passthrough GPU's VGA function: the FIRST address in GPU_PCI in
-- /etc/win11-vm.conf (./detect.sh prints it). "0000:01:00.0" is only an example.
local PASSTHROUGH_PCI = "0000:01:00.0"

-- Vulkan ICD of the GPU the HOST keeps (the iGPU), so the host never loads the passthrough
-- GPU's Vulkan driver. These are values to adjust, check `ls /usr/share/vulkan/icd.d/`:
--   Intel iGPU:  /usr/share/vulkan/icd.d/intel_icd.json
--   AMD iGPU:    /usr/share/vulkan/icd.d/radeon_icd.json
-- This block was built for an NVIDIA passthrough GPU with an Intel host GPU. With an AMD
-- passthrough GPU the host and the guest GPU share the mesa/radv stack, so hiding one from the
-- other is a different problem (the three variables below would hide both); treat AMD as
-- best-effort and expect to rethink them.
local HOST_VULKAN_ICD = "/usr/share/vulkan/icd.d/intel_icd.json"
-- ==========================

local flag = io.open(os.getenv("HOME") .. "/.config/hypr/gpu-vm-mode", "r")
if flag then
  flag:close()

  -- (a) Keep the NVIDIA userspace out of Hyprland and its children: use mesa for EGL and GLX,
  -- and only the host GPU's Vulkan driver.
  hl.env("__EGL_VENDOR_LIBRARY_FILENAMES", "/usr/share/glvnd/egl_vendor.d/50_mesa.json")
  hl.env("__GLX_VENDOR_LIBRARY_NAME", "mesa")
  hl.env("VK_DRIVER_FILES", HOST_VULKAN_ICD)

  -- (b) Tell Aquamarine (Hyprland's backend) to use only the host GPU(s).
  --
  -- AQ_DRM_DEVICES is a ":"-separated list, but the stable names under /dev/dri/by-path
  -- contain ":" themselves (pci-0000:00:02.0-card). Passed verbatim they are split into
  -- fragments, every PCI card is dropped, and Hyprland falls back to software rendering
  -- (aquamarine logs "Failed to canonicalize path /dev/dri/by-path/pci-0000"). So resolve each
  -- symlink to its colon-free /dev/dri/cardN here, at config-read time. The by-path names are
  -- used because card numbers change between boots; they are resolved fresh on every login.
  local drm_cards = {}
  local ls = io.popen("ls -1 /dev/dri/by-path/ 2>/dev/null")
  if ls then
    for name in ls:lines() do
      -- PCI GPUs, plus platform cards (for example DisplayLink's evdi); skip the render nodes.
      local is_card = (name:match("^pci%-.*%-card$") or name:match("^platform%-.*%-card$"))
      -- Leave out the passthrough GPU. (find with plain=true: the address contains "." and ":".)
      local is_passthrough = name:find("pci-" .. PASSTHROUGH_PCI .. "-card", 1, true)
      if is_card and not is_passthrough then
        local probe = io.popen("readlink -e -- '/dev/dri/by-path/" .. name .. "' 2>/dev/null")
        if probe then
          local node = probe:read("*l")
          probe:close()
          if node and node ~= "" then
            drm_cards[#drm_cards + 1] = node
          end
        end
      end
    end
    ls:close()
  end

  -- Only set it when something is left, otherwise leave Aquamarine's own detection alone.
  -- The list order matters: the first device is the primary one. ls sorts by PCI address, which
  -- puts an Intel iGPU (usually 0000:00:02.0) first; reorder if your host GPU is not first.
  if #drm_cards > 0 then
    hl.env("AQ_DRM_DEVICES", table.concat(drm_cards, ":"))
  end
end
