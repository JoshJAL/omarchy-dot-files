# New machine playbook

**Read this before changing any tracked config on a machine you have not set up before.**

`README.md` explains what this repo *is*. This file is the procedure for making it fit a machine
it has never run on. It is written for an agent to execute.

**For a routine pull onto a machine already set up, use [`FOR_AGENT.md`](FOR_AGENT.md) instead.**
This file is the once-per-machine path; that one is the every-time path, and it hands back here
if it finds hardware the branches below do not cover.

The repo is shared by every machine on one branch (`main`). There is no per-machine branch and
there must not be one — divergent branches drift and conflict on every pull. Machines differ by
**detecting their own hardware at config-read time**, not by holding different files.

---

## Rules that never bend

1. **The remote is PUBLIC** (`github.com/JoshJAL/omarchy-dot-files`). Never track anything
   carrying a key, token, internal hostname, work URL, or client identifier. Scan before adding.
2. **Never commit a machine-divergent version of a tracked file.** If this machine needs
   `monitors.lua` to say something different, add a *branch inside* the file. Committing your
   layout over the other machine's breaks that machine on its next pull.
3. **`~/.gitignore` is deny-by-default.** Everything in `$HOME` is ignored; un-ignore rules name
   what is tracked. To track something new: `dotfiles add -f <path>` (alias: `dotfiles-track`).
4. **Never `dotfiles checkout` over a dirty tree** without backing up conflicting files first.

---

## Step 1 — Identify this machine

```bash
cat /sys/devices/virtual/dmi/id/sys_vendor      # e.g. System76
cat /sys/devices/virtual/dmi/id/product_name    # e.g. Oryx Pro
hostnamectl chassis                             # laptop | desktop
hostnamectl hostname
ls /sys/class/drm/*-eDP-1 2>/dev/null           # internal panel present?
ls -l /dev/dri/by-path/                         # GPU topology by stable id
hyprctl monitors all | grep -E 'Monitor|availableModes' | head
```

Record `sys_vendor` + `product_name`. **That pair is the discriminator to prefer for a new
machine** — it is stable across reinstalls, unique per model, and needs no setup. Hostname is
weaker (it is a choice, and can collide on a fresh Omarchy install, which defaults to `omarchy`).

---

## Step 2 — Check whether the existing branches already cover it

These tracked files branch on hardware today, all through `hypr/machine.lua` (DMI vendor + product):

| File | Discriminator | What it selects |
|------|---------------|-----------------|
| `.config/hypr/machine.lua` | DMI `sys_vendor` + `product_name` | defines the machine ids; **add new machines here** |
| `.config/hypr/monitors.lua` | `machine.is(...)` | per-machine layout, scale and `GDK_SCALE` |
| `.config/hypr/hyprland.lua` | `machine.is(machine.LAPTOP)` | `AQ_DRM_DEVICES` order + `LIBVA_DRIVER_NAME=iHD`, work laptop only |

