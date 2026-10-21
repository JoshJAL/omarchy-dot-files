#!/bin/bash
# Install the win11 GPU-passthrough VM support files from this bundle, driven by /etc/win11-vm.conf.
#
#   ./install.sh [--conf FILE] [--packages]   install; root parts go through one pkexec prompt
#   ./install.sh --check [--conf FILE]        compare what is installed with the bundle, write nothing,
#                                             exit 1 on any drift
#
#   --conf FILE   use FILE as the machine config (it is installed as /etc/win11-vm.conf);
#                 without it the existing /etc/win11-vm.conf is used
#   --packages    first install the packages (pacman + AUR via yay), enable libvirtd, autostart
#                 the default network and add you to the libvirt group
#
# Run it as your normal user (VM_USER in the config), not with sudo. Files that get replaced are
# backed up first: system files to /var/backups/win11-gpu-vm/<time>/, yours to
# ~/.local/state/win11-gpu-vm/backups/<time>/ (outside every directory that reads *.conf/*.rules/hooks).
set -euo pipefail

B=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
F=$B/files
SYS_CONF=/etc/win11-vm.conf
PACMAN_PKGS=(qemu-desktop qemu-hw-usb-host qemu-hw-usb-redirect libvirt virt-manager virt-viewer
  edk2-ovmf swtpm dnsmasq libvirt-python)
AUR_PKGS=(looking-glass virtio-win)
UFW_RULES=(  # "<tuple regex in /etc/ufw/user.rules> => <ufw arguments>"  (Omarchy's ufw drops VM DHCP/DNS/NAT)
  'allow udp 67 .* in_virbr0( |$) => allow in on virbr0 to any port 67 proto udp comment libvirt-dhcp'
  'allow any 53 .* in_virbr0( |$) => allow in on virbr0 to any port 53 comment libvirt-dns'
  'route:allow any any .* in_virbr0( |$) => route allow in on virbr0 comment libvirt-vm-out'
  'route:allow any any .* out_virbr0( |$) => route allow out on virbr0 comment libvirt-vm-in'
)

die() { echo "install.sh: $*" >&2; exit 1; }

