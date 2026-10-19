# Windows-side steps

The manual part of the setup, in order. Everything here happens inside Windows (or drives it from
the host with `guest/vm-guest-exec`). Host-side scripts are in the folder above.

Order of the whole build:

1. `./create-vm.sh` (phase 1): plain VM with SPICE/QXL.
2. Steps 1-2 below: install Windows and the guest tools.
3. Step 3: shut down, `./enable-gpu.sh` (stage 1: GPU added, **QXL screen kept** so virt-viewer still
   shows Windows), `winvm-gpu on`, boot.
4. Steps 4-6 below, watching the QXL screen in virt-viewer: NVIDIA driver, Looking Glass host, Virtual
   Display Driver.
5. Step 7: shut down, `./enable-gpu.sh --final` (QXL removed), then use the launcher (Looking Glass).

This is the order that worked: the GPU and the QXL screen coexisted until Looking Glass worked, and
only then was QXL removed (with QXL present, Looking Glass clicks land on the invisible QXL screen).

`<GPU_NAME>` is `GPU_NAME` from `/etc/win11-vm.conf` (the name Windows shows for the GPU, for example
`NVIDIA GeForce RTX 4070 Laptop GPU`).

## 1. Install Windows (VM from `create-vm.sh`)

1. Start the VM and open it in virt-manager or virt-viewer. When the screen says
   **Press any key to boot from CD or DVD**, press a key. If you miss it the VM does not boot the installer
   (typically a UEFI shell or boot menu); force it off and start it again.
2. Language and edition as you like. Choose **Custom: Install Windows only**.
3. The disk list is empty because Windows has no driver for the virtio disk:
   **Load driver** -> **Browse** -> the virtio CD (usually drive `E:` or `D:`) ->
   `viostor\w11\amd64` -> OK -> select the "Red Hat VirtIO SCSI controller" driver -> Next.
   The 256 GB disk now appears; select it and continue.
