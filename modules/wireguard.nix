{ lib, ... }:

let
  wireguardSecretsFile = ../secrets/wireguard.yaml;
in
{
  # WireGuard secrets are managed by SOPS, but declared here because these are
  # WireGuard-specific runtime files.
  #
  # This file is intentionally optional so the first rebuild works before
  # secrets/wireguard.yaml exists.
  sops = lib.optionalAttrs (builtins.pathExists wireguardSecretsFile) {
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

  # Later, this module is also where wg-quick, NetworkManager, or systemd
  # integration should go.
}
