{ config, lib, pkgs, ... }:
let
  power = pkgs.writeShellApplication {
    name = "framework-power";
    runtimeInputs = with pkgs; [
      brightnessctl sway swaylock systemd util-linux procps libnotify wofi
      kitty docker libvirt tlp
    ];
    text = ''
      exec ${pkgs.python3}/bin/python3 -I ${./desktop.py} "$@"
    '';
  };
  python = pkgs.python3.withPackages (ps: [ ps.json5 ]);
  waybarSource = pkgs.replaceVars ./waybar.py {
    power = "${power}/bin/framework-power";
    waybar = "${pkgs.waybar}/bin/waybar";
  };
  waybar = pkgs.writeShellScriptBin "framework-waybar" ''
    exec ${python}/bin/python3 ${waybarSource} "$@"
  '';
  reloadBar = pkgs.writeShellScript "framework-waybar-reload" ''
    set -eu
    ${waybar}/bin/framework-waybar --prepare
    ${pkgs.coreutils}/bin/kill -SIGUSR2 "$1"
  '';
in
{
  home.packages = [ power ];
  # The existing Home Manager Waybar service remains the ONLY Waybar owner.
  # Read its unmanaged config at runtime, modify a copy, preserve its CSS.
  systemd.user.services.waybar.Service = {
    ExecStart = lib.mkForce "${waybar}/bin/framework-waybar";
    ExecReload = lib.mkForce "${reloadBar} $MAINPID";
  };

  wayland.windowManager.sway.extraConfig = lib.mkAfter ''
    # These work while swaylock is active as well as in the unlocked session.
    bindsym --locked XF86MonBrightnessDown exec ${power}/bin/framework-power down
    bindsym --locked XF86MonBrightnessUp exec ${power}/bin/framework-power up
    bindsym --locked Mod4+Shift+o exec ${power}/bin/framework-power screen-off
    bindsym --locked Mod4+Ctrl+o exec ${power}/bin/framework-power screen-on
    bindsym Mod4+Shift+p exec ${power}/bin/framework-power menu
    bindsym Mod4+Escape exec ${power}/bin/framework-power lock
    bindsym XF86PowerOff exec ${power}/bin/framework-power menu
  '';

  services.swayidle = {
    enable = true;
    systemdTarget = "sway-session.target";
    timeouts = [
      {
        timeout = 180;
        command = "${power}/bin/framework-power idle-dim";
        resumeCommand = "${power}/bin/framework-power idle-resume";
      }
      { timeout = 600; command = "${power}/bin/framework-power idle-lock"; }
      {
        timeout = 660;
        command = "${power}/bin/framework-power idle-off";
        resumeCommand = "${power}/bin/framework-power idle-resume";
      }
      { timeout = 1800; command = "${power}/bin/framework-power idle-sleep"; }
    ];
    events = [
      { event = "before-sleep"; command = "${power}/bin/framework-power lock"; }
      { event = "lock"; command = "${power}/bin/framework-power lock"; }
      { event = "after-resume"; command = "${power}/bin/framework-power after-resume"; }
    ];
  };
  systemd.user.services.framework-power-watch = {
    Unit = {
      Description = "Framework battery display policy and low-battery warnings";
      After = [ "sway-session.target" ];
      PartOf = [ "sway-session.target" ];
      ConditionEnvironment = "SWAYSOCK";
    };
    Service = {
      ExecStart = "${power}/bin/framework-power watch";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = [ "sway-session.target" ];
  };
  xdg.desktopEntries.framework-power = {
    name = "Framework Power";
    comment = "Charging, display-off, power profiles, sleep, and diagnostics";
    exec = "${power}/bin/framework-power menu";
    icon = "battery";
    terminal = false;
    categories = [ "Settings" "System" ];
  };
}
