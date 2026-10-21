# Lessons learned

Building this VM hit fifteen separate failures. Most of them failed silently or with a message that
points somewhere else, and each cost real time to diagnose. They are written down here so that, if
something breaks on your machine, you can look up the symptom first. The bundle already handles all
fifteen; each entry says which file does. Use this file when a step of `README.md` or `FOR_AGENT.md`
fails.

Everything below was observed on one machine (Intel laptop with an NVIDIA GPU, Omarchy, libvirt 12.8,
Looking Glass B7). Your hardware may fail in other ways.

## The 15 failures

### 1. Wrong firmware feature name in virt-install

- **Symptom:** `virt-install` fails with `Unable to find 'efi' firmware that is compatible`.
- **Cause:** The boot option `firmware.feature0.name=enrolled-keys` asks for a firmware descriptor that
  Arch's edk2 package does not provide. Its descriptors only offer `secure-boot`.
- **Fix:** Use `--boot uefi,firmware.feature0.name=secure-boot,firmware.feature0.enabled=yes` together
  with `--features smm.state=on`. Handled by `create-vm.sh`.

### 2. `/dev/kvm` has the wrong group and QEMU cannot use it

- **Symptom:** `/dev/kvm` is `root:input 0660` instead of `root:kvm 0666`, and QEMU fails with
  `Could not access KVM kernel module: No such file or directory`.
- **Cause:** A user-added udev rule (`/etc/udev/rules.d/92-via-keyboard.rules`) was split over two lines
  with no trailing `\`. The second line, a bare `GROUP="input"`, has no match key, so it applied to every
  device. KVM also emits a udev "change" event on every VM start, and `50-udev-default.rules` skips the
  permission rules on "change" events, so the wrong value kept being re-applied from the udev database.
- **Fix:** Repair the rule so it is one line (or delete the stray line), then run
  `sudo udevadm trigger --action=add --name-match=kvm`. `detect.sh` scans `/etc/udev/rules.d` for rules that
  have an assignment but no match key and warns about each one, and it checks the `/dev/kvm` permissions.
  The repair itself is manual.

### 3. The VM has no network

- **Symptom:** Windows installs but has no connectivity: no DHCP lease, no DNS, no internet.
- **Cause:** Omarchy enables ufw with default deny for incoming and routed traffic. That drops the
  guest's DHCP and DNS requests to dnsmasq on `virbr0` and the forwarded traffic.
- **Fix:** Allow DHCP (udp 67) and DNS (port 53) in on `virbr0`, plus `route allow in on virbr0` and
  `route allow out on virbr0`. `install.sh` adds all four rules when ufw is enabled and
  `install.sh --check` reports a missing one. Also make sure `virsh -c qemu:///system net-list` shows
  `default` active (`install.sh --packages` autostarts it).

### 4. Microsoft blocks scripted ISO downloads

- **Symptom:** Tools such as `quickget` fail with `Microsoft blocked the automated download request based
  on your IP address`.
- **Cause:** The Windows 11 download page rejects non-browser clients.
- **Fix:** Download the ISO by hand in a normal browser from microsoft.com/software-download/windows11,
  then pass it to `create-vm.sh --iso`.

### 5. Windows setup: no disk, and it insists on a Microsoft account

- **Symptom:** "Where do you want to install Windows?" lists no disks. Later, setup demands a Microsoft
  account and an internet connection.
- **Cause:** The disk is a virtio disk, and Windows setup has no driver for it. Windows 11 setup also
  pushes a Microsoft account.
- **Fix:** Choose "Load driver", browse the virtio CD to `viostor\w11\amd64` and select the Red Hat VirtIO
  SCSI controller. For a local account press Shift+F10 and run `start ms-cxh:localonly`; the fallback is
  `OOBE\BYPASSNRO` (not tested here). Covered in `guest/GUEST-STEPS.md` step 1; `create-vm.sh` attaches
  the virtio ISO and prints these hints.

### 6. The host will not release the GPU

- **Symptom:** `winvm-gpu on` reported `Still in use on the host:` (now: `Close these first, they are using the GPU:`) with Hyprland, Xwayland, systemd-logind
  and the polkit agent holding the GPU's `/dev/dri/cardN` or `/dev/nvidia*`. Unbinding the GPU would hang
  or fail.
- **Cause:** The compositor opens every GPU it finds, and merely loading the NVIDIA EGL/Vulkan/GLX
  libraries opens `/dev/nvidia0`.
- **Fix:** Start Hyprland without the GPU. A flag file `~/.config/hypr/gpu-vm-mode` makes the Hyprland
  config leave the passthrough GPU out of `AQ_DRM_DEVICES` and point EGL, GLX and Vulkan at mesa and the
  iGPU. The flag is only read at Hyprland start, so you must log out and in; only then can
  `winvm-gpu on` bind the GPU to vfio-pci (`driver_override`, unbind, `drivers_probe`). Handled by
  `files/usr/local/bin/winvm-gpu` (two-step `on`) and `hyprland-snippet.lua`, which you merge into your
  Hyprland config.

