{ pkgs, ... }:

{
  # Shared SOPS plumbing.
  #
  # The local age key lets rebuilds work after boot without requiring the
  # YubiKey every time. Back up this key encrypted to your YubiKey-backed
  # GPG key.
  #
  # Local key:
  #   /home/nix/.config/sops/age/keys.txt
  #
  # Encrypted backup:
  #   secrets/bootstrap/sops-age-key.txt.asc.gpg
  sops = {
    age.keyFile = "/home/nix/.config/sops/age/keys.txt";
    defaultSopsFormat = "yaml";
  };

  environment.systemPackages = with pkgs; [
    age
    sops
  ];

  # Directory for the local age identity used by sops-nix.
  # This is user-owned so normal `sops secrets/*.yaml` works without sudo.
  system.activationScripts.ensureSopsAgeDir.text = ''
    install -d -m 0700 -o nix -g users /home/nix/.config/sops/age
  '';
}
