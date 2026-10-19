# Windows 11 VM with GPU passthrough on Omarchy

A self-contained setup for a Windows 11 virtual machine (libvirt/QEMU) that owns one of your GPUs, shown
in a window on your Linux desktop through Looking Glass. It was built to run SolidWorks, which needs a
real GPU and cannot use the GPU of a Docker-based VM. Scripts detect your hardware, install everything,
create the VM and wire up the GPU handover, so only the Windows-side clicks are manual.

## What you get

- A Windows 11 VM: UEFI with Secure Boot, TPM 2.0, virtio disk and network, on `qemu:///system`.
- Your discrete GPU passed through to Windows, with a script (`winvm-gpu`) that hands it over and takes it back.
- Looking Glass B7: Windows on the GPU, displayed in a normal window.
- A launcher ("Windows 11 (GPU)" in the app menu, or `win11-vm`) that does the handover, boots Windows
  and opens Looking Glass.
- USB auto-attach: security keys (by vendor id, for example Yubico) and USB drives plugged in while the
  VM runs, or already plugged in when it starts, show up in Windows.
- A hardware check (`detect.sh`) and a drift check (`install.sh --check`).
- A guide for a coding agent (`FOR_AGENT.md`) and a list of the fifteen things that went wrong while
  building it (`LESSONS.md`).

## Requirements

- **Two GPUs.** The host keeps one (normally the integrated GPU) and Windows gets the other. A machine
  with a single GPU cannot do this.
- **IOMMU on:** VT-d (Intel) or AMD-Vi enabled in the firmware, plus `intel_iommu=on iommu=pt` (or
  `amd_iommu=on iommu=pt`) on the kernel command line. `detect.sh` tells you.
- **The GPU alone in its IOMMU group** (apart from its own HDMI audio function and PCI bridges).
- Omarchy (Arch Linux, Hyprland with the Lua config, Limine, usually btrfs, ufw enabled) and `yay` for
  the two AUR packages.
- RAM and disk for a Windows VM: plan on about half of your RAM and 80 GiB or more of free disk (the
  default disk image is 256 GiB, sparse).
- A monitor plugged into the passthrough GPU goes dark while Windows has the GPU.

Tested: an NVIDIA GPU passed through, on an Intel host. AMD (as host or passthrough GPU) is best-effort
and untested.

## Get just this folder

GitHub's "Download ZIP" gives the whole repository, not one folder. To fetch only this folder:

```
git clone --depth 1 --filter=blob:none --sparse https://github.com/JoshJAL/omarchy-dot-files.git win11-gpu-vm-src
cd win11-gpu-vm-src && git sparse-checkout set win11-gpu-vm && cd win11-gpu-vm
```

## Quick start

Run everything from this folder as your normal user. Root-only steps ask for your password through a
graphical prompt (`pkexec`).

1. `./detect.sh > win11-vm.conf` and read the report. `NO-GO` means this machine cannot run it as is.
   Review `win11-vm.conf` (see `win11-vm.conf.example` for what each key means).
2. `./install.sh --packages --conf win11-vm.conf`, log out and in once (libvirt group), then
   `./install.sh --check`.
3. Download the Windows 11 ISO in a browser (microsoft.com/software-download/windows11), then
   `./create-vm.sh --iso /path/to/Win11.iso` (add `--dry-run` first; `--memory`, `--vcpus` and
   `--disk-size` set the VM size).
4. Install Windows and the guest tools: `guest/GUEST-STEPS.md` steps 1 and 2. Shut Windows down.
5. Merge `hyprland-snippet.lua` into your `~/.config/hypr/hyprland.lua`.
6. `./enable-gpu.sh`, then `winvm-gpu on` (log out and in when it tells you, run it again), start the
   VM, and do `guest/GUEST-STEPS.md` steps 3 to 6 (GPU driver, Looking Glass host, virtual display).
7. Shut Windows down, run `./enable-gpu.sh --final`, then open **Windows 11 (GPU)** from the app menu.

If something fails, look up the symptom in `LESSONS.md`.

## Let a coding agent do it

Point a coding agent (Claude Code, Codex, ...) at `FOR_AGENT.md`. It runs the steps above in order,
shows you each change, and stops before anything that needs your password, a logout, or a deletion.
You still do the clicks inside Windows.

## What is in the folder

| Path | Purpose |
|---|---|
| `README.md` | this file |
| `FOR_AGENT.md` | step-by-step runbook for a coding agent |
| `LESSONS.md` | the fifteen failures hit while building this, with symptom, cause and fix |
| `detect.sh` | read-only hardware check; proposes the config; exits 1 on a blocker |
| `win11-vm.conf.example` | the config file format (`/etc/win11-vm.conf`) with explanations |
| `install.sh` | installs the files below, packages, ufw rules and the USB udev rule; `--check` shows drift |
| `create-vm.sh` | phase 1: creates the plain Windows 11 VM to install Windows into |
| `enable-gpu.sh` | phase 2: adds the GPU and the rest; `--final` removes the emulated screen |
| `hyprland-snippet.lua` | Hyprland config block that frees the GPU from the compositor; merge it by hand |
| `guest/GUEST-STEPS.md` | the Windows-side steps and their troubleshooting |
| `guest/vm-guest-exec` | runs PowerShell in the guest from the host (QEMU guest agent) |
| `guest/install-vdd.ps1` | installs the Virtual Display Driver in the guest, bound to the GPU |
| `files/usr/local/bin/winvm-gpu` | hands the GPU to Windows or back (`status`, `on`, `off`) |
| `files/usr/local/bin/winvm-usb` | attaches and detaches USB devices to the running VM |
| `files/etc/libvirt/hooks/qemu.d/win11-usb` | libvirt hook: attaches already-plugged-in USB devices at VM start |
| `files/etc/tmpfiles.d/10-looking-glass.conf.in` | creates the Looking Glass shared-memory file at boot |
| `files/home/.local/bin/win11-vm` | the launcher |
| `files/home/.local/share/applications/windows-11-gpu.desktop.in` | the app-menu entry |
| `files/home/.config/looking-glass/client.ini` | Looking Glass client settings |

## Built on one machine

This was built and tested on a single machine: an Intel i9 laptop with an NVIDIA RTX 4070 Laptop GPU,
Omarchy, libvirt 12.8 and Looking Glass B7. Everything else is untested: other GPUs, AMD, desktops, other
distributions. The scripts check what they can, but expect to adapt.