### 7. The IOMMU is narrower than the CPU

- **Symptom:** QEMU dies at VM start with `qemu: hardware error: vfio: DMA mapping failed, unable to
  continue`, preceded by `vfio_container_dma_map(..., 0x382800000000, ...) = -22`.
- **Cause:** The IOMMU supported 39 address bits (MGAW, read from bits 21:16 of
  `/sys/class/iommu/dmar*/intel-iommu/cap`, plus one) while the CPU has 42 physical address bits. The guest
  was handed addresses the IOMMU cannot map.
- **Fix:** Cap the guest with `<maxphysaddr mode='passthrough' limit='39'/>` inside `<cpu>`.
  `detect.sh` reads the width (Intel only) and proposes `IOMMU_LIMIT`; `enable-gpu.sh` writes the element.
  On AMD the width is not checked: if you see this error, set `IOMMU_LIMIT` to 39 or 48 yourself.

### 8. Btrfs checksum errors on the VM disk

- **Symptom:** The kernel log shows `BTRFS warning ... csum failed ... ino <the qcow2 file>` and
  `direct IO failed`, then QEMU stops with an `IO error` on `device='virtio-disk0'`.
- **Cause:** A copy-on-write qcow2 file on btrfs combined with `cache=none` (O_DIRECT) produces checksum
  mismatches when the guest rewrites blocks that are in flight.
- **Fix:** The image must be NOCOW. `chattr +C` only works on an empty file, so create the empty file, set
  the attribute, then create the image in it. To rescue an existing image copy it into such a file
  (`dd bs=64K conv=noerror,sync,sparse`), then verify with `cmp` and `qemu-img check`. `create-vm.sh` does
  this for a new disk on btrfs, and `detect.sh` warns when the images directory is on btrfs.

### 9. The NVIDIA driver refuses to start in a VM

- **Symptom:** The GPU shows a warning icon with "Code 43" in Windows Device Manager (the usual
  behavior of the NVIDIA driver in a VM it recognises). It did not occur after the fix below.
- **Cause:** The driver detects the hypervisor.
- **Fix:** Hide KVM (`<kvm><hidden state='on'/></kvm>`) and set a Hyper-V vendor id
  (`<hyperv><vendor_id state='on' value='KVMKVMKVM'/>`). The PCI hostdevs use `managed='no'` because
  `winvm-gpu` does the vfio-pci binding itself; libvirt must not rebind them. Handled by `enable-gpu.sh`.

### 10. Looking Glass has nothing to capture

- **Symptom:** The Looking Glass host in Windows logs `Failed to locate a valid output device` (or the
  client says the host is not running).
- **Cause:** A laptop GPU, or a desktop GPU with no monitor plugged in, has no active display output, and
  Looking Glass can only capture a display attached to the GPU.
- **Fix:** Install a virtual monitor: Virtual Display Driver (MttVDD, version 25.7.23, signed by SignPath
  Foundation), bound to the passthrough GPU by pinning `<friendlyname>` in
  `C:\VirtualDisplayDriver\vdd_settings.xml`. Two traps: `pnputil` rejects the driver with `publisher ...
  not yet been established as trusted` until the signer certificate is in `LocalMachine\TrustedPublisher`,
  and this Windows build's `pnputil` has no `/add-device`, so the root-enumerated device (`Root\MttVDD`)
  must be created through SetupAPI (`SetupDiCreateDeviceInfoW`, `SetupDiCallClassInstaller(DIF_REGISTERDEVICE)`,
  `UpdateDriverForPlugAndPlayDevicesW`). `guest/install-vdd.ps1` does all of it (and verifies the signature
  first); run it from the host with `guest/vm-guest-exec`. `GPU_NAME` must match Device Manager exactly.

### 11. Clicks land on an invisible screen

- **Symptom:** In the Looking Glass window the mouse and keyboard seem dead or act on something you
  cannot see.
- **Cause:** While the emulated QXL display exists, Windows has two displays and input is routed to the
  QXL one, which Looking Glass does not show.
- **Fix:** Remove the emulated video device (`<video><model type='none'/></video>`), and use virtio mouse
  and keyboard. Do this only after Looking Glass shows the desktop, because without QXL there is no
  picture until the GPU, its driver and the virtual display work. `enable-gpu.sh` does the
  virtio input in stage 1 and `enable-gpu.sh --final` removes QXL.

### 12. Looking Glass client `-s` disables input

- **Symptom:** The Looking Glass window shows the desktop but mouse and keyboard do nothing.
- **Cause:** `-s` turns the SPICE client off, and SPICE carries the input.
- **Fix:** Do not pass `-s`. The launcher `win11-vm` runs plain `looking-glass-client`.

### 13. Looking Glass shared memory

- **Symptom:** The client cannot open `/dev/shm/looking-glass` (missing or not accessible), or the
  host and client see no shared memory.
- **Cause:** Looking Glass needs an `ivshmem` device in the VM and a file in `/dev/shm` that your user
  can read and that the QEMU user can write.