# ---------------------------------------------------------------------------------------------
# Root half: `pkexec install.sh __root <stage> <stamp> <packages 0|1> <user>`. Copies the staged
# system files in place, then reloads whatever they feed.
# ---------------------------------------------------------------------------------------------
if [[ ${1:-} == __root ]]; then
  [[ $EUID == 0 ]] || die "__root must run as root"
  S=$2 TS=$3 PKG=$4 U=$5
  changed=()
  while IFS= read -r -d '' src; do
    dst=${src#"$S"/root}
    if [[ -e $dst ]] && cmp -s "$src" "$dst" && [[ $(stat -c %a "$src") == $(stat -c %a "$dst") ]]; then continue; fi
    if [[ -e $dst ]]; then install -D -m 0600 "$dst" "/var/backups/win11-gpu-vm/$TS$dst"; fi
    install -D -o root -g root -m "$(stat -c %a "$src")" "$src" "$dst"
    echo "  installed $dst"
    changed+=("$dst")
  done < <(find "$S/root" -type f -print0)

  systemd-tmpfiles --create /etc/tmpfiles.d/10-looking-glass.conf
  if [[ " ${changed[*]} " == *" /etc/udev/rules.d/99-winvm-usb.rules "* ]]; then udevadm control --reload; fi

  if [[ $PKG == 1 ]]; then
    systemctl enable --now libvirtd.service
    virsh -c qemu:///system net-autostart default >/dev/null
    virsh -c qemu:///system net-start default >/dev/null 2>&1 || true
    usermod -aG libvirt "$U"
  fi

  if command -v ufw >/dev/null && grep -qx 'ENABLED=yes' /etc/ufw/ufw.conf 2>/dev/null; then
    for r in "${UFW_RULES[@]}"; do
      grep -qE "^### tuple ### ${r%% => *}" /etc/ufw/user.rules || { read -ra a <<<"${r#* => }"; ufw "${a[@]}"; }
    done
  fi

  # libvirtd only discovers hook scripts at startup. Restarting it leaves running VMs alone.
  if [[ " ${changed[*]} " == *" /etc/libvirt/hooks/qemu.d/"* ]]; then
    systemctl try-restart libvirtd.service virtqemud.service
    echo "  restarted libvirtd (new hook)"
  fi
  [[ ${#changed[@]} -gt 0 && -d /var/backups/win11-gpu-vm/$TS ]] && echo "  backups: /var/backups/win11-gpu-vm/$TS"
  exit 0
fi

# ---------------------------------------------------------------------------------------------
# User half.
# ---------------------------------------------------------------------------------------------
CHECK=0 PACKAGES=0 CONF=$SYS_CONF
while [[ $# -gt 0 ]]; do
  case $1 in
    --check) CHECK=1 ;;
    --packages) PACKAGES=1 ;;
    --conf) CONF=$(realpath "${2:?--conf needs a file}"); shift ;;
    -h|--help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
  shift
done
[[ $EUID != 0 ]] || die "run as your normal user, not root (it asks for root itself)"
[[ -r $CONF ]] || die "$CONF not found. Create one: ./detect.sh > win11-vm.conf, review it, then ./install.sh --conf win11-vm.conf"

# The config is sourced by bash as root later, so only plain KEY=value lines are accepted.
bad=$(grep -nvE '^[[:space:]]*(#.*)?$|^[A-Z_]+=("[^"`$\\]*"|[^"`$\\ ;&|<>()]*)[[:space:]]*(#.*)?$' "$CONF" || true)
[[ -z $bad ]] || die "$CONF: only KEY=value lines are allowed:"$'\n'"$bad"
# shellcheck source=win11-vm.conf.example
. "$CONF"
for k in VM_NAME VM_USER GPU_PCI GPU_NAME LG_SHM_MB USB_STORAGE; do [[ -n ${!k:-} ]] || die "$CONF: $k is empty"; done
: "${IOMMU_LIMIT:=}" "${USB_VENDORS:=}"
[[ $VM_NAME =~ ^[A-Za-z0-9_.-]+$ ]] || die "VM_NAME: letters, digits, . _ - only"
[[ $VM_USER == "$(id -un)" ]] || die "VM_USER=$VM_USER but you are $(id -un); run this as $VM_USER"
for d in $GPU_PCI; do
  [[ $d =~ ^[0-9a-f]{4}:[0-9a-f]{2}:[0-9a-f]{2}\.[0-7]$ ]] || die "GPU_PCI: '$d' is not a PCI address like 0000:01:00.0"
  [[ -e /sys/bus/pci/devices/$d ]] || die "GPU_PCI: $d does not exist on this machine"
done
for v in $USB_VENDORS; do [[ $v =~ ^[0-9a-f]{4}$ ]] || die "USB_VENDORS: '$v' is not a 4-digit lowercase hex vendor id"; done
[[ $USB_STORAGE == [01] ]] || die "USB_STORAGE must be 0 or 1"
[[ -z $IOMMU_LIMIT || $IOMMU_LIMIT =~ ^[0-9]+$ ]] || die "IOMMU_LIMIT must be a number of bits or empty"
[[ $LG_SHM_MB =~ ^[0-9]+$ ]] && (( LG_SHM_MB > 0 && (LG_SHM_MB & (LG_SHM_MB - 1)) == 0 )) || die "LG_SHM_MB must be a power of two"

# ---------------------------------------------------------------------------------------------
# Render every target file into a staging tree: stage/root/<absolute path>, stage/user/<path under $HOME>.
# ---------------------------------------------------------------------------------------------
S=$(mktemp -d "${TMPDIR:-/tmp}/win11-gpu-vm.XXXXXX")
trap 'rm -rf "$S"' EXIT
chmod 0755 "$S"
put() {  # put <mode> <stage-path>  (content on stdin)
  mkdir -p "$(dirname "$S/$2")"; cat >"$S/$2"; chmod "$1" "$S/$2"
}
put 0755 root/usr/local/bin/winvm-gpu <"$F/usr/local/bin/winvm-gpu"
put 0755 root/usr/local/bin/winvm-usb <"$F/usr/local/bin/winvm-usb"
put 0755 root/etc/libvirt/hooks/qemu.d/win11-usb <"$F/etc/libvirt/hooks/qemu.d/win11-usb"
put 0755 root/etc/libvirt/hooks/qemu.d/win11-gpu <"$F/etc/libvirt/hooks/qemu.d/win11-gpu"
put 0644 root/etc/tmpfiles.d/10-looking-glass.conf < <(sed "s|@VM_USER@|$VM_USER|g" "$F/etc/tmpfiles.d/10-looking-glass.conf.in")
put 0644 root$SYS_CONF <"$CONF"
{
  echo "# Generated by win11-gpu-vm/install.sh from $SYS_CONF (USB_VENDORS, USB_STORAGE). Edit that, re-run install.sh."
  echo "# Matching devices are handed to the $VM_NAME VM while it runs (winvm-usb exits at once otherwise)."
  for v in $USB_VENDORS; do
    echo "ACTION==\"add\", SUBSYSTEM==\"usb\", ENV{DEVTYPE}==\"usb_device\", ATTR{idVendor}==\"$v\", RUN+=\"/usr/bin/systemd-run --no-block /usr/local/bin/winvm-usb add %p\""
  done
  if [[ $USB_STORAGE == 1 ]]; then
    echo 'ACTION=="add", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_interface", ENV{INTERFACE}=="8/*", RUN+="/usr/bin/systemd-run --no-block /usr/local/bin/winvm-usb add %p"'
  fi
  if [[ -n $USB_VENDORS || $USB_STORAGE == 1 ]]; then
    echo 'ACTION=="remove", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", RUN+="/usr/bin/systemd-run --no-block /usr/local/bin/winvm-usb del $env{BUSNUM} $env{DEVNUM}"'
  fi
} | put 0644 root/etc/udev/rules.d/99-winvm-usb.rules
put 0755 user/.local/bin/win11-vm <"$F/home/.local/bin/win11-vm"
put 0644 user/.local/share/applications/windows-11-gpu.desktop < <(sed "s|@HOME@|$HOME|g" "$F/home/.local/share/applications/windows-11-gpu.desktop.in")
put 0644 user/.config/looking-glass/client.ini <"$F/home/.config/looking-glass/client.ini"

target() { case $1 in "$S"/root/*) echo "${1#"$S"/root}" ;; *) echo "$HOME/${1#"$S"/user/}" ;; esac; }
same() { [[ -e $2 ]] && cmp -s "$1" "$2" && [[ $(stat -c %a "$1") == $(stat -c %a "$2") ]]; }
ufw_missing() {
  command -v ufw >/dev/null && grep -qx 'ENABLED=yes' /etc/ufw/ufw.conf 2>/dev/null || return 0
  local r
  for r in "${UFW_RULES[@]}"; do grep -qE "^### tuple ### ${r%% => *}" /etc/ufw/user.rules 2>/dev/null || echo "ufw ${r#* => }"; done
}

# ---------------------------------------------------------------------------------------------
# --check
# ---------------------------------------------------------------------------------------------
if [[ $CHECK == 1 ]]; then
  drift=0
  while IFS= read -r -d '' src; do
    dst=$(target "$src")
    if same "$src" "$dst"; then echo "ok       $dst"; continue; fi
    drift=1
    if [[ ! -e $dst ]]; then echo "MISSING  $dst"
    elif cmp -s "$src" "$dst"; then echo "MODE     $dst is $(stat -c %a "$dst"), want $(stat -c %a "$src")"
    else echo "DIFFERS  $dst"; diff -u --label "installed $dst" --label "bundle" "$dst" "$src" | sed 's/^/         /' || true
    fi
  done < <(find "$S/root" "$S/user" -type f -print0 | sort -z)
  if [[ -e /etc/libvirt/hooks/qemu ]] && grep -q winvm-usb /etc/libvirt/hooks/qemu; then
    drift=1; echo "LEGACY   /etc/libvirt/hooks/qemu still runs winvm-usb (now done by qemu.d/win11-usb); remove it"
  fi
  while IFS= read -r m; do drift=1; echo "UFW      missing rule: $m"; done < <(ufw_missing)
  [[ -e /dev/shm/looking-glass ]] || echo "note     /dev/shm/looking-glass does not exist yet (created by tmpfiles at boot or by install.sh)"
  if [[ $drift == 0 ]]; then echo "No drift."; else echo "Drift found. Run ./install.sh$([[ $CONF != "$SYS_CONF" ]] && echo " --conf $CONF") to bring it in line."; fi
  exit $drift
fi

# ---------------------------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------------------------
TS=$(date +%Y%m%d-%H%M%S)
if [[ $PACKAGES == 1 ]]; then
  echo "Installing packages (pacman, then AUR)…"
  pkexec pacman -S --needed --noconfirm "${PACMAN_PKGS[@]}"
  command -v yay >/dev/null || die "yay not found; install ${AUR_PKGS[*]} from the AUR yourself, then re-run without --packages"
  yay -S --needed --noconfirm --sudo pkexec "${AUR_PKGS[@]}"
fi

for src in "$S"/user/.local/bin/win11-vm "$S"/user/.local/share/applications/windows-11-gpu.desktop "$S"/user/.config/looking-glass/client.ini; do
  dst=$(target "$src")
  same "$src" "$dst" && continue
  [[ -e $dst ]] && install -D -m 0600 "$dst" "$HOME/.local/state/win11-gpu-vm/backups/$TS${dst#"$HOME"}"
  install -D -m "$(stat -c %a "$src")" "$src" "$dst"
  echo "  installed $dst"
done

need_root=$PACKAGES
while IFS= read -r -d '' src; do same "$src" "$(target "$src")" || need_root=1; done < <(find "$S/root" -type f -print0)
[[ -n $(ufw_missing) ]] && need_root=1
if [[ $need_root == 1 ]]; then
  echo "System files: approve the password prompt…"
  pkexec "$B/install.sh" __root "$S" "$TS" "$PACKAGES" "$VM_USER"
else
  echo "  system files already up to date"
fi

if [[ -e /etc/libvirt/hooks/qemu ]] && grep -q winvm-usb /etc/libvirt/hooks/qemu; then
  echo "NOTE: /etc/libvirt/hooks/qemu (older single-file hook) also runs winvm-usb. Remove it once the qemu.d hook is confirmed working."
fi
[[ $PACKAGES == 1 ]] && echo "NOTE: you were added to the libvirt group; log out and back in before using virsh as yourself."
echo "Done. Verify with: ./install.sh --check"
