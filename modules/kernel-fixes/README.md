# AMDGPU DisplayPort AUX reply-bounds test backport

## Why this patch exists

The supplied pstore archive contains seven identifiable Linux 6.12.90 panics
with `Kernel stack is corrupted in: drm_dp_dpcd_probe+0xe7/0xf0`, reached
from `amdgpu_dm_hpd_wq` / `dm_handle_hpd_work`. Identifiable events span June 23
through September 23, 2026. This establishes the crash path, not the exact
reply length or the hardware/firmware event that initiated it.

The 6.12.90 DRM helper uses a one-byte stack buffer for its probe. The AMD
DMUB transfer function copies the firmware-reported reply length without
clamping it to the requested buffer. This is a strong candidate for the
overwrite. Linux v7.3-rc4 contains receive-length bounding in the corresponding
function. This local patch adapts that code to 6.12.90; it is NOT an official
stable backport and is NOT yet verified to cure this laptop's crashes.

## Scope

Only the AUX reply copy and its returned length change. The source-buffer
bound, destination-buffer bound, NULL-data check, and write-status-update
exception are retained from the cited upstream implementation. Sleep,
charging, TLP, USB autosuspend, GPU acceleration, BIOS and the flake lock
are not changed. Kernel stack protection remains enabled.

The exact-version assertion stops evaluation if the selected kernel changes;
review/remove/rebase this temporary backport then. It does not select or
pin a kernel version. Do not downgrade a newer kernel to satisfy it.

## Installation from the downloaded outer patch

From the repository root (normally ~/nixos-dots):

```sh
git apply --check ~/Downloads/0004-framework-amdgpu-aux-bounds.patch &&
git apply ~/Downloads/0004-framework-amdgpu-aux-bounds.patch &&
git add -N modules/kernel-fixes &&
nixos-rebuild build --flake .#nixos
```

This changes the kernel derivation. Expect a source build rather than a
normal cached-kernel substitution; use AC power and sufficient free disk
space. The first command builds only; it does not activate or restart the
system. Do not update flake inputs at the same time.

After a successful build, keep a record of the resulting kernel path:

```sh
readlink -f ./result/kernel
```

Save work before the eventual reboot. Install for the next boot without
switching the running session:

```sh
sudo nixos-rebuild boot --flake .#nixos
```

Reboot manually when ready. The kernel still reports `6.12.90`; `uname -r`
alone cannot prove the patch is active. After reboot:

```sh
uname -r
readlink -f /run/booted-system/kernel
```

Compare that path to the one recorded after the build. Do not garbage-collect
the previous generation during testing. A successful build/boot is not yet
proof the intermittent KVM crash is fixed.

## Rollback

At the systemd-boot menu, select the previous NixOS generation to boot the
old kernel. A running kernel cannot be replaced by `nixos-rebuild switch`.
Remove this change from the repository with:

```sh
git apply -R --check ~/Downloads/0004-framework-amdgpu-aux-bounds.patch &&
git apply -R ~/Downloads/0004-framework-amdgpu-aux-bounds.patch
```

If files were edited after application, review the differences instead of
forcing a reverse patch. Build/install the chosen configuration for the next
boot and reboot to run its kernel. Keep the crash records for comparison.

## Validation limitations

The outer patch was tested against the exact supplied nixconfig(5).tar and
with both follow-up power patches applied. The kernel hunk was checked
against the relevant 6.12.90 function transcribed from the upstream source
view, NOT a downloaded full kernel source tree. A userspace C test exercises
the exact changed copy block with simulated reply lengths and guard bytes;
this does NOT exercise firmware, interrupts, locking or the real kernel.
Nix evaluation, a full kernel build and hardware testing were unavailable.
See the accompanying validation report for the actual test results.

## Upstream sources inspected on 2026-09-27

* Old receive code:
  https://raw.githubusercontent.com/gregkh/linux/v6.12.90/drivers/gpu/drm/amd/display/amdgpu_dm/amdgpu_dm.c
* One-byte probe:
  https://raw.githubusercontent.com/gregkh/linux/v6.12.90/drivers/gpu/drm/display/drm_dp_helper.c
* Bounded receive code adapted here:
  https://raw.githubusercontent.com/torvalds/linux/v7.3-rc4/drivers/gpu/drm/amd/display/amdgpu_dm/amdgpu_dm_dmub.c
* Existing write-status-update behavior:
  https://raw.githubusercontent.com/gregkh/linux/v6.12.90/drivers/gpu/drm/amd/display/dc/dce/dce_aux.c

The backported code is from AMD's MIT-licensed display driver.

Copyright 2026 Advanced Micro Devices, Inc.

Permission is hereby granted, free of charge, to any person obtaining a
copy of this software and associated documentation files (the "Software"),
to deal in the Software without restriction, including without limitation
the rights to use, copy, modify, merge, publish, distribute, sublicense,
and/or sell copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
THE COPYRIGHT HOLDER(S) OR AUTHOR(S) BE LIABLE FOR ANY CLAIM, DAMAGES OR
OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.
