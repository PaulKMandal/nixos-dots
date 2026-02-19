{ config, pkgs, ... }:

{
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

  # If you use Tailscale/WireGuard/etc and only want those interfaces, you can tighten later.
}

