# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      ./modules/zed/configuration.nix
    ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Make sure nouveau never binds the card
  boot.blacklistedKernelModules = [ "nouveau" ];
  boot.kernelParams = [
    "modprobe.blacklist=nouveau"
    "nouveau.modeset=0"
  ];

  networking.hostName = "nixos"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;

  # Set your time zone.
  time.timeZone = "America/Chicago";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.nix = {
    isNormalUser = true;
    description = "Nix";
    extraGroups = [ "networkmanager" "wheel" "audio" "video" "input"];
    packages = with pkgs; [];
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  nix.settings.experimental-features = ["nix-command" "flakes"];

  xdg.portal = {
     enable = true;
     wlr.enable = true;
     extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  };

  services.pipewire = {
     enable = true;
     pulse.enable = true;
     alsa.enable = true;
     jack.enable = false;
  };
  security.rtkit.enable = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
     home-manager
     git
     neovim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
     wget
     sway
     rofi
     firefox
     kitty
     waybar
     wofi
     mako
     grim slurp
     wl-clipboard
     polkit_gnome
     pavucontrol
     networkmanagerapplet
     python3
     protonmail-bridge
     protonmail-bridge-gui
     thunderbird
     keepassxc
     xfce.thunar
     veracrypt
     libreoffice
     pciutils
     ripgrep
     waterfox
     xdg-utils
     zed-editor
     signal-desktop
     
     sirikali
     #SiriKali filesystem backends
     cryfs
     securefs
     encfs
     sshfs
     fscrypt-experimental
     fscryptctl
  ];

  #needed for fuse mounts (SiriKali)
  programs.fuse.userAllowOther = true;

  environment.variables.EDITOR = "neovim";

  #Enable fish
  programs.fish.enable = false;
  
  #Enable zsh
  programs.zsh.enable = true;

  # ensures /etc/shells contains fish
  environment.shells = with pkgs; [ zsh ];

  # set for your user (replace nix with your username if different)
  users.users.nix.shell = pkgs.zsh;

  #-----Thunar stuff-----
  programs.thunar.enable = true;

  # If you're not running full XFCE, you usually want this so settings persist:
  programs.xfconf.enable = true;

  # Mount/trash/network integration + thumbnails:
  services.gvfs.enable = true;
  services.tumbler.enable = true;

  # For mounting removable media (often needed with Thunar + gvfs):
  services.udisks2.enable = true;

  # Authorization prompts (mounting, etc.):
  security.polkit.enable = true;
  #----------------------


  # Use NVIDIA proprietary driver
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    modesetting.enable = true;  # needed for modern Wayland/DRM path
    open = false;               # start with proprietary kernel module
  };

  hardware.graphics = {
    enable = true;
    enable32Bit=true;
  };

  fonts = {
     enableDefaultPackages = true;
     fontconfig.defaultFonts = {
       sansSerif = [ "Noto Sans" ];
       serif     = [ "Noto Serif" ];
       monospace = [ "JetBrainsMono Nerd Font" ];
     };
   };

fonts.packages = with pkgs; [
  noto-fonts
  noto-fonts-color-emoji
  nerd-fonts."jetbrains-mono"
];

  #Enable keyring
  services.gnome.gnome-keyring.enable = true;

  security.pam.services.login.enableGnomeKeyring = true;
  #SysRq for debugging/dumping tasks
  boot.kernel.sysctl."kernel.sysrq" = 1;

  #Config for logs
  services.journald.extraConfig = ''
  Storage=persistent
  SystemMaxUse=1G
  '';

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.11"; # Did you read the comment?

}
