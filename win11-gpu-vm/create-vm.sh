#!/bin/bash
# Phase 1: create the plain Windows 11 VM (UEFI + Secure Boot, TPM 2.0, SPICE/QXL) to install Windows into.
#
#   ./create-vm.sh --iso WINDOWS11.iso [options]
#
#   --iso PATH          Windows 11 installer ISO (required, except with --dry-run)
#   --virtio-iso PATH   virtio driver ISO (default /var/lib/libvirt/images/virtio-win.iso, installed by
#                       the AUR package virtio-win; ./install.sh --packages installs it)
#   --memory MiB        guest RAM (default 16384)
#   --vcpus N           guest vCPUs, an even number: N/2 cores x 2 threads (default 8)
#   --disk-size GiB     virtual disk size, at least 64 (default 256)
#   --name NAME         libvirt domain name (default VM_NAME from the config)
#   --conf FILE         read FILE instead of /etc/win11-vm.conf
#   --dry-run           create nothing: print the root commands and the virt-install command
#
# The disk /var/lib/libvirt/images/NAME.qcow2 is created first, as an empty file marked No_COW on btrfs
# (a copy-on-write disk image with cache=none gives checksum failures and QEMU I/O errors there). That
# needs root and goes through one pkexec prompt. ISOs outside /var/lib/libvirt/images are copied into it
# in the same step, because the QEMU user cannot read your home directory.
# Afterwards ./enable-gpu.sh adds the GPU once Windows is installed.
set -euo pipefail

B=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SYS_CONF=/etc/win11-vm.conf
URI=qemu:///system
IMG_DIR=/var/lib/libvirt/images

die() { echo "create-vm.sh: $*" >&2; exit 1; }

# ---------------------------------------------------------------------------------------------
# Root half: `pkexec create-vm.sh __root <name> <size GiB> [<iso source> <iso target name>]...`
# Creates the disk (No_COW on btrfs), then copies the ISOs. Never removes anything: if a step fails
# the message names what was left behind.
# ---------------------------------------------------------------------------------------------
if [[ ${1:-} == __root ]]; then
  [[ $EUID == 0 ]] || die "__root must run as root"
  NAME=$2 SIZE=$3
  shift 3
  [[ $NAME =~ ^[A-Za-z0-9_.-]+$ ]] || die "bad name: $NAME"
  [[ $SIZE =~ ^[0-9]+$ ]] || die "bad size: $SIZE"
  DISK=$IMG_DIR/$NAME.qcow2
  [[ ! -e $DISK ]] || die "$DISK already exists"
  OWNER=root
  for u in libvirt-qemu qemu; do if id -u "$u" >/dev/null 2>&1; then OWNER=$u; break; fi; done

  install -m 0600 -o "$OWNER" -g "$OWNER" /dev/null "$DISK"
  if [[ $(stat -f -c %T "$IMG_DIR") == btrfs ]]; then
    chattr +C "$DISK"   # only works while the file is empty
  fi
  qemu-img create -f qcow2 "$DISK" "${SIZE}G" || die "qemu-img failed; the empty file $DISK was left behind, delete it before retrying"
  if [[ $(stat -f -c %T "$IMG_DIR") == btrfs ]]; then
    [[ $(lsattr -d "$DISK") == *C* ]] || die "$DISK lost its No_COW attribute; delete it and report this"
  fi
  echo "  created $DISK (owner $OWNER$([[ $(stat -f -c %T "$IMG_DIR") == btrfs ]] && echo ", No_COW"))"

  while [[ $# -ge 2 ]]; do
    src=$1 dst=$IMG_DIR/$2
    [[ $2 =~ ^[A-Za-z0-9_.-]+$ ]] || die "bad ISO target name: $2"
    shift 2
    [[ ! -e $dst ]] || die "$dst already exists"
    install -m 0644 -o "$OWNER" -g "$OWNER" "$src" "$dst" || die "copy failed; a partial $dst may be left behind, delete it before retrying"
    echo "  copied $src -> $dst"
  done
  exit 0
fi

# ---------------------------------------------------------------------------------------------
# User half.
# ---------------------------------------------------------------------------------------------
MEM=16384 VCPUS=8 DISK_GB=256 ISO="" VIRTIO_ISO=$IMG_DIR/virtio-win.iso NAME="" CONF=$SYS_CONF DRY=0
while [[ $# -gt 0 ]]; do
  case $1 in
    --iso) ISO=${2:?--iso needs a file}; shift ;;
    --virtio-iso) VIRTIO_ISO=${2:?--virtio-iso needs a file}; shift ;;
    --memory) MEM=${2:?--memory needs MiB}; shift ;;
    --vcpus) VCPUS=${2:?--vcpus needs a number}; shift ;;
    --disk-size) DISK_GB=${2:?--disk-size needs GiB}; shift ;;
    --name) NAME=${2:?--name needs a name}; shift ;;
    --conf) CONF=$(realpath "${2:?--conf needs a file}"); shift ;;
    --dry-run) DRY=1 ;;
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
  shift
