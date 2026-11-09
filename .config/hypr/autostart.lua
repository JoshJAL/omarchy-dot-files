-- Extra autostart processes, ported from Omarchy 3's ~/.config/hypr/autostart.conf.

-- Keep the system awake while audio is playing or the CPU is busy (prevents
-- auto-lock). Not wrapped in uwsm-app, matching the original exec-once.
o.exec_on_start(os.getenv("HOME") .. "/.local/bin/keepawake-guard")

-- T3 Code's server runs as the t3code.service user service (installed with
-- `t3 up`), so it and the T3 Connect tunnel stay up without the desktop app.
-- Do NOT autostart the app here: it would compete with the service for ~/.t3.
-- Open the app on demand; it is only a client.
