# For an agent, after a pull

**Point an agent at this file after `dotfiles pull`.** It is the procedure for confirming that
what arrived in the pull is actually *in effect* on this machine, not merely present on disk.

`README.md` explains what this repo is. `NEW-MACHINE.md` is the once-per-machine setup
procedure. This file is the routine one: run it every time files land.

---

## Why this file is not called CLAUDE.md or AGENTS.md

Because the work-tree of this repo is `$HOME`, and both of those names load automatically from
the working directory **and every directory above it**. A `CLAUDE.md` here would be injected into
every session for every project under `~`.

Worse, it would break other repos silently. Claude Code reads a repository's own `AGENTS.md` only
when there is no `CLAUDE.md` in the working directory *or any directory above it* — so a
`CLAUDE.md` at `$HOME` stops every cloned project's `AGENTS.md` from ever being read, with no
warning. The same applies to `~/AGENTS.md`, which would load into every project below it that has
no `CLAUDE.md` of its own.

So the name is deliberately inert. Nothing auto-loads it; you point at it. **Do not rename this
file to a filename any agent tool loads by convention.**

---

## Step 0 — Identify the machine, and stop if it is new

```bash
cat /sys/devices/virtual/dmi/id/sys_vendor
cat /sys/devices/virtual/dmi/id/product_name
hostnamectl chassis
```

Compare that `sys_vendor` / `product_name` pair against the *Known machines* table at the bottom
of `NEW-MACHINE.md`.

**If it is not in that table, stop and follow `NEW-MACHINE.md` instead.** Everything below
assumes the hardware branches in `monitors.lua` and `hyprland.lua` already cover this machine.
They are two-way tests, so a machine they were not written for does not fail loudly — it silently
takes the other machine's branch and comes up with the wrong monitor layout.

---

## Step 1 — The tree must be clean

```bash
dotfiles status
```

Empty is the only passing result.

A tracked file that is dirty immediately after a pull is a **finding, not noise**. It means
something on this machine rewrote a tracked file to encode local state, and whatever it wrote
will either be committed over the other machine's version or be clobbered on the next pull. Find
out which tool wrote it and why before doing anything else.

Two kinds turn up in practice, and they are not the same problem:

- **Re-serialization.** A tool rewrote the file with identical meaning — a `—` escape
  emitted as a literal `—`. Harmless; revert it.
- **Encoded machine state.** The content genuinely differs because this machine differs. That is
  the one that matters. See *Failure modes already seen* below.

---

## Step 2 — Derived checks

Do not work from a fixed list of filenames; the repo grows. Derive the checks from what is
actually tracked:

```bash
dotfiles ls-files
```

Then apply the invariant for each location:

| Location | Invariant | Check |
|---|---|---|
| `.config/systemd/user/*.{path,service,timer}` | enabled **and** active | `systemctl --user is-enabled X; systemctl --user is-active X; systemctl --user list-units --failed` |
| `.local/bin/*` | executable, and resolves on `PATH` | `test -x`, then `command -v <name>` |
| `.config/omarchy/hooks/post-update.d/*` | has been run once since the pull | run it — they are idempotent by design |
| `.config/hypr/*.lua` | config parses; every binding is registered | `hyprctl reload && hyprctl configerrors` (must be empty), then `hyprctl binds` |
| `.config/omarchy/plugins/*` | declared in `shell.json`, and the shell restarted since the pull | `grep <id> ~/.config/omarchy/shell.json`; `pgrep -af quickshell` |
| `.config/omarchy/extensions/*.jsonc` | parses **as JSONC** | strip `//` comments *and* trailing commas before parsing |
| `.config/mimeapps.list` | every handler name resolves to a real `.desktop` | for each value, confirm the file exists in some XDG applications dir |

Notes that have cost time before:

- **A new systemd unit does nothing until it is enabled.** `daemon-reload` after a pull, then
  `enable --now`. A unit file arriving in the work-tree is not an installed unit.
