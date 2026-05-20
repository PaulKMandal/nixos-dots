{ lib, ... }:

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
  #   sudo wg-quick up proton_ca924
  # while keeping the decrypted secret files under /run/secrets.
  system.activationScripts.linkWireGuardConfigs.text = lib.optionalString hasWireguardSecrets ''
    install -d -m 0700 -o root -g root /etc/wireguard

    link_wg_conf() {
      local name="$1"
      local target="/run/secrets/wireguard/$name.conf"
      local link="/etc/wireguard/$name.conf"

      if [ -e "$link" ] && [ ! -L "$link" ]; then
        echo "Refusing to replace non-symlink $link" >&2
        echo "Move it out of the way or import it into secrets/wireguard.yaml first." >&2
        exit 1
      fi

      ln -sfn "$target" "$link"
    }

    link_wg_conf proton_ca924
    link_wg_conf proton_ca924_filter
    link_wg_conf gpu_server
  '';

  # Later, this module is also where wg-quick, NetworkManager, or systemd
  # integration should go.
}
