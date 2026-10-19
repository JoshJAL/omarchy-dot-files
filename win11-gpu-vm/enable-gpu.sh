#!/bin/bash
# Phase 2: turn the plain Windows VM from create-vm.sh into the GPU-passthrough VM, driven by /etc/win11-vm.conf.
#
#   ./enable-gpu.sh [--conf FILE]             stage 1: add the GPU and everything else, keep the QXL screen
#   ./enable-gpu.sh --final [--conf FILE]     stage 2: also remove QXL (video none)
#   ./enable-gpu.sh --dry-run [--final] [--conf FILE]
#                                             print every planned virt-xml command and the XML diff it
#                                             would produce; defines nothing, works while the VM runs
#
#   --conf FILE   read FILE instead of /etc/win11-vm.conf
#   --final       also apply the video-none edit (stage 2)
#   --dry-run     change nothing
#
# Two stages, because Windows has no picture on the GPU until the NVIDIA driver, the Looking Glass
# host and the Virtual Display Driver are installed (guest/GUEST-STEPS.md). Stage 1 runs after Windows
# and the guest tools are installed: the QXL screen stays, so virt-viewer still shows Windows while you
# install those. Stage 2 (--final) runs once Looking Glass shows the desktop: QXL goes, otherwise clicks
# land on the invisible QXL screen. The VM must be shut off. It changes only the VM's persistent
# definition, and only what is missing, so re-running either stage is harmless:
#   - one PCI hostdev per address in GPU_PCI (managed='no': winvm-gpu does the vfio-pci binding)
#   - virtio mouse + virtio keyboard
#   - the Looking Glass shared memory (ivshmem-plain, LG_SHM_MB)
#   - the QEMU guest agent channel
#   - KVM hidden + Hyper-V vendor_id (stops the NVIDIA driver refusing to start in a VM)
#   - maxphysaddr limit IOMMU_LIMIT, if set (without it QEMU fails: "vfio: DMA mapping failed")
#   - --final only: video model none (SPICE graphics stays for input; the GPU is Windows' only display)
set -euo pipefail

SYS_CONF=/etc/win11-vm.conf
URI=qemu:///system

die() { echo "enable-gpu.sh: $*" >&2; exit 1; }

DRY=0 FINAL=0 CONF=$SYS_CONF XML_IN="" XML_OUT=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run) DRY=1 ;;
    --final) FINAL=1 ;;
    --conf) CONF=$(realpath "${2:?--conf needs a file}"); shift ;;
    # Test hooks, not for normal use: edit the XML in FILE instead of the domain (never defines
    # anything; implies --dry-run) and optionally write the edited XML to another file.
    --xml-in) XML_IN=$(realpath "${2:?--xml-in needs a file}"); DRY=1; shift ;;
    --xml-out) XML_OUT=${2:?--xml-out needs a file}; shift ;;
    -h|--help) sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
  shift
done
[[ -z $XML_OUT || -n $XML_IN ]] || die "--xml-out needs --xml-in"
[[ -r $CONF ]] || die "$CONF not found. Run ./install.sh first (or pass --conf FILE)"

# Only plain KEY=value lines are accepted, same rule as install.sh.
bad=$(grep -nvE '^[[:space:]]*(#.*)?$|^[A-Z_]+=("[^"`$\\]*"|[^"`$\\ ;&|<>()]*)[[:space:]]*(#.*)?$' "$CONF" || true)
[[ -z $bad ]] || die "$CONF: only KEY=value lines are allowed:"$'\n'"$bad"
# shellcheck source=win11-vm.conf.example
. "$CONF"
for k in VM_NAME GPU_PCI LG_SHM_MB; do [[ -n ${!k:-} ]] || die "$CONF: $k is empty"; done
: "${IOMMU_LIMIT:=}"
[[ $VM_NAME =~ ^[A-Za-z0-9_.-]+$ ]] || die "VM_NAME: letters, digits, . _ - only"
for d in $GPU_PCI; do
  [[ $d =~ ^[0-9a-f]{4}:[0-9a-f]{2}:[0-9a-f]{2}\.[0-7]$ ]] || die "GPU_PCI: '$d' is not a PCI address like 0000:01:00.0"
  [[ -e /sys/bus/pci/devices/$d ]] || die "GPU_PCI: $d does not exist on this machine"
