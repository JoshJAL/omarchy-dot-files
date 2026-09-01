# Hyprland .conf -> .lua port (staged for the Omarchy 4 "Quattro" upgrade)

Prepared 2026-09-01, against Hyprland 0.56.2 / Omarchy 3.8.5 -> 4.0.2.

Nothing here is live. These are drop-in replacements for the stock `.lua` files
that `omarchy upgrade to quattro` installs into `~/.config/hypr/`.

## Why this couldn't be done in place

Hyprland picks its config format once at startup: `hyprland.lua` if it exists,
otherwise `hyprland.conf`. Lua has no `source` for hyprlang files. Your
`hyprland.conf` sources nine Omarchy 3 defaults that are all hyprlang, and those
live in `~/.local/share/omarchy/` (overwritten on update, not ours to edit).
So writing a `hyprland.lua` on Omarchy 3 means losing every Omarchy default.
Omarchy 4 is the migration.

## Order of operations

1. `omarchy update`                (pulls the intermediate migrations)
2. `omarchy upgrade to quattro`    (or: menu -> Update -> Omarchy to Quattro)
3. Reboot.
4. Paste the one-liner below.

```
if grep -q bootstrap.lua ~/.config/hypr/hyprland.lua 2>/dev/null; then cp ~/hypr-quattro-port/{monitors,input,bindings,autostart}.lua ~/.config/hypr/ && { grep -q dynamic_cursors ~/.config/hypr/hyprland.lua || cat ~/hypr-quattro-port/hyprland.lua.snippet >> ~/.config/hypr/hyprland.lua; } && hyprctl reload && hyprctl configerrors && echo "Done."; else echo "Not on Omarchy 4 yet - run: omarchy update, then omarchy upgrade to quattro, reboot, then paste this again."; fi
```

It refuses to run before the upgrade (appending the snippet to a non-existent
`hyprland.lua` would create one, which would switch Hyprland into Lua mode with
nothing but the snippet in it -- a broken session), and it won't double-append
if pasted twice.

The upgrade backs up anything it overwrites as
`<file>.omarchy-upgrade-to-quattro.<suffix>.bak`, and your old `.conf` files are
left in place untouched. `omarchy-snapshot` + the Limine bootloader entry are
the full rollback.

## What was ported

| Old | New | Note |
|---|---|---|
| `monitors.conf` | `monitors.lua` | 3 monitors, verbatim. `GDK_SCALE` set to 1, not Omarchy's default 2 (all your displays are scale 1.0). |
| `input.conf` | `input.lua` | `ctrl:nocaps`, repeat 40/600, numlock, `scroll_factor 0.4`, both terminal scroll rules. |
| `bindings.conf` | `bindings.lua` | 31 bindings in, 6 out. See below. |
| `autostart.conf` | `autostart.lua` | `keepawake-guard`. `hyprpm reload` dropped -- the snippet loads the plugin instead. |
| `plugin:dynamic-cursors` block | `hyprland.lua.snippet` | Loads the plugin explicitly, then configures it. |
| `envs.conf` | *(dropped)* | See below. |
| `hypridle.conf`, `hyprlock.conf` | *(dropped)* | hypridle and hyprlock are both retired in Quattro. |

### Bindings: 25 of 31 dropped

24 were exact repeats of Omarchy defaults (Terminal, Browser, File manager,
Tmux, Music, Editor, Docker, Signal, Obsidian, Passwords, ChatGPT, Calendar,
Email, YouTube, WhatsApp, Google Messages, Google Photos, X, X Post, ...), all of
which Omarchy 4 ships in `default/hypr/bindings/applications.lua`. Carrying them
forward would just be re-declaring the defaults.

The 25th is `SUPER+L`, dropped by choice: it overrode "Toggle workspace layout"
to run `hyprlock`, which Quattro removed, and Omarchy 4 already binds
`omarchy-system-lock` to `SUPER + CTRL + L`. `SUPER+L` goes back to its default.

`SUPER+S` (`~/.local/bin/omarchy-random-screensaver.sh`) is also out, pending a
look at whether Quattro's own screensaver makes it redundant. The script is
untouched on disk and `bindings.lua` carries the two lines to restore it.

That leaves 6: Typora over Omawrite, Claude over Grok, split on `SUPER+Y`, and
the three `SUPER+SHIFT` capture binds.

### envs.conf was already dead

`~/.config/hypr/envs.conf` (your NVIDIA block) is not sourced by anything --
`hyprland.conf` sources Omarchy's `default/hypr/envs.conf`, never yours.
Verified: `NVD_BACKEND` is unset in the running session. It has been inert for
some time. Omarchy 4 sets these itself in `default/hypr/nvidia.lua`, gated on
actually detecting an NVIDIA GPU and on whether GSP firmware is in use
(`NVD_BACKEND=direct` vs `egl`), which is more careful than the old static list.
Nothing to port. `AQ_DRM_DEVICES` is the one line with no Omarchy 4 equivalent --
if multi-GPU device ordering matters on this machine, re-add just that one.

## dynamic-cursors

Currently loaded and working on 0.56.2. The snippet follows the plugin's own
README (https://github.com/VirtCode/hypr-dynamic-cursors): the Lua config key is
`dynamic_cursors` with an underscore, where hyprlang used a hyphen, and the
`if hl.plugin.dynamic_cursors` guard is the author's documented pattern.

The one thing to watch: hyprpm has to rebuild the `.so` against whatever
Hyprland version Quattro pulls in (`hyprpm update`). If it won't build, the
guard means the config block is skipped rather than erroring -- and you can
delete the whole snippet, since nothing else depends on it.

## Not verified

These files have not been parsed by Hyprland -- Omarchy 4 isn't installed, so
there's no `default.hypr.helpers` to define `o.bind`, `o.window`,
`o.exec_on_start`. They pass `luac -p`, and the `hl.*` calls are checked against
the 0.56.2 binary's symbol table and Omarchy 4.0.2's own stock configs. The
`hyprctl configerrors` at the end of the one-liner is the real test.