**These are exact matches, not guesses.** A machine whose DMI pair is not in `machine.lua`
matches no branch, so it gets no machine-specific monitor rules (Hyprland auto-arranges at each
display's preferred mode) and none of the work laptop's GPU pins. That is a working but
unconfigured desktop, not a wrong one.

(Before the Surface Book was added these were two-way boolean tests -- "has an `eDP-1`", "has the
Intel iGPU" -- and a second laptop silently took the work laptop's layout. That is why the
discriminator is DMI now.)

So: if this machine is not in *Known machines* below, it needs a branch. Go to Step 4.

---

## Step 3 — Choose the handling pattern

Three patterns are already established here. Pick by what kind of difference it is.

| Pattern | Use when | Example in repo |
|---------|----------|-----------------|
| **Branch on hardware** | The setting is genuinely different per machine and both values matter | `monitors.lua`, `hyprland.lua` |
| **Alias so one file works everywhere** | The difference is only a *name*, and a single file could satisfy both | `hooks/post-update.d/keep-default-apps` writes `.desktop` aliases so one `mimeapps.list` resolves on every machine |
| **Leave untracked** | Machine-local, secret, or regenerated | `~/.config/secrets.env`, work-only systemd units, `btop.conf` |

Prefer **alias** over **branch** when possible — it keeps the file byte-identical everywhere and
removes the per-machine question entirely. Prefer **branch** over **untracked** when the value is
worth version history.

---

## Step 4 — Add this machine as a branch

### 4a. Register the machine in `machine.lua`

`~/.config/hypr/machine.lua` already exists (tracked). It reads DMI and exposes one constant per
known machine. Add yours:

```lua
M.NEWBOX = "<sys_vendor> <product_name>"   -- exactly as `cat` prints them, joined by one space
```

Then in `monitors.lua`, add an `elseif machine.is(machine.NEWBOX) then` branch (set `GDK_SCALE`
inside it -- it is per-machine now). Keep the fallback that does nothing rather than one that
guesses; a wrong explicit layout is worse than Hyprland's auto-arrangement.

### 4b. Write this machine's values

Never copy another machine's numbers. Read them from the hardware:

```bash
hyprctl monitors all          # exact output names, modes, refresh rates
```

Use the **highest** listed mode per output unless there is a reason not to, and set `position`
from the physical arrangement. Refresh rates must be copied exactly as reported, including the
decimals (`59.97`, not `60`) — a mode string that does not match an advertised mode is rejected.

### 4c. GPU settings are opt-in, never inherited

Anything in `hyprland.lua` touching `AQ_DRM_DEVICES` or `LIBVA_DRIVER_NAME` must stay behind a
positive test for the machine that needs it. Two traps documented in that file, both learned the
hard way:

- `AQ_DRM_DEVICES` must be given **resolved `/dev/dri/cardN` paths**, not `by-path` symlinks —
  aquamarine splits the variable on `:` and PCI paths contain colons, which shreds them and
  drops every PCI card.
- The `LIBVA_DRIVER_NAME` pin must sit **below** `require("default.hypr.omarchy")`. Omarchy's
  `default/hypr/nvidia.lua` sets it, `hl.env` is last-write-wins, and anything set earlier is
  silently overwritten.

---

## Step 5 — Recreate what git does not carry

These are ignored by design and will not arrive with a clone:

1. **`~/.config/secrets.env`** — API keys, sourced by `.bashrc:23`. Create by hand, `chmod 600`.
2. **Themes** — `grep -v '^#' ~/.config/omarchy/themes-installed.txt | awk '{print $2}' | xargs -rn1 omarchy theme install`
   then `omarchy theme set <name>` (installing activates each one in turn).
3. **Run the hooks once** — they only fire on `omarchy update`:
   `bash ~/.config/omarchy/hooks/post-update.d/keep-default-apps` (idempotent)
4. **Work-only systemd user units** — deliberately untracked because they carry internal
   identifiers and this remote is public. They are named in `~/.dotfiles/info/exclude` on the
   machine that has them. Recreate only on a work machine.
5. **`~/.dotfiles/info/exclude`** — local-only, not pushed. It is now redundant with `.gitignore`;
   no action needed.

---

## Step 6 — Verify before committing

```bash
hyprctl reload && hyprctl configerrors     # must be empty
hyprctl monitors | grep -E 'Monitor|@'     # every display present, at intended mode
dotfiles status                            # only files you meant to change
dotfiles diff                              # no other machine's values altered
```

Then commit the branch addition, not a rewrite:

```bash
dotfiles add .config/hypr/monitors.lua .config/hypr/machine.lua
dotfiles commit -m "hypr: add <machine> monitor layout"
dotfiles push
```

If `hyprctl configerrors` is non-empty, fix it before pushing — a broken config reaches every
machine on its next pull.

---

## Known machines

| | Work laptop | Desktop | Surface Book |
|---|---|---|---|
| DMI | `System76` / `Oryx Pro` | `Gigabyte Technology Co., Ltd.` / `X670 AORUS ELITE AX` | `Microsoft Corporation` / `Surface Book` |
| Chassis | laptop | desktop | laptop |
| GPUs | Intel Iris Xe (`pci-0000:00:02.0`) + RTX 4070 Mobile (`pci-0000:01:00.0`) + DisplayLink evdi | RTX 5080 + AMD iGPU | Intel HD 520 (`pci-0000:00:02.0`) only |
| Displays | `eDP-1` 1920x1200@165 · `HDMI-A-1` 3440x1440@59.97 · `DVI-I-1` 1920x1080@60 | `DP-2` 3440x1440@99.98 · `DP-1` 2560x1440@240 | `eDP-1` 3000x2000@59.98, scale 2 (HiDPI) |
| `GDK_SCALE` | 1 | 1 | 2 |
| Special | `AQ_DRM_DEVICES` pinned so Intel is the render device; `LIBVA_DRIVER_NAME=iHD` | Omarchy's own `nvidia.lua` handles everything; leave it alone | Nothing pinned. No ghostty/helium installed at first setup (2026-10-07), so terminal fell back to foot and browser to chromium until installed |

The laptop's `DVI-I-1` is a DisplayLink output over `evdi`. It disappears when the dock is
unplugged, and its card number shifts between boots because `evdi` is a platform device — which
is why `by-path` ids are resolved at config-read time rather than hardcoded as `cardN`.