done
[[ $EUID != 0 ]] || die "run as your normal user, not root (it asks for root itself)"

if [[ -z $NAME ]]; then
  [[ -r $CONF ]] || die "$CONF not found. Run ./install.sh first (or pass --conf FILE or --name NAME)"
  # Only plain KEY=value lines are accepted, same rule as install.sh.
  bad=$(grep -nvE '^[[:space:]]*(#.*)?$|^[A-Z_]+=("[^"`$\\]*"|[^"`$\\ ;&|<>()]*)[[:space:]]*(#.*)?$' "$CONF" || true)
  [[ -z $bad ]] || die "$CONF: only KEY=value lines are allowed:"$'\n'"$bad"
  # shellcheck source=win11-vm.conf.example
  . "$CONF"
  NAME=${VM_NAME:-}
  [[ -n $NAME ]] || die "$CONF: VM_NAME is empty"
fi
[[ $NAME =~ ^[A-Za-z0-9_.-]+$ ]] || die "VM name: letters, digits, . _ - only"
[[ $MEM =~ ^[0-9]+$ ]] && (( MEM >= 4096 )) || die "--memory: MiB, at least 4096 (Windows 11 needs 4 GiB)"
[[ $VCPUS =~ ^[0-9]+$ ]] && (( VCPUS >= 2 && VCPUS % 2 == 0 )) || die "--vcpus: an even number, at least 2 (threads=2 per core)"
[[ $DISK_GB =~ ^[0-9]+$ ]] && (( DISK_GB >= 64 )) || die "--disk-size: GiB, at least 64 (Windows 11 minimum)"
for c in virt-install virsh qemu-img; do command -v "$c" >/dev/null || die "$c not found (install the packages: ./install.sh --packages)"; done

DISK=$IMG_DIR/$NAME.qcow2
CORES=$((VCPUS / 2))

# ISOs must live where the QEMU user can read them: inside IMG_DIR, otherwise copied there.
COPIES=()   # pairs: source, target name
place_iso() {  # place_iso <var name> <label> <required 0|1>
  local -n ref=$1
  local p=${ref:-} dst
  if [[ -z $p ]]; then ref="$IMG_DIR/<$2>"; return; fi
  if [[ ! -r $p ]]; then
    if [[ $3 == 1 && $DRY == 0 ]]; then
      die "$2: $p does not exist or is not readable$([[ $2 == virtio-iso ]] && echo " (./install.sh --packages installs the virtio-win package)")"
    fi
    echo "NOTE: $2: $p does not exist or is not readable (a real run would stop here)"
    ref=$(realpath -m "$p"); return
  fi
  p=$(realpath "$p")
  if [[ $(dirname "$p") == "$IMG_DIR" ]]; then ref=$p; return; fi
  dst=$(basename "$p")
  [[ $dst =~ ^[A-Za-z0-9_.-]+$ ]] || die "$2: file name '$dst' has characters other than letters, digits, . _ -; rename it"
  [[ ! -e $IMG_DIR/$dst ]] || die "$IMG_DIR/$dst already exists; pass that path instead of $p"
  COPIES+=("$p" "$dst")
  ref=$IMG_DIR/$dst
}
[[ -n $ISO || $DRY == 1 ]] || die "--iso is required (the Windows 11 ISO from microsoft.com/software-download/windows11)"
place_iso ISO "windows-iso" 1
place_iso VIRTIO_ISO "virtio-iso" 1

# Refuse to clobber anything (a dry run only reports it).
DOMAIN_EXISTS=0
if virsh -c "$URI" dominfo "$NAME" >/dev/null 2>&1; then DOMAIN_EXISTS=1; fi
refuse() {
  if [[ $DRY == 1 ]]; then echo "NOTE: $1 (a real run would refuse)"; else die "$1. Use --name for another VM, or remove the old one first"; fi
}
if [[ $DOMAIN_EXISTS == 1 ]]; then refuse "libvirt domain '$NAME' already exists"; fi
if [[ -e $DISK ]]; then refuse "$DISK already exists"; fi
BTRFS=0
if [[ $(stat -f -c %T "$IMG_DIR" 2>/dev/null) == btrfs ]]; then BTRFS=1; fi

