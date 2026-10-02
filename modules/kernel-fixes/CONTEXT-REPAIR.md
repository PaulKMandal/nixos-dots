# 0005: repair the AUX backport's source context

The original 0004 kernel hunk failed in the real Nix build at the patch phase.
Its previous local application test used a transcribed function excerpt, not
byte-exact kernel source. That test was insufficient. The exact mismatch cannot
be inferred from the rejected-hunk message alone.

This follow-up does not change the proposed C fix or Nix configuration. It adds
`refresh-amdgpu-aux-context.py`, which regenerates the inner patch on the laptop
from the exact cached kernel archive named by the failed build. The immutable
archive is read only. There are no network requests or kernel installations.

## Apply after 0004, then repair and build

Save 0005-framework-amdgpu-source-context-repair.patch in ~/Downloads.
Do not reverse 0004 or apply it a second time.

```bash
cd "$HOME/nixos-dots" &&
git apply --check "$HOME/Downloads/0005-framework-amdgpu-source-context-repair.patch" &&
git apply "$HOME/Downloads/0005-framework-amdgpu-source-context-repair.patch" &&
git add -N modules/kernel-fixes &&
python3 modules/kernel-fixes/refresh-amdgpu-aux-context.py \
  --source-archive /nix/store/ly5vh4w7brdqbyiycdgi05m94h9qnamd-linux-6.12.90.tar.xz \
  --write &&
nix build --no-update-lock-file --out-link result-amdgpu-fixed \
  '.#nixosConfigurations.nixos.config.system.build.toplevel' &&
readlink -e ./result-amdgpu-fixed/kernel
```

Use AC power. The kernel build can require substantial CPU time and disk space.
`git add -N` makes new files visible to the flake; it does not commit them.
No boot configuration is installed by this command. Keep the previous generation.

The helper:

1. Reads only the kernel Makefile and the complete target C file from the archive;
   it does not unpack the whole tree onto the filesystem.
2. Checks VERSION/PATCHLEVEL/SUBLEVEL and an empty EXTRAVERSION for 6.12.90.
3. Checks every C code token in the whole target function against the reviewed
   baseline. Whitespace and comments may differ; executable code may not.
4. Verifies that the existing repository patch adds/removes the same intended
   C code, so a manually changed fix is not silently overwritten.
5. Replaces only the known receive-copy block and generates a unified diff using
   the actual file's bytes, line numbers, and context.
6. Uses Git's strict application and reversal checks on a temporary copy of the
   complete C file and compares the result byte-for-byte. When GNU patch is
   available, it additionally applies the diff with --fuzz=0.
7. Saves the previous patch under ~/.local/state/framework-amdgpu-repair/ before
   atomically replacing modules/kernel-fixes/amdgpu-dmub-aux-reply-bounds.patch.

Without --write it runs the checks without changing the repository patch.
Rerunning it with the same source is safe: an already refreshed patch is unchanged.
It refuses symlink patch destinations, changed code, duplicate target functions,
and unexpected source versions instead of forcing a patch or downgrading Linux.

If the helper reports that the target function differs in CODE, it prints that
function and leaves the patch alone. Save that error output for diagnosis. The
chained build will not run. If the cached archive no longer exists, do not choose
an arbitrary tarball: use the source selected by the same locked configuration.

## Install only after successful build

Record the kernel path printed by the successful command above. The pre-existing
`./result/kernel` link can point to an older build; it is not evidence that a new
build succeeded. This procedure uses a separate `result-amdgpu-fixed` link.

```bash
cd "$HOME/nixos-dots" &&
sudo nixos-rebuild boot --flake .#nixos
```

Only after this command succeeds, save work and reboot manually. Then check:

```bash
uname -r
readlink -e /run/booted-system/kernel
```

The version remains 6.12.90. The booted kernel path must match the path recorded
from `result-amdgpu-fixed/kernel` after the successful build. A successful
build/boot does not yet establish that the intermittent KVM crash is cured.

## Rollback

If needed, select the prior NixOS generation in systemd-boot. Do not garbage-
collect it during testing. To restore the original inner patch, copy back the
exact backup path printed by the helper to:

    modules/kernel-fixes/amdgpu-dmub-aux-reply-bounds.patch

Then, if removing the entire test, reverse 0005 and 0004 with git apply -R after
checking that neither patch would overwrite subsequent edits. The helper does
not alter power settings, firmware, or the running kernel.

## Validation scope

Local tests cover formatting/comment variations, changes to actual code, source
version checks, duplicate/missing functions and archive members, template edits,
strict diff application/reversal, backup, check-only mode, and repeated use.
Tests use synthetic source fixtures built around a transcribed upstream function.
They are NOT a test against a downloaded raw Linux tree or the user's tarball.
The complete-file preflight against the user's real source occurs on the laptop.

No Nix evaluation, full kernel compilation, or hardware testing was performed
in the assistant environment. This remains a candidate driver backport, not a
verified cure. See 0005-framework-amdgpu-source-context-validation.txt.

## Source references

Reviewed baseline (code-token guard only; never the diff context):
https://raw.githubusercontent.com/gregkh/linux/v6.12.90/drivers/gpu/drm/amd/display/amdgpu_dm/amdgpu_dm.c

Receive-copy logic (unchanged from 0004):
https://raw.githubusercontent.com/torvalds/linux/v7.3-rc4/drivers/gpu/drm/amd/display/amdgpu_dm/amdgpu_dm_dmub.c

Nix build result links are produced only after a successful build:
https://nix.dev/manual/nix/2.28/command-ref/new-cli/nix3-build

The AMD-derived code fragments are Copyright 2015, 2026 Advanced Micro Devices,
Inc., licensed under the MIT terms reproduced in the accompanying README.md.