done
[[ -z $IOMMU_LIMIT || $IOMMU_LIMIT =~ ^[0-9]+$ ]] || die "IOMMU_LIMIT must be a number of bits or empty"
[[ $LG_SHM_MB =~ ^[0-9]+$ ]] && (( LG_SHM_MB > 0 && (LG_SHM_MB & (LG_SHM_MB - 1)) == 0 )) || die "LG_SHM_MB must be a power of two"
for c in virt-xml virsh xmllint; do command -v "$c" >/dev/null || die "$c not found (install the packages: ./install.sh --packages)"; done

W=$(mktemp -d "${TMPDIR:-/tmp}/enable-gpu.XXXXXX")
trap 'rm -rf "$W"' EXIT
CUR=$W/cur.xml NEXT=$W/next.xml

if [[ -n $XML_IN ]]; then
  [[ -r $XML_IN ]] || die "cannot read $XML_IN"
  cp "$XML_IN" "$CUR"
else
  virsh -c "$URI" dominfo "$VM_NAME" >/dev/null 2>&1 || die "no libvirt domain '$VM_NAME' on $URI. Run ./create-vm.sh first"
  state=$(virsh -c "$URI" domstate "$VM_NAME")
  if [[ $DRY == 0 && $state != "shut off" ]]; then
    die "'$VM_NAME' is $state. Shut Windows down completely, then run this again"
  fi
  # The inactive XML is the persistent definition: what the next boot will use, even while the VM runs.
  virsh -c "$URI" dumpxml --inactive "$VM_NAME" >"$CUR"
fi

# has <xpath>: true when the current XML matches.
has() { [[ $(xmllint --xpath "boolean($1)" "$CUR") == true ]]; }

APPLIED=0 PRESENT=0
present() { echo "  ok     $1 (already present)"; PRESENT=$((PRESENT + 1)); }

# apply <description> <virt-xml action and options...>
# Real run: virt-xml edits and defines the domain. Dry run: virt-xml reads the working XML on stdin,
# prints the diff, and the result becomes the input of the next step (so later diffs build on earlier ones).
apply() {
  local desc=$1 q err=$W/err
  shift
  echo "  apply  $desc"
  q=""
  for a in "$@"; do if [[ $a =~ ^[A-Za-z0-9_@=:./,+-]+$ ]]; then q+=" $a"; else q+=" $(printf %q "$a")"; fi; done
  if [[ $DRY == 1 ]]; then
    echo "    virt-xml --connect $URI$q"
    virt-xml --connect "$URI" "$@" --print-diff <"$CUR" 2>"$err" | sed 's/^/    | /' || true
    virt-xml --connect "$URI" "$@" --print-xml <"$CUR" >"$NEXT" 2>"$err" || { cat "$err" >&2; die "virt-xml failed for: $desc"; }
    mv "$NEXT" "$CUR"
  else
    echo "    virt-xml --connect $URI $VM_NAME$q"
    virt-xml --connect "$URI" "$VM_NAME" "$@" >/dev/null 2>"$err" || { cat "$err" >&2; die "virt-xml failed for: $desc"; }
    virsh -c "$URI" dumpxml --inactive "$VM_NAME" >"$CUR"
  fi
  APPLIED=$((APPLIED + 1))
}

# XPath predicate for a hostdev source address. libvirt prints 0x-prefixed hex, virt-xml prints decimal; accept both.
addr_pred() {
  local d b s f
  IFS=':.' read -r d b s f <<<"$1"
  printf "[(@domain='0x%s' or @domain='%d') and (@bus='0x%s' or @bus='%d') and (@slot='0x%s' or @slot='%d') and (@function='0x%x' or @function='%d')]" \
    "$d" "$((16#$d))" "$b" "$((16#$b))" "$s" "$((16#$s))" "$((16#$f))" "$((16#$f))"
}

if [[ $DRY == 1 ]]; then echo "Dry run: nothing is defined."; fi
echo "Checking '$VM_NAME'…"

# 1. GPU hostdevs. managed='no' because winvm-gpu binds vfio-pci itself.
for d in $GPU_PCI; do
  pred=$(addr_pred "$d")
  if has "//devices/hostdev[@type='pci']/source/address$pred"; then
    present "hostdev $d"
    if has "//devices/hostdev[@type='pci' and @managed='yes'][source/address$pred]"; then
      echo "  WARN   hostdev $d is managed='yes'; winvm-gpu expects managed='no'. Fix it with virt-manager or virsh edit." >&2
    fi
  else
    apply "hostdev $d (managed='no')" --add-device --hostdev "$d,xpath1.set=./@managed=no"
  fi