- **`hyprctl configerrors` empty is not the same as "the binding works."** A binding can parse and
  still point at a script that is missing or not executable. Check `hyprctl binds` for the
  modmask/key, and check the target exists.
- **JSONC is not JSON.** Trailing commas are legal in the menu extension. A plain `json.loads`
  reports a syntax error on a perfectly valid file; strip trailing commas first or you will
  "fix" something that was never broken.
- **A mimeapps handler that does not resolve does not error.** It falls through silently to
  whatever else claims the scheme. Resolving each name is the only way to see it.

---

## Step 3 — What git does not carry

These cannot be derived from the repo because they are deliberately untracked. `NEW-MACHINE.md`
Step 5 is the authority; this is the checklist form:

1. **`~/.config/secrets.env`** — must exist, mode `600`. Sourced by `.bashrc`. Never tracked; the
   remote is public.
2. **Themes** — every entry in `~/.config/omarchy/themes-installed.txt` should have a directory
   under `~/.config/omarchy/themes/`. Reinstall missing ones with the command in that file's own
   header comment.
3. **`.desktop` aliases** — written by `hooks/post-update.d/keep-default-apps`, not by git. Until
   that hook runs, a tracked `mimeapps.list` can name a handler this machine cannot resolve.

---

## Step 4 — Report, and stop

Apply on your own initiative only what this repo already documents as idempotent: running a
post-update hook, `systemctl --user daemon-reload` and `enable --now`, `hyprctl reload`,
restarting the shell.

Report, and do not decide alone:

- a tracked file still dirty, and why
- config that differs because the machine differs (a hardware branch that needs adding)
- a missing `secrets.env`, or anything else that needs a credential
- any fix whose blast radius reaches the other machine on its next pull

**Never `commit` or `push`.** A wrong fix committed here arrives on the other machine
automatically, and a broken tracked config reaches it before anyone notices.

---

## Failure modes already seen

Kept because each one looked like something else at first.

**A tracked handler name that does not resolve here.** `mimeapps.list` is shared between machines
and can only name one `.desktop` per scheme, but the two machines install the same apps under
different names — Helium is packaged as `helium.desktop` on one and is a hand-made
`helium-browser.desktop` pointing at an AppImage on the other. The tracked file named one of
them; on the machine without it, `x-scheme-handler/https` quietly resolved to Chromium instead.
Nothing errored. The fix is aliasing (`keep-default-apps` writes a `NoDisplay` copy under the
other name), not a per-machine file — so **if the browser is wrong after a pull, run that hook
before assuming the config is wrong.**

**A generated block that encoded the local browser set.** The browser rows in
`omarchy-menu.jsonc` are generated from what is installed, so the file came out different on each
machine and was permanently dirty on whichever one had not written it last — exactly what
`NEW-MACHINE.md` rule 2 forbids. It is now written to converge: rows for browsers this machine
does not have are carried through unchanged behind a `when` guard, and glyph codepoints are
assigned over the sorted union of all of them rather than by local position. **If that file is
dirty after a pull, the convergence has regressed — do not just commit it.**

**Tooling that only looked where pacman installs.** `sync-browser-menu` and `keep-default-apps`
originally searched `~/.local/share/applications` and `/usr/share/applications` only. A browser
installed as a flatpak or into `/usr/local` exports somewhere else entirely, so it was invisible
to both while `xdg-settings` resolved it fine — the menu simply disagreed with the system. Both
now read `XDG_DATA_DIRS`. **When adding tooling that looks for a `.desktop`, use the XDG dirs;
the install method differs per machine and per app.**

**A guard that tested the wrong thing.** `omarchy-cmd-present` tests `PATH`, and a browser
installed as an AppImage has no command on `PATH` at all — so it reported "not installed" for a
browser that was installed, default, and running. `.local/bin/desktop-entry-present` tests the
desktop entry instead, which is what the row actually depends on.
