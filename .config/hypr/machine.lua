-- Identify the machine from DMI. Stable across reinstalls, needs no hostname
-- (a fresh Omarchy install answers "omarchy" on every machine).
--
-- Replaces the old two-way boolean tests (eDP-1 present / Intel iGPU present).
-- Those answered "is this the work laptop?" and silently put any third machine
-- on the laptop's branch. See NEW-MACHINE.md, Step 4a.
--
-- To add a machine: read its pair from
--   cat /sys/devices/virtual/dmi/id/sys_vendor /sys/devices/virtual/dmi/id/product_name
-- add a constant below, then add a branch where it differs.
local function dmi(field)
  local f = io.open("/sys/devices/virtual/dmi/id/" .. field, "r")
  if not f then return "" end
  local v = f:read("*l") or ""
  f:close()
  return v
end

local id = dmi("sys_vendor") .. " " .. dmi("product_name")

local M = {}
M.id       = id
M.is       = function(name) return id == name end
M.LAPTOP   = "System76 Oryx Pro"
M.DESKTOP  = "Gigabyte Technology Co., Ltd. X670 AORUS ELITE AX"
M.SURFACE  = "Microsoft Corporation Surface Book"
return M
