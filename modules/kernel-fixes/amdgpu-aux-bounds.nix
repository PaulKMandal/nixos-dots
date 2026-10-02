# Temporary test backport for the panic documented in README.md.
{ config, ... }:

{
  # Fail visibly after a kernel update rather than silently carrying an
  # unreviewed backport forward or pinning an old kernel indefinitely.
  assertions = [
    {
      assertion = config.boot.kernelPackages.kernel.version == "6.12.90";
      message = ''
        The local AMDGPU AUX reply-bounds backport was prepared for Linux 6.12.90.
        The selected kernel changed. Review whether it includes the upstream fix,
        then remove or rebase modules/kernel-fixes/amdgpu-aux-bounds.nix.
        Do not keep an old kernel solely to satisfy this assertion.
      '';
    }
  ];

  boot.kernelPatches = [
    {
      name = "amdgpu-dmub-aux-reply-bounds";
      patch = ./amdgpu-dmub-aux-reply-bounds.patch;
    }
  ];
}
