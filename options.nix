{ lib, ... }:
{
  options.disks.hasDataMount = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Whether this host has the /mnt/Data mount.";
  };
}

