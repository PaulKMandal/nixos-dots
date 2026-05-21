{ pkgs, ... }:

{
  programs.dconf.enable = true;
  programs.virt-manager.enable = true;

  virtualisation.libvirtd = {
    enable = true;

    qemu = {
      package = pkgs.qemu_kvm;
      swtpm.enable = true;
    };
  };

  users.users.nix.extraGroups = [
    "libvirtd"
    "kvm"
  ];

  environment.systemPackages = with pkgs; [
    acl
    libosinfo
    libvirt
    libxml2
    osinfo-db
    qemu_kvm
    rsync
    spice
    spice-gtk
    spice-protocol
    swtpm
    virt-viewer
    win-spice
    virtio-win
  ];

  system.activationScripts.ensureHomeVmDirs.text = ''
    install -d -m 0750 -o nix -g users /home/nix/Documents/VMs
    install -d -m 0750 -o nix -g users /home/nix/Documents/VMs/images
    install -d -m 0750 -o nix -g users /home/nix/Documents/VMs/networks
    install -d -m 0750 -o nix -g users /home/nix/Documents/VMs/nvram
    install -d -m 0750 -o nix -g users /home/nix/Documents/VMs/xml
  '';
}
