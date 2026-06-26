# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:

let
  wrapChromiumBrowser = name: package: binary:
    pkgs.symlinkJoin {
      inherit name;
      paths = [ package ];
      buildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        wrapProgram $out/bin/${binary} \
          --add-flags "--proxy-server=direct://" \
          --add-flags "--proxy-bypass-list=*" \
          --add-flags "--disable-quic"
      '';
    };

  chromiumDirect = wrapChromiumBrowser "chromium-direct" pkgs.chromium "chromium";
  braveDirect = wrapChromiumBrowser "brave-direct" pkgs.brave "brave";
in
{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      ./storage.nix
      ./modules/secrets.nix
      ./modules/wireguard.nix
      ./modules/tor/configuration.nix
      ./modules/virtualization/configuration.nix
      ./modules/zed/configuration.nix
      #./modules/syncthing/configuration.nix #Currently borked
      ./options.nix
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

  # Proton VPN / WireGuard policy routing can fail with strict reverse-path filtering.
  networking.firewall.checkReversePath = "loose";

  # CUPS / printer support. This enables local printing, common open printer
  # drivers, driverless network discovery, IPP-over-USB, and the GTK printer UI.
  services.printing = {
    enable = true;
    drivers = with pkgs; [
      cups-filters
      gutenprint
      hplip
      brlaser
    ];
  };

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };

  services.ipp-usb.enable = true;
  programs.system-config-printer.enable = true;

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
    extraGroups = [ "networkmanager" "wheel" "audio" "video" "input" "adbusers" ];
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
  
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;
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
     #firefox
     kitty
     waybar
     wofi
     mako
     grim slurp
     wl-clipboard
     polkit_gnome
     pavucontrol
     mpv

     # GrapheneOS / Android flashing and troubleshooting.
     # android-tools provides adb and fastboot for the CLI installer.
     android-tools
     # The WebUSB installer needs a Chromium-based browser; Firefox/LibreWolf do not work for it.
     chromiumDirect
     braveDirect
     curl
     libarchive # bsdtar, used by the GrapheneOS CLI install guide on Linux
     openssh    # ssh-keygen -Y verify for factory image signatures
     unzip
     usbutils   # lsusb for USB/fastboot troubleshooting

     networkmanagerapplet
     protonvpn-gui
     wireguard-tools
     python3
     protonmail-bridge
     protonmail-bridge-gui
     thunderbird
     keepassxc
     libsecret # secret-tool; useful for Secret Service/keyring debugging
     glib      # gsettings; useful for Chromium/GNOME proxy debugging
     seahorse  # GUI keyring manager
     xfce.thunar
     veracrypt
     libreoffice
     pciutils
     ripgrep
     #waterfox #Not working
     librewolf
     xdg-utils
     zed-editor
     signal-desktop
     gnome-disk-utility
     gparted
     cryptsetup
     lvm2
     tree

     sirikali
     #SiriKali filesystem backends
     cryfs
     securefs
     encfs
     sshfs
     fscrypt-experimental
     fscryptctl

     #Needed for yubikey use (ykchalresp) with 3rd party apps.
     yubikey-personalization
     ykfde-open
     yubioath-flutter      # Yubico Authenticator GUI
     yubikey-manager       # ykman CLI
     yubico-piv-tool       # PIV/smartcard tooling

     gnupg
     pcsc-tools

     kdePackages.kdenlive

  ];

  # Enables Android udev integration for adb/fastboot non-root access.
  # The nix user is in adbusers above.
  programs.adb.enable = true;

  # Thunderbolt / USB4 dock authorization.
  services.hardware.bolt.enable = true;

  #Needed for non-root use of yubikey tools (e.g. ykchalresp)
  services.udev.packages = with pkgs; [
    yubikey-personalization
    libfido2
  ];

  #needed for PIV/GPG use with yubikey
  services.pcscd.enable = true;

  #needed for fuse mounts (SiriKali)
  programs.fuse.userAllowOther = true;

  environment.variables.EDITOR = "nvim";

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
  #services.xserver.videoDrivers = [ "nvidia" ];

  #hardware.nvidia = {
  #  modesetting.enable = true;  # needed for modern Wayland/DRM path
  #  open = false;               # start with proprietary kernel module
  #};

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

  # Power management. Keep the laptop awake when the lid is closed on AC power.
  # Closing the lid on battery still uses the default logind behavior.
  services.logind.lidSwitchExternalPower = "ignore";

  # Secret Service/keyring support for Chromium-family browsers.
  # PAM should unlock the login keyring at login so Chromium/Brave do not hang
  # or prompt later when they try to use org.freedesktop.secrets.
  services.gnome.gnome-keyring.enable = true;
  programs.seahorse.enable = true;

  security.pam.services.login.enableGnomeKeyring = true;
  #SysRq for debugging/dumping tasks
  boot.kernel.sysctl."kernel.sysrq" = 1;

  #Config for logs
  services.journald.extraConfig = ''
  Storage=persistent
  SystemMaxUse=1G
  '';

  #Syncthing service
  services.syncthing = {
    enable = true;

    # Run it as your user so it can read/write your home dirs
    user = "nix";
    group = "users";

    # Where Syncthing stores its config/index
    dataDir = "/home/nix/.config/syncthing";
    configDir = "/home/nix/.config/syncthing";

    # Optional: pin GUI to LAN only (recommended)
    guiAddress = "127.0.0.1:8384";

    # Optional: pre-declare folders/devices in Nix (you can also do it in the web UI)
    # settings = { };
  };

  # Networking: open ports on the firewall
  networking.firewall.allowedTCPPorts = [
    8384  # Web UI (only needed if guiAddress is not localhost, or if you want LAN access)
    22000 # Sync
  ];
  networking.firewall.allowedUDPPorts = [
    22000 # QUIC (optional but useful)
    21027 # Local discovery
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
   programs.gnupg.agent = {
     enable = true;
     enableSSHSupport = true;
     pinentryPackage = pkgs.pinentry-qt;
   };

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
