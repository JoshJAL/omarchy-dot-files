# Runbook for a coding agent

You are setting up a Windows 11 VM with a passed-through GPU (shown through Looking Glass) on the
human's Omarchy machine (Arch Linux, Hyprland with a Lua config, Quickshell, Limine, ufw). The human
approves each step. Work from the bundle directory (the folder that contains `detect.sh`). Windows-side
steps live in `guest/GUEST-STEPS.md`; follow that file for them and do not copy its content elsewhere.
When something fails, read `LESSONS.md` before improvising.

## 1. Stop rules

Stop and ask the human before doing any of these.

- **Root.** Anything that needs root goes through `pkexec`, and every `pkexec` is a password prompt on
  the human's screen. Say what is about to run and why before each one. Do not use `sudo`, do not try
  to bypass the prompt.
- **Logging out.** `winvm-gpu on` needs the human to log out and back in, which ends your session too.
  Tell them first, and tell them what to run or say when they are back.
- **Deleting anything.** Disks, ISOs, VM definitions, backups, the flag file, config files.
- **Dotfiles.** Never commit to, or push from, the human's dotfiles repository without asking. Merging
  the Hyprland snippet edits a config file that may be tracked; show the diff and let them decide.
- **Secrets.** Never paste the Windows product key, a Windows password or any other credential into a
  command line, file, log or chat message. The human types them into Windows.
- **Other machines' values.** Never copy a value from this bundle's examples (PCI addresses, the GPU
  name, IOMMU limit, USB vendor ids, user name) into the real config. Every value comes from
  `./detect.sh` or from the human.

**NO-GO from `./detect.sh`: stop.** It exits 1 and the last line says `NO-GO ... VERDICT`. Explain the
blocker to the human, do not proceed. The blockers are:

- only one GPU (a single-GPU host would have no display once Windows takes the GPU)
- IOMMU off (detect.sh prints the fix: enable VT-d/AMD-Vi in the firmware, and add `intel_iommu=on
  iommu=pt` or `amd_iommu=on iommu=pt` to the Limine kernel command line; this is the human's decision and
  needs a reboot)
- the GPU shares its IOMMU group with something that is not part of the GPU (not isolated)
- the only connected displays are on the passthrough GPU
- no `vmx`/`svm` CPU flag, or no second GPU that is not the boot VGA device

**Cautions that are not blockers:**

- **AMD hosts or AMD GPUs are best-effort.** This was built and tested with an NVIDIA GPU and an Intel
  host. The IOMMU address-width check only exists for Intel, and the Hyprland mesa/Vulkan settings assume
  the passthrough GPU is NVIDIA. Say so, and expect to adapt.