4. At the network screen ("Let's connect you to a network" / no internet) the installer wants a Microsoft
   account. To make a local account instead, press **Shift+F10** for a console and run:

   ```
   start ms-cxh:localonly
   ```

   A local-account dialog opens; fill in a user name and password. (Alternative if that dialog does
   not appear on your build: `oobe\bypassnro`, then the installer reboots and offers "I don't have
   internet". Not tested here.)

## 2. Guest tools

After the first login, open the virtio CD and run **`virtio-win-guest-tools.exe`** (installs the network
driver, the **QEMU guest agent**, the balloon driver and the other virtio drivers). Accept the defaults
and reboot if it asks.

The guest agent this installs is what `guest/vm-guest-exec` talks to. Its channel to the host is added
in step 3, so test it there.

## 3. Shut down and add the GPU

Shut Windows down (Start -> Shut down), then on the host:

```
./enable-gpu.sh     # stage 1: GPU, guest agent channel, Looking Glass memory, ...; QXL stays
winvm-gpu on        # two-step: it may ask you to log out and back in, then run it again
virsh -c qemu:///system start <VM_NAME>     # VM_NAME from /etc/win11-vm.conf
virt-viewer -c qemu:///system <VM_NAME>
```

Windows still shows on the QXL screen in virt-viewer; the GPU appears as a second display adapter
("Microsoft Basic Display Adapter" until its driver is in). Check from the host that the guest agent
answers:

```
guest/vm-guest-exec 'hostname'
```

If this prints the guest's name, `vm-guest-exec` works. If it fails with "Guest agent is not
responding", wait a minute after boot, then see Troubleshooting -> *no network / agent*.

## 4. NVIDIA driver

In Windows (virt-viewer), download the driver for your GPU from nvidia.com (Drivers: pick your GPU,
"Game Ready") and run it; reboot when it asks. The installer needs the GPU attached, so it cannot be
done before step 3. Afterwards Device Manager -> Display adapters shows the GPU by name with no warning
icon. That name is your `GPU_NAME`: if it differs from `/etc/win11-vm.conf`, fix the file (and re-run
`./install.sh`) before step 6.

No Code 43 is expected: `enable-gpu.sh` hides KVM and sets a Hyper-V `vendor_id`. If Device
Manager does show "Code 43" on the GPU, see Troubleshooting.

## 5. Looking Glass host

Download the **Looking Glass B7** Windows host from looking-glass.io (Downloads page). The host version must match the client on the Linux side
(`looking-glass-client --version` must say B7). Run the installer in the guest; it installs the
**Looking Glass (host)** service, which starts at boot and waits for a display output on the GPU.

The service logs "Looking Glass Host Application Not Running" or "Failed to locate a valid output
device" until step 6 is done. That is expected at this point.

## 6. Virtual Display Driver (from the host)

Looking Glass captures a display that is attached to the GPU, and a passed-through laptop GPU (or a
desktop GPU with no monitor plugged in) has none, so install a virtual monitor on it. From the bundle
directory on the host, with the VM running:

```
guest/vm-guest-exec --timeout 600 --file guest/install-vdd.ps1 -- -GpuName "<GPU_NAME>"
```

The script downloads the Virtual Display Driver (MttVDD, GitHub VirtualDrivers/Virtual-Display-Driver),
verifies that it is validly signed by "SignPath Foundation" before trusting it, adds the signer to
Trusted Publishers, writes `C:\VirtualDisplayDriver\vdd_settings.xml` (GPU name, extra resolutions
1920x1200 and 3440x1440, logging on), installs the driver and creates the device. It prints the
final device status and exits 0 on success. Options: `-Resolutions 2560x1440,3840x2160`,
`-VddVersion`, `-VddUrl`, `-ExpectedThumbprint` (see the script's header). It is safe to run again.

Check afterwards (Device Manager is easiest, but from the host):

```
guest/vm-guest-exec 'Get-PnpDevice -Class Display | Format-Table Status,FriendlyName -AutoSize'
```

You want two entries with Status OK: your **NVIDIA GeForce ...** and **Virtual Display Driver**
(the exact friendly name of the virtual one may differ by version).

Optional check before step 7: `looking-glass-client` on the host should now show the virtual
display (input may still go to the QXL screen; that is what step 7 fixes).

## 7. Remove QXL and switch to Looking Glass

1. Shut Windows down, then on the host: `./enable-gpu.sh --final` (sets `video none`; SPICE stays for
   keyboard and mouse).
2. Start the VM with the launcher ("Windows 11 (GPU)" in the app menu, or `win11-vm`), which opens
   `looking-glass-client`.
3. In Windows: Settings -> System -> Display should now list only the virtual monitor. Pick the
   resolution you added (for example 1920x1200).
4. Restart the Looking Glass host service or reboot the guest once if the client still says no
   display.

---

## Troubleshooting

**Looking Glass: "Looking Glass Host Application Not Running" or "Failed to locate a valid output
device"** 
The host has no active output on the GPU. Almost always one of:
- The Virtual Display Driver is not installed: run step 6 and check `Get-PnpDevice -Class Display`.
- It is installed but attached to the wrong adapter: `friendlyname` in
  `C:\VirtualDisplayDriver\vdd_settings.xml` must equal the GPU name exactly as Device Manager shows it.
  Re-run step 6 with the correct `-GpuName "<GPU_NAME>"` (it rewrites the file and restarts the device).
- The service started before the display existed: reboot the guest.
- While QXL is still present (before step 7), Windows may keep resetting "Extend these displays":
  finish step 7 instead of fighting the setting.
- The NVIDIA driver is not installed or the GPU shows an error in Device Manager (step 4).

**The mouse does not work in the Looking Glass window**
Do not pass `-s` to `looking-glass-client`: that option *disables* SPICE, which carries the input. The
launcher does not pass it; if you start the client by hand, use plain `looking-glass-client`. Also check
that the VM has the virtio mouse and keyboard (`virsh -c qemu:///system dumpxml <VM_NAME>` should show
`<input type='mouse' bus='virtio'>` and `<input type='keyboard' bus='virtio'>`), which `enable-gpu.sh`
adds, that the virtio input driver came with the guest tools (step 2), and that QXL is gone
(`./enable-gpu.sh --final`): with QXL present, clicks land on the QXL screen Looking Glass does not show. Press the Scroll Lock key
(Looking Glass' default escape key) to toggle capture.

**No network in the guest, or the guest agent does not answer**
- The virtio network driver comes from `virtio-win-guest-tools.exe` (step 2). Until it is installed
  Windows has no network at all.
- On the host, Omarchy's firewall (ufw) drops the VM's DHCP, DNS and NAT traffic unless the `virbr0`
  rules are present. `./install.sh` adds them (it lists them in `UFW_RULES`); `./install.sh --check`
  reports a missing one. Also check `virsh -c qemu:///system net-list` shows `default` active.
- The guest agent needs the `org.qemu.guest_agent.0` channel (added by `enable-gpu.sh` stage 1) and the "QEMU Guest Agent" Windows service running.

**"Code 43" on the GPU in Device Manager**
Not expected. It means the driver detected a VM: check that `enable-gpu.sh` ran (it sets `<kvm><hidden
state='on'/></kvm>` and a Hyper-V `vendor_id`) and that you rebooted the VM afterwards.

**`vm-guest-exec`: "guest-file-open failed"** 
Only matters for `--transfer file`. The default `--transfer auto` sends this script in a
`-EncodedCommand` and does not need it. Force it with `--transfer encoded`.

**`install-vdd.ps1` stops with a signature error**
It refuses to continue when the driver's signature is not Valid, not from "SignPath Foundation", or does
not match the pinned certificate thumbprint. For a newer release signed with a renewed certificate, check
the release yourself and pass `-ExpectedThumbprint ''` (name check only) or the new thumbprint.

## Not verified here

- The `oobe\bypassnro` alternative and the exact wording of Windows installer screens vary by Windows
  11 build.
- The friendly name the virtual monitor shows in Device Manager may differ from "Virtual Display
  Driver" in newer driver releases.
- Whether the Looking Glass host installer asks to reboot depends on its version; reboot if the
  client reports no display after step 7.