# vi_args <main disk spec>: the virt-install argument list.
vi_args() {
  VI=(virt-install --connect "$URI" --name "$NAME" --os-variant win11
    --memory "$MEM" --vcpus "$VCPUS,sockets=1,cores=$CORES,threads=2" --cpu host-passthrough
    --machine q35 --features smm.state=on
    --boot uefi,firmware.feature0.name=secure-boot,firmware.feature0.enabled=yes
    --tpm backend.type=emulator,backend.version=2.0,model=tpm-crb
    --disk "$1"
    --disk "path=$ISO,device=cdrom,bus=sata"
    --disk "path=$VIRTIO_ISO,device=cdrom,bus=sata"
    --network network=default,model=virtio
    --graphics spice --video qxl --sound ich9
    --controller type=usb,model=qemu-xhci
    --redirdev usb,type=spicevmc --redirdev usb,type=spicevmc
    --noautoconsole)
}
quote_cmd() {  # print an argument list one option per line, quoting only where needed
  local a first=1
  for a in "$@"; do
    [[ $a =~ ^[A-Za-z0-9_@=:./,+-]+$ ]] || a=$(printf %q "$a")
    if [[ $a == --* && $first == 0 ]]; then printf ' \\\n  '; elif [[ $first == 0 ]]; then printf ' '; fi
    printf %s "$a"; first=0
  done
  echo
}
vi_args "path=$DISK,format=qcow2,bus=virtio,cache=none,discard=unmap"

root_cmd=(pkexec "$B/create-vm.sh" __root "$NAME" "$DISK_GB" "${COPIES[@]}")

if [[ $DRY == 1 ]]; then
  echo "Dry run: nothing is created."
  echo
  echo "# 1. As root, one pkexec prompt:"
  echo "install -m 0600 -o libvirt-qemu -g libvirt-qemu /dev/null $DISK"
  if [[ $BTRFS == 1 ]]; then echo "chattr +C $DISK                  # btrfs: No_COW, only possible while the file is empty"
  else echo "# (not btrfs: no chattr +C needed)"; fi
  echo "qemu-img create -f qcow2 $DISK ${DISK_GB}G"
  for ((i = 0; i < ${#COPIES[@]}; i += 2)); do
    echo "install -m 0644 -o libvirt-qemu -g libvirt-qemu ${COPIES[i]} $IMG_DIR/${COPIES[i+1]}"
  done
  printf '# (the real run does this through: %s)\n' "$(printf '%q ' "${root_cmd[@]}")"
  echo
  echo "# 2. As you:"
  quote_cmd "${VI[@]}"
  echo
  # Validate the virt-install arguments without creating anything. virt-install --print-xml
  # creates a missing disk when given size=, so the not-yet-existing disk is swapped for an existing
  # file; that needs a name not in use and an ISO that exists.
  if [[ $DOMAIN_EXISTS == 1 ]]; then
    echo "Validation skipped: a domain named '$NAME' exists (use --name to validate under another name)."
  elif [[ ! -r $ISO || ! -r $VIRTIO_ISO ]]; then
    echo "Validation skipped: both ISOs must exist to run virt-install --print-xml."
  else
    vi_args "path=$VIRTIO_ISO,device=cdrom,bus=sata"
    if "${VI[@]}" --check all=off --print-xml >"${TMPDIR:-/tmp}/create-vm-validate.$$" 2>&1; then
      echo "Validation: virt-install accepts these options (checked with --print-xml, nothing created)."
    else
      echo "Validation FAILED:"; cat "${TMPDIR:-/tmp}/create-vm-validate.$$"
    fi
    rm -f "${TMPDIR:-/tmp}/create-vm-validate.$$"
  fi
  exit 0
fi

echo "Creating the disk $DISK (${DISK_GB} GiB): approve the password prompt…"
"${root_cmd[@]}"
echo "Creating the VM '$NAME'…"
"${VI[@]}" || die "virt-install failed; the disk $DISK was kept. Delete it (pkexec rm $DISK) before running this again"

cat <<EOF

'$NAME' is running and booting the Windows installer.

Next steps:
  1. Open its screen:  virt-viewer --connect $URI $NAME     (or: virt-manager)
     Click into the window and press a key at "Press any key to boot from CD or DVD".
  2. At "Where do you want to install Windows?" the list is empty: choose "Load driver" > Browse,
     open the virtio-win CD, go to viostor\\w11\\amd64 and pick the Red Hat VirtIO SCSI controller.
     The disk then appears; install onto it.
  3. After the first login run virtio-win-guest-tools.exe from the same CD (drivers + guest agent).
  4. Shut Windows down completely and continue with guest/GUEST-STEPS.md step 3 (./enable-gpu.sh,
     NVIDIA driver, Looking Glass host, Virtual Display Driver, then ./enable-gpu.sh --final).
EOF