- **Desktop with a monitor on the passthrough GPU.** `detect.sh` warns ("monitor on the passthrough
  GPU"). That monitor goes dark while Windows has the GPU. Make sure the human understands this before
  continuing.
- **`WARN` lines** (btrfs, ufw, `/dev/kvm` permissions, a udev rule without a match key) are explained
  in the output. Relay them; most are handled by later steps.

## 2. Get the bundle

If the human has not already got the folder:

```
git clone --depth 1 --filter=blob:none --sparse https://github.com/JoshJAL/omarchy-dot-files.git win11-gpu-vm-src
cd win11-gpu-vm-src && git sparse-checkout set win11-gpu-vm && cd win11-gpu-vm
```

All commands below run from this directory.

## 3. Detect the hardware and review the config

```
./detect.sh > win11-vm.conf
```

The config goes to stdout (the file); the hardware report goes to the terminal (stderr). The script is
read-only and needs no root. Read the report, then go through `win11-vm.conf` with the human, key by key:

| Key | What to confirm |
|---|---|
| `VM_NAME` | libvirt domain name. `win11` is fine. |
| `VM_USER` | Must be the human's login name (`install.sh` refuses root and any other user). |
| `GPU_PCI` | All PCI functions of the GPU's IOMMU group, GPU first (VGA, then HDMI audio), for example two addresses. Check with the human that this is the GPU to hand to Windows, not the host's. |
| `GPU_NAME` | The name Windows will show. A proposal from the PCI database; correct it in step 8 after the driver is installed if Device Manager says otherwise. |
| `IOMMU_LIMIT` | Empty, or a number of bits. If set, it avoids `vfio: DMA mapping failed`. |
| `USB_VENDORS` | Vendor ids (4 lowercase hex digits, space separated) of USB devices to hand to Windows automatically, default `1050` (Yubico). Ask which keys they use. To find an id, plug the device in and run `lsusb`: the line reads `ID 1050:0407 ...`, and the vendor id is the part before the colon. Empty means none. |
| `USB_STORAGE` | `1` also hands USB thumbdrives/external disks to Windows, `0` does not. |
| `LG_SHM_MB` | Looking Glass memory in MiB, a power of two. `128` suffices up to 4K SDR. |

VM memory, CPU count and disk size are not config keys. They are flags of `create-vm.sh` (step 6):
`--memory`, `--vcpus`, `--disk-size`. `detect.sh` prints a RAM suggestion (about half of the host's).

## 4. Install

```
./install.sh --packages --conf win11-vm.conf
```

What it does: installs the packages (pacman, then the AUR packages `looking-glass` and `virtio-win`
through `yay`), enables `libvirtd`, autostarts the `default` network, adds the user to the `libvirt`
group, installs `winvm-gpu`, `winvm-usb`, the libvirt hook, the tmpfiles rule, `/etc/win11-vm.conf`, the
generated udev rule for USB, ufw rules for `virbr0`, and the user-side launcher `win11-vm`, the
`.desktop` entry and the Looking Glass client config. It restarts `libvirtd` when the hook is new (a
running VM is not touched) and backs up every file it replaces (`/var/backups/win11-gpu-vm/<time>/` for
system files, `~/.local/state/win11-gpu-vm/backups/<time>/` for user files). Expect one or more
`pkexec` prompts. It must run as the normal user.

The `libvirt` group membership needs a **new login** to take effect, and `create-vm.sh` needs it. If
`virsh -c qemu:///system list` is denied afterwards, ask the human to log out and back in now (tell them
what to say when they are back), before step 6.

Then verify:

```
./install.sh --check
```

It writes nothing and exits 1 on drift. After a fresh install the expected output is `ok` per file and
`No drift.`. A `note` about `/dev/shm/looking-glass` is harmless.

## 5. Get the Windows 11 ISO

The **human** downloads the ISO in a browser from `microsoft.com/software-download/windows11`
(English or the language they want, 64-bit). Do not try to script it: Microsoft blocks automated
downloads. The file name must use only letters, digits, `.`, `_` and `-` (rename it otherwise).

## 6. Create the VM

Dry run first, and show the human the output:

```
./create-vm.sh --iso /path/to/Win11.iso --dry-run
```

Then create it, choosing sizes with the human (defaults: 16384 MiB, 8 vCPUs, 256 GiB; at most about half
the host's RAM and cores; vCPUs is an even number; disk at least 64 GiB):

```
./create-vm.sh --iso /path/to/Win11.iso --memory 16384 --vcpus 8 --disk-size 256
```

It creates the disk (No_COW on btrfs, one `pkexec` prompt), copies the ISO into
`/var/lib/libvirt/images/` and starts the VM. Then follow `guest/GUEST-STEPS.md` **steps 1 and 2**
(install Windows, then the guest tools). The human is at the `virt-viewer` window
(`virt-viewer --connect qemu:///system <VM_NAME>`): you cannot drive the Windows installer. The human
chooses and types the Windows account name and password; never ask for or record them.

When Windows is installed and `virtio-win-guest-tools.exe` has run, the human shuts Windows down from
inside (Start, Shut down).

## 7. Hyprland: release the GPU at login

`hyprland-snippet.lua` makes Hyprland start without the passthrough GPU whenever the flag file
`~/.config/hypr/gpu-vm-mode` exists. It is machine-specific and must be **merged** into the human's
`~/.config/hypr/hyprland.lua`, not pasted blindly:

1. Open the snippet and the human's `hyprland.lua`. If the config already sets `AQ_DRM_DEVICES`,
   `__EGL_VENDOR_LIBRARY_FILENAMES`, `__GLX_VENDOR_LIBRARY_NAME` or `VK_DRIVER_FILES`, merge the logic
   instead of adding a second `hl.env()` for the same name.
2. Set `PASSTHROUGH_PCI` to the first address in `GPU_PCI`, and `HOST_VULKAN_ICD` to the host GPU's ICD
   (`ls /usr/share/vulkan/icd.d/`).
3. Parse-check it (the `hl` global is not defined at parse time, which is fine):
   `luajit -bl ~/.config/hypr/hyprland.lua > /dev/null`.
4. Show the diff and get approval before writing. Do not commit it.

The change has no effect until the next login, and the snippet does nothing while the flag is absent.

## 8. Add the GPU (stage 1), boot, install the Windows-side pieces

The VM must be shut off. Preview, then apply:

```
./enable-gpu.sh --dry-run
./enable-gpu.sh
```

Stage 1 adds the GPU hostdevs, virtio mouse and keyboard, the Looking Glass shared memory, the guest
agent channel, the KVM-hiding settings and the IOMMU limit, and **keeps the QXL screen** so virt-viewer
still shows Windows. It only adds what is missing, so re-running is harmless.

Hand over the GPU (two runs of the same command):

```
winvm-gpu on
```

The first run asks for `pkexec`, creates the flag and says to log out and in. **Tell the human to log
out and back in**, and tell them what is next. After login:

```
winvm-gpu on
winvm-gpu status
```

The second run unbinds the GPU from the host and binds it to `vfio-pci` ("GPU is now reserved for
Windows."). If it prints `Close these first, they are using the GPU:`, something still holds the GPU: check that the
Hyprland snippet took effect (`env | grep AQ_DRM_DEVICES` in a terminal started after login), log out and in again, or close
the listed programs. `winvm-gpu status` should show `gpu driver: vfio-pci` for every function.

Start the VM and watch it:

```
virsh -c qemu:///system start <VM_NAME>
virt-viewer -c qemu:///system <VM_NAME>
```

Now follow `guest/GUEST-STEPS.md` **steps 3 to 6**, with the human at the virt-viewer window:

- step 3: confirm the guest agent answers with `guest/vm-guest-exec 'hostname'`.
- step 4: the GPU vendor's Windows driver (the human downloads and runs it; for NVIDIA that is the
  driver from nvidia.com). Afterwards read the GPU's name in Device Manager. If it differs from
  `GPU_NAME`, fix `GPU_NAME` in the config, re-run `./install.sh --conf win11-vm.conf`, and use the
  corrected name below. `GPU_NAME` must match Device Manager exactly.
- step 5: the Looking Glass B7 host from looking-glass.io, inside Windows. Its version must match the
  Linux client (`looking-glass-client --version` says B7).
- step 6: the Virtual Display Driver, from the host:

  ```
  guest/vm-guest-exec --timeout 600 --file guest/install-vdd.ps1 -- -GpuName "<GPU_NAME>"
  ```

  Replace `<GPU_NAME>` with the value from `/etc/win11-vm.conf`. It exits 0 on success.

## 9. Finish: remove QXL, launch

The human shuts Windows down from inside it (or `win11-vm shutdown`). Then:

```
./enable-gpu.sh --final
```

Stage 2 removes QXL (`video none`). The GPU becomes Windows' only display, and Looking Glass shows it.
Then the human opens **Windows 11 (GPU)** from the app menu (or runs `win11-vm start`), which hands the
GPU over if needed, starts the VM and opens `looking-glass-client`.

## 10. Verification checklist

Do each item and report which pass:

1. In Windows (Looking Glass window), Device Manager shows the GPU under Display adapters with no
   warning icon (no Code 43). Remotely: `guest/vm-guest-exec 'Get-PnpDevice -Class Display | Format-Table Status,FriendlyName -AutoSize'`
   lists the GPU and "Virtual Display Driver", both OK.
2. `winvm-gpu status` shows `gpu driver: vfio-pci`, `hypr flag: set`, `vm running: yes`.
3. Looking Glass shows the Windows desktop and the mouse and keyboard work inside it.
4. USB: with the VM running, plug in a configured key or a USB drive. `journalctl -t winvm-usb -n 20`
   shows `attach <bus>-<dev> <vendor>:<product>`, and the human sees the device in Windows. Unplug it:
   the log shows `detach`.
5. USB at boot: shut the VM down, leave the key plugged in, start the VM, wait about 10 seconds. The log
   shows an `attach` (from the libvirt hook) and Windows sees it.
6. `./install.sh --check` prints `No drift.`
7. Windows has network (the human opens a web page, or `guest/vm-guest-exec 'Test-NetConnection 1.1.1.1 -Port 443'`).
8. Switching back: the human closes the Looking Glass window and gets "Windows is off." Then
   `winvm-gpu status` shows the Linux driver (e.g. `nvidia`), `vm running: no` and **no** host users;
   if Hyprland is listed, the udev seat rule did not apply (`udevadm info /dev/dri/cardN | grep CURRENT_TAGS`
   must not contain `seat`). `journalctl -t winvm-gpu -n 5` shows `vm stop: GPU returned to Linux`.
9. The human opens **Windows 11 (GPU)** again: it starts with no password prompt and no log out/in.

If one fails, find the symptom in `LESSONS.md`.

## 11. Daily use and undo

**Use:**

| Command | Does |
|---|---|
| `win11-vm start` (default; the app menu entry) | hand over the GPU if needed, boot Windows, open Looking Glass. Closing the Looking Glass window shuts Windows down (ACPI, so Windows can still stop for unsaved work); shutting Windows down from inside closes the window. USB devices return to Linux when Windows is off |
| `win11-vm shutdown` | clean (ACPI) shutdown of Windows |
| `win11-vm gpu-off` | shut down Windows and leave VM mode, so the desktop (Hyprland, monitors wired to the GPU) can use the GPU again (log out/in afterwards). Not needed day to day: the GPU already belongs to Linux whenever Windows is off |
| `winvm-gpu status` | driver of the GPU, flag, whether the VM runs, host programs still using the GPU |
| `winvm-gpu holders` | programs still using the GPU (they block the VM start; close them) |
| `winvm-gpu on` / `winvm-gpu off` | one-time setup (sets the Hyprland flag, then binds) / stop using the GPU for the VM (`off` needs the VM shut down, removes the flag, needs a log out/in for the desktop to use the GPU) |

With the flag set, the hook `qemu.d/win11-gpu` binds the GPU to vfio-pci at every VM start and returns it
to the Linux driver at every stop (log: `journalctl -t winvm-gpu`). Hyprland takes any GPU that appears
while it runs, so the generated udev rule `72-winvm-gpu-seat.rules` keeps the GPU off the login seat and
logind refuses to hand it over (see `LESSONS.md`). A program holding the GPU (btop's GPU panel,
nvidia-smi, CUDA work) makes the start fail; the launcher names it.

**USB off switch:** `touch ~/.config/windows/usb-auto-off` stops automatic attachment of USB devices;
delete the file to turn it back on.

**Change the configuration:** edit the bundle's `win11-vm.conf` (or `/etc/win11-vm.conf` as root), then
re-run `./install.sh --conf win11-vm.conf` to propagate it (it regenerates the udev rule and the
tmpfiles rule). Keys that live in the VM definition (`GPU_PCI`, `IOMMU_LIMIT`, `LG_SHM_MB`) are applied
to the VM by `./enable-gpu.sh` (VM shut off); it only adds what is missing and never replaces existing
devices, so after changing them check `./enable-gpu.sh --dry-run`.

**Uninstall** (manual; every item needs the human's approval, the system ones need root):

- `winvm-gpu off` first (VM shut down). Then remove the flag-related block from `hyprland.lua` if wanted.
- System files: `/usr/local/bin/winvm-gpu`, `/usr/local/bin/winvm-usb`,
  `/etc/libvirt/hooks/qemu.d/win11-usb`, `/etc/libvirt/hooks/qemu.d/win11-gpu`, `/etc/tmpfiles.d/10-looking-glass.conf`,
  `/etc/udev/rules.d/99-winvm-usb.rules`, `/etc/udev/rules.d/72-winvm-gpu-seat.rules`, `/etc/win11-vm.conf`, and the four ufw rules whose comments
  are `libvirt-dhcp`, `libvirt-dns`, `libvirt-vm-out`, `libvirt-vm-in` (`ufw status numbered`, then
  `ufw delete <n>`). Then `udevadm control --reload` and restart libvirtd.
- User files: `~/.local/bin/win11-vm`, `~/.local/share/applications/windows-11-gpu.desktop`,
  `~/.config/looking-glass/client.ini`, `~/.config/windows/usb-auto-off` if present.
- The VM itself: `virsh -c qemu:///system undefine <VM_NAME> --nvram --tpm`, then the disk
  `/var/lib/libvirt/images/<VM_NAME>.qcow2` and the ISOs in that directory.
- Backups: `/var/backups/win11-gpu-vm/` and `~/.local/state/win11-gpu-vm/backups/`.

## 12. When something fails

Read `LESSONS.md`: it lists the fifteen failures that occurred while building this, with the exact error
text, cause and fix. `guest/GUEST-STEPS.md` has a troubleshooting section for the Windows side.