- **Fix:** Add `<shmem name='looking-glass'><model type='ivshmem-plain'/><size unit='M'>128</size></shmem>`
  and create the file at boot with `/etc/tmpfiles.d/10-looking-glass.conf` containing
  `f /dev/shm/looking-glass 0660 <your user> kvm -`. `enable-gpu.sh` adds the device (size `LG_SHM_MB`) and
  `install.sh` installs the tmpfiles rule and creates the file.

### 14. No way to drive Windows from the host (guest agent channel)

- **Symptom:** `guest/vm-guest-exec` fails with `Guest agent is not responding`, so the Windows side
  cannot be scripted.
- **Cause:** The VM has no channel to the QEMU guest agent, or the agent is not installed/running in
  Windows.
- **Fix:** Add `<channel type='unix'><target type='virtio' name='org.qemu.guest_agent.0'/></channel>`
  (`enable-gpu.sh` does) and install `virtio-win-guest-tools.exe` in Windows. With that,
  `guest/vm-guest-exec` runs PowerShell in the guest through `guest-exec`, which makes the driver
  installation scriptable (and lets a coding agent do it).

### 15. USB keys and drives need to follow into the VM

- **Symptom:** A security key or USB stick plugged in while Windows runs is not seen by Windows; a
  device that was already plugged in when the VM started is missing; or a naive udev rule or libvirt hook
  makes things hang.
- **Cause:** Nothing hands host USB devices to a running VM by itself, and the obvious ways to do it
  deadlock or misparse:
  - udev `RUN` programs block the device event queue, so the attach cannot run inline.
  - A libvirt hook runs while libvirtd waits for it, and `virsh` waits for libvirtd, so calling `virsh`
    inside the hook deadlocks.
  - libvirtd only loads hook scripts at startup, so a newly installed hook does nothing until it restarts.
  - udev's `BUSNUM` and `DEVNUM` arrive zero-padded (`001`, `009`); bash reads `009` as a bad octal
    number, so the device lookup never matches.
- **Fix:**
  - A udev rule matches your vendor ids (`USB_VENDORS`) and mass-storage interfaces
    (`INTERFACE=="8/*"`) and runs `systemd-run --no-block /usr/local/bin/winvm-usb add %p`. Removals run
    `winvm-usb del $env{BUSNUM} $env{DEVNUM}`.
  - `winvm-usb` uses `virsh attach-device --live` and `detach-device --live` with a
    `<hostdev mode='subsystem' type='usb' managed='yes'>` naming the bus and device number, normalised to
    decimal.
  - A libvirt hook (`/etc/libvirt/hooks/qemu.d/win11-usb`) runs `winvm-usb sync` five seconds after the
    `started` event, via `systemd-run --on-active=5`, which attaches devices that were already plugged in.
  - `install.sh` generates the udev rule (`/etc/udev/rules.d/99-winvm-usb.rules`) from the config,
    installs the hook and restarts libvirtd when the hook is new (a running VM is not affected).
  - Files: `files/usr/local/bin/winvm-usb`, `files/etc/libvirt/hooks/qemu.d/win11-usb`, `install.sh`.

## Also learned

- **Docker/dockur does not do this.** Omarchy's built-in Windows VM runs in Docker (dockur). It could not
  use the discrete GPU in any useful way, so this bundle uses plain libvirt/QEMU instead.
- **A libvirt hook must not run `virsh` synchronously.** libvirtd waits for the hook to finish, and
  `virsh` waits for libvirtd, so it deadlocks. The hook defers the work with `systemd-run`. libvirtd also
  only discovers hooks at startup (see 15).
- **A udev `RUN` must not block.** It holds up the device event queue. Use `systemd-run --no-block`.
- **Zero-padded `BUSNUM`/`DEVNUM`** from udev must be forced to decimal before use (see 15).
- **Microsoft blocks scripted ISO downloads.** Use a browser (see 4).
- **Looking Glass client `-s` disables SPICE**, and with it, input (see 12).
- **Windows kept resetting "Extend these displays" while QXL was present.** The cure is not to fight the
  setting but to finish the build with `./enable-gpu.sh --final`, which removes QXL.
- **A USB stick that has Linux partitions only shows its FAT partition in Windows.** That is not a
  passthrough failure; Windows cannot read ext4/btrfs/LUKS. Check the stick with `lsblk` on the host.
- **Hyprland grabs a GPU that appears while it runs.** `AQ_DRM_DEVICES` only filters the startup scan;
  aquamarine's udev hotplug path opens any new DRM card. Giving the GPU back to `nvidia` when the VM
  stopped made Hyprland open `/dev/dri/card2` within a second, and the next VM start then needed a log
  out/in. So the hook leaves the GPU on vfio-pci after the VM stops; only `win11-vm gpu-off` returns it.
- **Closing the Looking Glass window used to leave Windows running.** It kept the USB devices, the GPU and
  its RAM. The launcher now shuts Windows down (ACPI) when the window closes, and closes the window when
  Windows stops.
