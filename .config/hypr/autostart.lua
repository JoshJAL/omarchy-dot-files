-- Extra autostart processes, ported from Omarchy 3's ~/.config/hypr/autostart.conf.

-- Keep the system awake while audio is playing or the CPU is busy (prevents
-- auto-lock). Not wrapped in uwsm-app, matching the original exec-once.
o.exec_on_start(os.getenv("HOME") .. "/.local/bin/keepawake-guard")

-- T3 Code is the sole server owner of ~/.t3 on the desktop, and T3 Connect's
-- tunnel only exists while it runs, so start it with the session. Desktop only:
-- the work laptop is a client of this machine, not a host.
local machine = require("hypr.machine")
if machine.is(machine.DESKTOP) then
  o.launch_on_start("t3code")
end
