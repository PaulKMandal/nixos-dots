{ pkgs, ... }:

{
  # pcscd provides the host smart-card service. The NixOS module includes the
  # CCID plugin used by the Identiv/SCR33xx reader and most USB CAC/PIV readers.
  services.pcscd.enable = true;

  environment.systemPackages = with pkgs; [
    nssTools
    opensc
    p11-kit
    pcsc-tools
  ];

  # Make OpenSC available through p11-kit. Firefox-family browsers load the
  # p11-kit proxy below rather than registering OpenSC separately in each browser.
  environment.etc."pkcs11/modules/opensc-pkcs11".text = ''
    module: ${pkgs.opensc}/lib/opensc-pkcs11.so
  '';

  # Permit only the interactive workstation account to use pcsc-lite. This is
  # narrower than a world-writable USB rule and covers both daemon and card
  # access checks performed by pcsc-lite.
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if ((action.id == "org.debian.pcsc-lite.access_pcsc" ||
           action.id == "org.debian.pcsc-lite.access_card") &&
          subject.user == "nix") {
        return polkit.Result.YES;
      }
    });
  '';
}
