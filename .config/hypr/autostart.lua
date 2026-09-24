-- Extra autostart processes, ported from Omarchy 3's ~/.config/hypr/autostart.conf.

-- Keep the system awake while audio is playing or the CPU is busy (prevents
-- auto-lock). Not wrapped in uwsm-app, matching the original exec-once.
o.exec_on_start(os.getenv("HOME") .. "/.local/bin/keepawake-guard")
