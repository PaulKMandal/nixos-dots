{ config, lib, pkgs, ... }:

{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.initrd.luks.devices."cryptroot" = {
    device = "/dev/disk/by-uuid/5c585574-fc70-4fb0-ba48-05587aa9ee95";
    preLVM = true;
  };

  services.lvm.enable = true;

  fileSystems."/" = lib.mkForce {
    device = "/dev/disk/by-uuid/b0442db2-1d3a-4cb5-82d0-166bb5852fa5";
    fsType = "ext4";
  };

  fileSystems."/boot" = lib.mkForce {
    device = "/dev/disk/by-uuid/0BC6-8FC5";
    fsType = "vfat";
    options = [ "fmask=0077" "dmask=0077" ];
  };

  fileSystems."/home" = lib.mkForce {
    device = "/dev/disk/by-uuid/4a9603cf-a69f-455f-a684-600293bb59e3";
    fsType = "btrfs";
    options = [ "subvol=@home" "compress=zstd" "noatime" ];
  };

  fileSystems."/home/.snapshots" = lib.mkForce {
    device = "/dev/disk/by-uuid/4a9603cf-a69f-455f-a684-600293bb59e3";
    fsType = "btrfs";
    options = [ "subvol=@home-snapshots" "compress=zstd" "noatime" ];
  };

  swapDevices = lib.mkForce [
    { device = "/dev/disk/by-label/nixos-swap"; }
  ];

  services.fstrim.enable = true;
}
