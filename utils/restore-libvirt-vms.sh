#!/usr/bin/env bash
set -euo pipefail

BACKUP_ROOT="${1:-/home/nix/.SiriKali/fw13-backup_5-14-2026}"
VM_ROOT="${2:-/home/nix/Documents/VMs}"
RUNNING_AS_ROOT=0
if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  RUNNING_AS_ROOT=1
fi

if [[ "$RUNNING_AS_ROOT" -eq 1 && "$BACKUP_ROOT" == /home/nix/.SiriKali/* ]]; then
  cat >&2 <<MSG
This backup is under /home/nix/.SiriKali. SiriKali/FUSE mounts are usually
visible to the owning user but not to root. Run this restore script as nix,
without sudo; the script will talk to qemu:///system through your libvirt group.

Use:
  ./utils/restore-libvirt-vms.sh "$BACKUP_ROOT" "$VM_ROOT"
MSG
  exit 1
fi

looks_like_var_libvirt() {
  [[ -d "$1/images" || -d "$1/qemu" || -d "$1/storage" ]]
}

looks_like_etc_libvirt() {
  [[ -d "$1/qemu" || -d "$1/qemu/networks" || -d "$1/nwfilter" || -f "$1/libvirtd.conf" ]]
}

find_libvirt_var() {
  local candidates=(
    "$BACKUP_ROOT/var/lib/libvirt"
    "$BACKUP_ROOT/var/libvirt"
    "$BACKUP_ROOT/lib/libvirt"
    "$BACKUP_ROOT/libvirt"
  )
  local d
  for d in "${candidates[@]}"; do
    if [[ -d "$d" ]] && looks_like_var_libvirt "$d"; then
      printf '%s\n' "$d"
      return 0
    fi
  done

  echo "Missing libvirt state directory. Checked:" >&2
  printf '  %s\n' "${candidates[@]}" >&2
  echo >&2
  echo "Helpful diagnostic:" >&2
  echo "  find '$BACKUP_ROOT' -maxdepth 5 -type d \( -name images -o -name qemu -o -name networks \) -print" >&2
  exit 1
}

find_libvirt_etc() {
  local candidates=(
    "$BACKUP_ROOT/etc/libvirt"
    "$BACKUP_ROOT/etc/lib"
  )
  local d
  for d in "${candidates[@]}"; do
    if [[ -d "$d" ]] && looks_like_etc_libvirt "$d"; then
      printf '%s\n' "$d"
      return 0
    fi
  done

  echo "Missing libvirt config directory. Checked:" >&2
  printf '  %s\n' "${candidates[@]}" >&2
  echo >&2
  echo "Helpful diagnostic:" >&2
  echo "  find '$BACKUP_ROOT' -maxdepth 5 -type d \( -name libvirt -o -name networks -o -name qemu \) -print" >&2
  exit 1
}

LIBVIRT_VAR="${LIBVIRT_VAR_OVERRIDE:-$(find_libvirt_var)}"
LIBVIRT_ETC="${LIBVIRT_ETC_OVERRIDE:-$(find_libvirt_etc)}"

echo "Using libvirt state directory:  $LIBVIRT_VAR"
echo "Using libvirt config directory: $LIBVIRT_ETC"

if ! virsh -c qemu:///system uri >/dev/null 2>&1; then
  cat >&2 <<MSG
Cannot access qemu:///system as $(id -un).

Do not use sudo while reading from the SiriKali backup. Instead, make sure your
current login session has the libvirt groups from the NixOS config:

  id

You should see libvirtd and kvm. If not, log out and back in, or reboot.
MSG
  exit 1
fi

find_qemu_emulator() {
  local candidates=(
    /run/libvirt/nix-emulators/qemu-system-x86_64
    /run/libvirt/nix-emulators/qemu-kvm
    /run/current-system/sw/bin/qemu-system-x86_64
  )
  local p

  for p in "${candidates[@]}"; do
    if [[ -x "$p" ]]; then
      printf '%s\n' "$p"
      return 0
    fi
  done

  if command -v qemu-system-x86_64 >/dev/null 2>&1; then
    command -v qemu-system-x86_64
    return 0
  fi

  cat >&2 <<MSG
Could not find a usable qemu-system-x86_64 binary for restored libvirt XML.
Checked:
  ${candidates[*]}

Diagnostic:
  ls -l /run/libvirt/nix-emulators /run/current-system/sw/bin/qemu-system-x86_64
MSG
  exit 1
}

QEMU_EMULATOR="${QEMU_EMULATOR_OVERRIDE:-$(find_qemu_emulator)}"
echo "Using QEMU emulator:          $QEMU_EMULATOR"

QEMU_MACHINE_HELP="$("$QEMU_EMULATOR" -machine help 2>/dev/null || true)"

machine_supported() {
  local machine="$1"
  grep -Eq "^${machine}([[:space:]]|$)" <<<"$QEMU_MACHINE_HELP"
}

latest_supported_machine() {
  local prefix="$1"
  awk -v prefix="$prefix" '
    $1 ~ "^" prefix "-[0-9]+[.][0-9]+$" && $0 !~ /deprecated/ { print $1 }
  ' <<<"$QEMU_MACHINE_HELP" | sort -V | tail -n 1
}

Q35_MACHINE="${Q35_MACHINE_OVERRIDE:-$(latest_supported_machine pc-q35)}"
I440FX_MACHINE="${I440FX_MACHINE_OVERRIDE:-$(latest_supported_machine pc-i440fx)}"
Q35_MACHINE="${Q35_MACHINE:-q35}"
I440FX_MACHINE="${I440FX_MACHINE:-pc}"

echo "Using Q35 machine fallback:   $Q35_MACHINE"
echo "Using i440fx machine fallback:$I440FX_MACHINE"

first_existing_path() {
  local p
  for p in "$@"; do
    if [[ -e "$p" ]]; then
      printf '%s\n' "$p"
      return 0
    fi
  done
  return 1
}

find_by_name() {
  local name="$1"
  shift
  local d
  for d in "$@"; do
    [[ -d "$d" ]] || continue
    find -L "$d" -maxdepth 4 -type f -name "$name" -print -quit 2>/dev/null || true
  done | head -n 1
}

find_ovmf_code() {
  first_existing_path \
    /run/libvirt/nix-ovmf/OVMF_CODE.secboot.4m.fd \
    /run/libvirt/nix-ovmf/OVMF_CODE.secboot.fd \
    /run/libvirt/nix-ovmf/OVMF_CODE_4M.secboot.fd \
    /run/libvirt/nix-ovmf/OVMF_CODE_4M.ms.fd \
    /run/libvirt/nix-ovmf/edk2-x86_64-secure-code.fd \
    /run/libvirt/nix-ovmf/OVMF_CODE.4m.fd \
    /run/libvirt/nix-ovmf/OVMF_CODE.fd \
    /run/libvirt/nix-ovmf/OVMF_CODE_4M.fd \
    /run/libvirt/nix-ovmf/edk2-x86_64-code.fd \
    2>/dev/null && return 0

  find_by_name '*secure*code*.fd' /run/libvirt/nix-ovmf /run/current-system/sw/share || true
}

find_ovmf_vars() {
  first_existing_path \
    /run/libvirt/nix-ovmf/OVMF_VARS.4m.fd \
    /run/libvirt/nix-ovmf/OVMF_VARS.fd \
    /run/libvirt/nix-ovmf/OVMF_VARS_4M.fd \
    /run/libvirt/nix-ovmf/edk2-x86_64-vars.fd \
    /run/libvirt/nix-ovmf/edk2-i386-vars.fd \
    2>/dev/null && return 0

  find_by_name '*vars*.fd' /run/libvirt/nix-ovmf /run/current-system/sw/share || true
}

find_virtio_iso() {
  first_existing_path \
    /run/current-system/sw/share/virtio-win/virtio-win.iso \
    /run/current-system/sw/share/virtio-win.iso \
    2>/dev/null && return 0

  find_by_name 'virtio-win*.iso' /run/current-system/sw/share /run/current-system/sw || true
}

OVMF_CODE="${OVMF_CODE_OVERRIDE:-$(find_ovmf_code)}"
OVMF_VARS="${OVMF_VARS_OVERRIDE:-$(find_ovmf_vars)}"
VIRTIO_WIN_ISO="${VIRTIO_WIN_ISO_OVERRIDE:-$(find_virtio_iso)}"

if [[ -n "$OVMF_CODE" ]]; then
  echo "Using OVMF code image:        $OVMF_CODE"
else
  echo "Warning: no NixOS OVMF code image found; UEFI loader paths will be left unchanged." >&2
fi

if [[ -n "$OVMF_VARS" ]]; then
  echo "Using OVMF vars template:     $OVMF_VARS"
else
  echo "Warning: no NixOS OVMF vars template found; UEFI template paths will be left unchanged." >&2
fi

if [[ -n "$VIRTIO_WIN_ISO" ]]; then
  echo "Using virtio-win ISO:         $VIRTIO_WIN_ISO"
fi

declare -a restore_dirs=(
  "$VM_ROOT"
  "$VM_ROOT/images"
  "$VM_ROOT/networks"
  "$VM_ROOT/nvram"
  "$VM_ROOT/swtpm"
  "$VM_ROOT/xml"
  "$VM_ROOT/xml/original"
  "$VM_ROOT/xml/rewritten"
)

if [[ "$RUNNING_AS_ROOT" -eq 1 ]]; then
  install -d -m 0750 -o nix -g users "${restore_dirs[@]}"
else
  install -d -m 0750 "${restore_dirs[@]}"
fi

declare -a rsync_archive_opts=(-aH)
if [[ "$RUNNING_AS_ROOT" -eq 1 ]]; then
  rsync_archive_opts=(-aHAX)
fi

if [[ -d "$LIBVIRT_VAR/images" ]]; then
  rsync "${rsync_archive_opts[@]}" --info=progress2 "$LIBVIRT_VAR/images/" "$VM_ROOT/images/"
fi

if [[ -d "$LIBVIRT_VAR/qemu/nvram" ]]; then
  rsync "${rsync_archive_opts[@]}" --info=progress2 "$LIBVIRT_VAR/qemu/nvram/" "$VM_ROOT/nvram/"
fi

if [[ -d "$LIBVIRT_VAR/swtpm" ]]; then
  rsync "${rsync_archive_opts[@]}" --info=progress2 "$LIBVIRT_VAR/swtpm/" "$VM_ROOT/swtpm/"
fi

if [[ -d "$LIBVIRT_ETC/qemu" ]]; then
  find "$LIBVIRT_ETC/qemu" -maxdepth 1 -type f -name '*.xml' -print0 |
    while IFS= read -r -d '' xml; do
      cp -a "$xml" "$VM_ROOT/xml/original/"
    done
fi

if [[ -d "$LIBVIRT_ETC/qemu/networks" ]]; then
  rsync "${rsync_archive_opts[@]}" "$LIBVIRT_ETC/qemu/networks/" "$VM_ROOT/networks/"
fi

escape_sed_replacement() {
  printf '%s' "$1" | sed -e 's/[\/&]/\\&/g'
}

rewrite_unsupported_machines() {
  local out="$1"
  local machine replacement machine_escaped replacement_escaped

  while IFS= read -r machine; do
    [[ -n "$machine" ]] || continue
    if machine_supported "$machine"; then
      continue
    fi

    replacement=""
    case "$machine" in
      pc-q35-*) replacement="$Q35_MACHINE" ;;
      pc-i440fx-*) replacement="$I440FX_MACHINE" ;;
      *)
        echo "Warning: $out uses unsupported machine '$machine'; no automatic fallback known." >&2
        continue
        ;;
    esac

    echo "Rewriting unsupported machine '$machine' -> '$replacement' in $(basename "$out")"
    machine_escaped="$(escape_sed_replacement "$machine")"
    replacement_escaped="$(escape_sed_replacement "$replacement")"
    sed -i \
      -e "s#machine='${machine_escaped}'#machine='${replacement_escaped}'#g" \
      -e "s#machine=\"${machine_escaped}\"#machine=\"${replacement_escaped}\"#g" \
      "$out"
  done < <(
    grep -oE "machine=['\"][^'\"]+['\"]" "$out" |
      sed -E "s/machine=['\"]([^'\"]+)['\"]/\1/" |
      sort -u
  )
}

rewrite_ovmf_paths() {
  local out="$1"
  local code_escaped vars_escaped

  if [[ -n "$OVMF_CODE" ]]; then
    code_escaped="$(escape_sed_replacement "$OVMF_CODE")"
    sed -i -E \
      "s#(<loader[^>]*>)[^<]*(OVMF_CODE|edk2-[^<]*code)[^<]*(</loader>)#\1${code_escaped}\3#g" \
      "$out"
  fi

  if [[ -n "$OVMF_VARS" ]]; then
    vars_escaped="$(escape_sed_replacement "$OVMF_VARS")"
    sed -i -E \
      -e "s#template='[^']*(OVMF_VARS|edk2-[^']*vars)[^']*'#template='${vars_escaped}'#g" \
      -e "s#template=\"[^\"]*(OVMF_VARS|edk2-[^\"]*vars)[^\"]*\"#template=\"${vars_escaped}\"#g" \
      "$out"
  fi
}

rewrite_virtio_iso_paths() {
  local out="$1"
  local iso_escaped

  [[ -n "$VIRTIO_WIN_ISO" ]] || return 0
  iso_escaped="$(escape_sed_replacement "$VIRTIO_WIN_ISO")"
  sed -i -E \
    -e "s#source file='[^']*virtio-win[^']*[.]iso'#source file='${iso_escaped}'#g" \
    -e "s#source file=\"[^\"]*virtio-win[^\"]*[.]iso\"#source file=\"${iso_escaped}\"#g" \
    "$out"
}

warn_missing_sources() {
  local out="$1"
  local src

  while IFS= read -r src; do
    [[ -n "$src" ]] || continue
    [[ "$src" == /dev/* ]] && continue
    [[ -e "$src" ]] && continue
    echo "Warning: $(basename "$out") references missing source: $src" >&2
  done < <(
    grep -oE "source file=['\"][^'\"]+['\"]" "$out" |
      sed -E "s/source file=['\"]([^'\"]+)['\"]/\1/" |
      sort -u
  )
}

vm_root_escaped="$(escape_sed_replacement "$VM_ROOT")"
backup_var_escaped="$(escape_sed_replacement "$LIBVIRT_VAR")"
qemu_emulator_escaped="$(escape_sed_replacement "$QEMU_EMULATOR")"

for xml in "$VM_ROOT/xml/original"/*.xml; do
  [[ -e "$xml" ]] || continue
  out="$VM_ROOT/xml/rewritten/$(basename "$xml")"

  sed \
    -e "s#/var/lib/libvirt/images#${vm_root_escaped}/images#g" \
    -e "s#/var/libvirt/images#${vm_root_escaped}/images#g" \
    -e "s#${backup_var_escaped}/images#${vm_root_escaped}/images#g" \
    -e "s#/var/lib/libvirt/qemu/nvram#${vm_root_escaped}/nvram#g" \
    -e "s#/var/libvirt/qemu/nvram#${vm_root_escaped}/nvram#g" \
    -e "s#${backup_var_escaped}/qemu/nvram#${vm_root_escaped}/nvram#g" \
    -e "s#<emulator>[^<]*qemu-system-x86_64</emulator>#<emulator>${qemu_emulator_escaped}</emulator>#g" \
    -e "s#<emulator>[^<]*qemu-kvm</emulator>#<emulator>${qemu_emulator_escaped}</emulator>#g" \
    "$xml" > "$out"

  rewrite_unsupported_machines "$out"
  rewrite_ovmf_paths "$out"
  rewrite_virtio_iso_paths "$out"
  warn_missing_sources "$out"
done

if command -v setfacl >/dev/null 2>&1 && id qemu-libvirtd >/dev/null 2>&1; then
  setfacl -m u:qemu-libvirtd:--x /home/nix || true
  setfacl -m u:qemu-libvirtd:--x /home/nix/Documents || true
  setfacl -m u:qemu-libvirtd:r-x "$VM_ROOT" || true
  setfacl -R -m u:qemu-libvirtd:rwX "$VM_ROOT" || true
  setfacl -R -d -m u:qemu-libvirtd:rwX "$VM_ROOT" || true
fi

if [[ -d "$VM_ROOT/swtpm" ]] && find "$VM_ROOT/swtpm" -mindepth 1 -print -quit 2>/dev/null | grep -q .; then
  cat <<MSG
Copied swtpm state into:
  $VM_ROOT/swtpm

For Windows 11 TPM continuity, the script will also copy that state into
libvirt's system state directory. sudo may prompt.
MSG
  if command -v sudo >/dev/null 2>&1; then
    sudo install -d -m 0750 /var/lib/libvirt/swtpm
    sudo rsync -aH "$VM_ROOT/swtpm/" /var/lib/libvirt/swtpm/
    if id qemu-libvirtd >/dev/null 2>&1; then
      sudo chown -R qemu-libvirtd:qemu-libvirtd /var/lib/libvirt/swtpm || true
    fi
  else
    cat >&2 <<MSG
Warning: sudo is unavailable, so swtpm state was not copied to /var/lib/libvirt/swtpm.
Copy it manually before relying on the Windows 11 VM's TPM state.
MSG
  fi
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

declare -a define_failures=()
for xml in "$VM_ROOT/xml/rewritten"/*.xml; do
  [[ -e "$xml" ]] || continue
  if ! virsh -c qemu:///system define "$xml"; then
    define_failures+=("$xml")
  fi
done

if [[ "${#define_failures[@]}" -gt 0 ]]; then
  echo >&2
  echo "Failed to define ${#define_failures[@]} VM XML file(s):" >&2
  printf '  %s\n' "${define_failures[@]}" >&2
  echo >&2
  echo "Inspect the rewritten XML and libvirt logs:" >&2
  echo "  grep -R \"<type \\|<loader\\|<nvram\\|<emulator\\|<source file\" '$VM_ROOT/xml/rewritten'" >&2
  echo "  journalctl -u libvirtd -b --no-pager | tail -n 120" >&2
  exit 1
fi

cat <<MSG
Restore complete.

VM payload location:
  $VM_ROOT

Check restored guests with:
  virsh -c qemu:///system list --all

Open virt-manager and use the system connection:
  qemu:///system
MSG
