{ config, lib, ... }:

let
  wireguardSecretsFile = ../secrets/wireguard.yaml;
  hasWireguardSecrets = builtins.pathExists wireguardSecretsFile;
in
{
  # WireGuard secrets are managed by SOPS, but declared here because these are
  # WireGuard-specific runtime files.
  #
  # This file is intentionally optional so the first rebuild works before
  # secrets/wireguard.yaml exists.
  sops = lib.optionalAttrs hasWireguardSecrets {
    secrets = {
      "wireguard/proton_ca924_conf" = {
        sopsFile = wireguardSecretsFile;
        path = "/run/secrets/wireguard/proton_ca924.conf";
        owner = "root";
        group = "root";
        mode = "0600";
      };

      "wireguard/proton_ca924_filter_conf" = {
        sopsFile = wireguardSecretsFile;
        path = "/run/secrets/wireguard/proton_ca924_filter.conf";
        owner = "root";
        group = "root";
        mode = "0600";
      };

      "wireguard/gpu_server_conf" = {
        sopsFile = wireguardSecretsFile;
        path = "/run/secrets/wireguard/gpu_server.conf";
        owner = "root";
        group = "root";
        mode = "0600";
      };
    };
  };

  # Let wg-quick use normal names like:
  #   sudo wg-quick up gpu_server
  # while keeping the decrypted secret material under /run/secrets.
  #
  # Do this through environment.etc instead of an activation script. NixOS owns
  # /etc during activation, so hand-created /etc/wireguard links can disappear
  # after a rebuild or boot.
  environment.etc = lib.optionalAttrs hasWireguardSecrets {
    "wireguard/proton_ca924.conf".source =
      config.sops.secrets."wireguard/proton_ca924_conf".path;

    "wireguard/proton_ca924_filter.conf".source =
      config.sops.secrets."wireguard/proton_ca924_filter_conf".path;

    "wireguard/gpu_server.conf".source =
      config.sops.secrets."wireguard/gpu_server_conf".path;
  };

  # Later, this module is also where wg-quick, NetworkManager, or systemd
  # integration should go.
}
