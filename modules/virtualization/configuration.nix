{ pkgs, ... }:

{
  programs.dconf.enable = true;
  programs.virt-manager.enable = true;
  virtualisation.spiceUSBRedirection.enable = true;

  virtualisation.libvirtd = {
    enable = true;

    # Do not resurrect guests merely because they were running when the host
    # last shut down. Guests remain available for an explicit manual start.
    onBoot = "ignore";

    qemu = {
      package = pkgs.qemu_kvm;
      swtpm.enable = true;
    };
  };

  virtualisation.docker = {
    enable = true;
  };

  # Ensure the render group exists and grant host GPU render-node access to
  # your user and libvirt's QEMU worker for SPICE GL / VirGL.
  users.groups.render = {};

  users.users.nix.extraGroups = [
    "libvirtd"
    "kvm"
    "docker"
    "render"
    "video"
  ];

  users.users.qemu-libvirtd.extraGroups = [
    "render"
    "video"
  ];

  environment.systemPackages = with pkgs; [
    docker-compose
    acl
    libosinfo
    libepoxy
    libglvnd
    libvirt
    libxml2
    mesa-demos
    osinfo-db
    pciutils
    qemu_kvm
    rsync
    spice
    spice-gtk
    spice-protocol
    swtpm
    virglrenderer
    virt-viewer
    vulkan-tools
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
