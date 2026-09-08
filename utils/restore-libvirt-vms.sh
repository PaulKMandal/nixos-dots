#!/usr/bin/env bash
set -euo pipefail

BACKUP_ROOT="${1:-/home/nix/.SiriKali/fw13-backup_5-14-2026}"
VM_ROOT="${2:-/home/nix/Documents/VMs}"
LIBVIRT_VAR="$BACKUP_ROOT/var/lib/libvirt"
LIBVIRT_ETC="$BACKUP_ROOT/etc/libvirt"

require_dir() {
  if [[ ! -d "$1" ]]; then
    echo "Missing directory: $1" >&2
    exit 1
  fi
}

require_dir "$LIBVIRT_VAR"
require_dir "$LIBVIRT_ETC"

install -d -m 0750 -o nix -g users "$VM_ROOT" \
  "$VM_ROOT/images" \
  "$VM_ROOT/networks" \
  "$VM_ROOT/nvram" \
  "$VM_ROOT/xml" \
  "$VM_ROOT/xml/original" \
  "$VM_ROOT/xml/rewritten"

if [[ -d "$LIBVIRT_VAR/images" ]]; then
  rsync -aHAX --info=progress2 "$LIBVIRT_VAR/images/" "$VM_ROOT/images/"
fi

if [[ -d "$LIBVIRT_VAR/qemu/nvram" ]]; then
  rsync -aHAX --info=progress2 "$LIBVIRT_VAR/qemu/nvram/" "$VM_ROOT/nvram/"
fi

if [[ -d "$LIBVIRT_ETC/qemu" ]]; then
  find "$LIBVIRT_ETC/qemu" -maxdepth 1 -type f -name '*.xml' -print0 |
    while IFS= read -r -d '' xml; do
      cp -a "$xml" "$VM_ROOT/xml/original/"
    done
fi

if [[ -d "$LIBVIRT_ETC/qemu/networks" ]]; then
  rsync -aHAX "$LIBVIRT_ETC/qemu/networks/" "$VM_ROOT/networks/"
fi

escape_sed_replacement() {
  printf '%s' "$1" | sed -e 's/[\/&]/\\&/g'
}

vm_root_escaped="$(escape_sed_replacement "$VM_ROOT")"
backup_var_escaped="$(escape_sed_replacement "$LIBVIRT_VAR")"

for xml in "$VM_ROOT/xml/original"/*.xml; do
  [[ -e "$xml" ]] || continue
  out="$VM_ROOT/xml/rewritten/$(basename "$xml")"

  sed \
    -e "s#/var/lib/libvirt/images#${vm_root_escaped}/images#g" \
    -e "s#${backup_var_escaped}/images#${vm_root_escaped}/images#g" \
    -e "s#/var/lib/libvirt/qemu/nvram#${vm_root_escaped}/nvram#g" \
    -e "s#${backup_var_escaped}/qemu/nvram#${vm_root_escaped}/nvram#g" \
    "$xml" > "$out"
done

if command -v setfacl >/dev/null 2>&1 && id qemu-libvirtd >/dev/null 2>&1; then
  setfacl -m u:qemu-libvirtd:--x /home/nix || true
  setfacl -m u:qemu-libvirtd:--x /home/nix/Documents || true
  setfacl -m u:qemu-libvirtd:r-x "$VM_ROOT" || true
  setfacl -R -m u:qemu-libvirtd:rwX "$VM_ROOT" || true
  setfacl -R -d -m u:qemu-libvirtd:rwX "$VM_ROOT" || true
fi

if ! virsh -c qemu:///system pool-info home-vms >/dev/null 2>&1; then
  virsh -c qemu:///system pool-define-as home-vms dir --target "$VM_ROOT/images"
fi
virsh -c qemu:///system pool-autostart home-vms >/dev/null
virsh -c qemu:///system pool-start home-vms >/dev/null 2>&1 || true

if [[ -d "$VM_ROOT/networks" ]]; then
  find "$VM_ROOT/networks" -maxdepth 1 -type f -name '*.xml' -print0 |
    while IFS= read -r -d '' netxml; do
      name="$(sed -n 's:.*<name>\(.*\)</name>.*:\1:p' "$netxml" | head -n1)"
      [[ -n "$name" ]] || { echo "Skipping network with no name: $netxml" >&2; continue; }

      if ! virsh -c qemu:///system net-info "$name" >/dev/null 2>&1; then
        virsh -c qemu:///system net-define "$netxml"
      fi
      virsh -c qemu:///system net-autostart "$name" >/dev/null || true
      virsh -c qemu:///system net-start "$name" >/dev/null 2>&1 || true
    done
fi

for xml in "$VM_ROOT/xml/rewritten"/*.xml; do
  [[ -e "$xml" ]] || continue
  virsh -c qemu:///system define "$xml"
done

cat <<MSG
Restore complete.

VM payload location:
  $VM_ROOT

Check restored guests with:
  virsh -c qemu:///system list --all

Open virt-manager and use the system connection:
  qemu:///system
MSG
