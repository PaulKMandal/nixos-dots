{ pkgs, ... }:

let
  cacToggle = pkgs.writeShellApplication {
    name = "cac-toggle";
    runtimeInputs = with pkgs; [
      coreutils
      libvirt
      libxml2
      opensc
      systemd
      usbutils
      util-linux
    ];
    text = builtins.readFile ./cac-toggle;
  };

  cacDoctor = pkgs.writeShellApplication {
    name = "cac-doctor";
    runtimeInputs = with pkgs; [
      coreutils
      findutils
      gnugrep
      gnused
      libvirt
      libxml2
      opensc
      p11-kit
      systemd
      usbutils
    ];
    text = ''
      export CAC_P11_KIT_PROXY=${pkgs.p11-kit}/lib/p11-kit-proxy.so
      export CAC_OPENSC_MODULE=${pkgs.opensc}/lib/opensc-pkcs11.so
      ${builtins.readFile ./cac-doctor}
    '';
  };

  cacChromiumSetup = pkgs.writeShellApplication {
    name = "cac-chromium-setup";
    runtimeInputs = with pkgs; [
      coreutils
      gnugrep
      nssTools
    ];
    text = ''
      export CAC_P11_KIT_PROXY=${pkgs.p11-kit}/lib/p11-kit-proxy.so
      ${builtins.readFile ./cac-chromium-setup}
    '';
  };
in
{
  # Keep all locally invoked helper scripts under the user's established
  # ~/.bin convention while retaining their dependencies in the Nix store.
  home.file.".bin/cac-toggle".source = "${cacToggle}/bin/cac-toggle";
  home.file.".bin/cac-doctor".source = "${cacDoctor}/bin/cac-doctor";
  home.file.".bin/cac-chromium-setup".source =
    "${cacChromiumSetup}/bin/cac-chromium-setup";

  # Make GnuPG share the system PC/SC service instead of opening the reader
  # directly and preventing LibreWolf or OpenSC from using it.
  home.file.".gnupg/scdaemon.conf".text = ''
    disable-ccid
    pcsc-shared
  '';

  # LibreWolf uses the Firefox enterprise-policy mechanism. Loading the
  # p11-kit proxy exposes every module configured under /etc/pkcs11/modules,
  # including OpenSC above.
  programs.librewolf.policies.SecurityDevices.Add.p11-kit-proxy =
    "${pkgs.p11-kit}/lib/p11-kit-proxy.so";

}
