{ pkgs, ... }:

{
  services.tor = {
    enable = true;
    client.enable = true;
    controlSocket.enable = true;

    # Provide a configured torsocks setup for CLI apps.
    torsocks = {
      enable = true;
      server = "127.0.0.1:9050";
      fasterServer = "127.0.0.1:9063";
    };

    # client.enable provides the isolated SOCKS proxy on 127.0.0.1:9050.
    # Add a second local SOCKS port so the torsocks-faster wrapper has a
    # matching Tor listener.
    settings.SOCKSPort = [
      {
        addr = "127.0.0.1";
        port = 9063;
      }
    ];
  };

  # Allow the desktop user to use the Tor control socket for tools like nyx.
  users.users.nix.extraGroups = [ "tor" ];

  environment.systemPackages = with pkgs; [
    tor-browser
    nyx
  ];
}