done

# 2. No emulated video card: the GPU is Windows' only display. SPICE graphics stays for input.
if has "//devices/video/model[@type='none']"; then
  present "video model none"
elif [[ $FINAL == 0 ]]; then
  echo "  later  video model none (run with --final once Looking Glass shows the Windows desktop)"
elif ! has "//devices/video"; then
  apply "video model none" --add-device --video model.type=none
elif ! has "//devices/video/model[@type='none']"; then
  apply "video model none (replaces $(xmllint --xpath 'string(//devices/video[1]/model/@type)' "$CUR"))" --edit --video clearxml=yes,model.type=none
fi

# 3. virtio mouse and keyboard.
for t in mouse keyboard; do
  if has "//devices/input[@type='$t' and @bus='virtio']"; then present "virtio $t"
  else apply "virtio $t" --add-device --input "$t,bus=virtio"; fi
done

# 4. Looking Glass shared memory.
if has "//devices/shmem[@name='looking-glass']"; then
  present "shmem looking-glass"
  if ! has "//devices/shmem[@name='looking-glass']/size[(@unit='M' or @unit='MiB') and .='$LG_SHM_MB']"; then
    echo "  WARN   shmem looking-glass exists but its size is not ${LG_SHM_MB}M; left as it is." >&2
  fi
else
  apply "shmem looking-glass (${LG_SHM_MB}M)" --add-device --shmem "name=looking-glass,model.type=ivshmem-plain,size=$LG_SHM_MB,size.unit=M"
fi

# 5. Guest agent channel.
if has "//devices/channel/target[@name='org.qemu.guest_agent.0']"; then present "guest agent channel"
else apply "guest agent channel" --add-device --channel unix,target.type=virtio,target.name=org.qemu.guest_agent.0; fi

# 6. Hide KVM, set the Hyper-V vendor id (first-class option for the first, XPath for the second).
if has "//features/kvm/hidden[@state='on']"; then present "kvm hidden"
else apply "kvm hidden" --edit --features kvm.hidden.state=on; fi
if has "//features/hyperv/vendor_id[@state='on' and @value='KVMKVMKVM']"; then present "hyperv vendor_id"
else apply "hyperv vendor_id KVMKVMKVM" --edit --xml ./features/hyperv/vendor_id/@state=on --xml ./features/hyperv/vendor_id/@value=KVMKVMKVM; fi

# 7. Guest physical address width, for IOMMUs narrower than the CPU.
if [[ -z $IOMMU_LIMIT ]]; then
  echo "  skip   maxphysaddr (IOMMU_LIMIT is empty)"
elif has "//cpu/maxphysaddr[@mode='passthrough' and @limit='$IOMMU_LIMIT']"; then
  present "maxphysaddr limit $IOMMU_LIMIT"
else
  apply "maxphysaddr limit $IOMMU_LIMIT" --edit --xml ./cpu/maxphysaddr/@mode=passthrough --xml "./cpu/maxphysaddr/@limit=$IOMMU_LIMIT"
fi

[[ -z $XML_OUT ]] || cp "$CUR" "$XML_OUT"

echo
if [[ $DRY == 1 ]]; then
  echo "Dry run done: $APPLIED change(s) would be made, $PRESENT already present."
  exit 0
fi
echo "Done: $APPLIED change(s) made, $PRESENT already present."
if [[ $FINAL == 0 ]]; then
cat <<EOF

Next steps (stage 1 done; QXL screen kept):
  1. winvm-gpu on                  (first run prepares Hyprland; log out and back in, then run it again)
                                   Hyprland must honour the flag: merge hyprland-snippet.lua first
  2. virsh -c $URI start $VM_NAME && virt-viewer -c $URI $VM_NAME
  3. In Windows: NVIDIA driver, Looking Glass host, Virtual Display Driver (guest/GUEST-STEPS.md)
  4. Shut Windows down, then: ./enable-gpu.sh --final
EOF
else
cat <<EOF

Next steps:
  1. winvm-gpu on                  (if the GPU is not already reserved; may ask you to log out and back in)
  2. Open "Windows 11 (GPU)" from the app menu, or run: win11-vm start
EOF
fi
