{ config, lib, pkgs, ... }:
let
  powerTests = import ./tests.nix { inherit pkgs; };
  rootSource = pkgs.replaceVars ./root.py {
    ectool = "${pkgs.fw-ectool}/bin/ectool";
    tlp = "${config.services.tlp.package}/bin/tlp";
    rootPath = lib.makeBinPath [ config.services.tlp.package pkgs.coreutils pkgs.util-linux ];
  };
  rootControl = pkgs.writeShellScriptBin "framework-power-root" ''
    exec ${pkgs.python3}/bin/python3 -I ${rootSource} "$@"
  '';
  allowedActions = [
    "charge-toggle" "charge-80" "charge-100" "charge-status"
    "profile-auto" "profile-ac" "profile-battery"
  ];
in
{
  # Building this generation must also pass the hardware-free regression tests.
  environment.etc."framework-power/tests-passed".source = powerTests;

  # TLP owns CPU/device policy. Do not run competing autotuners alongside it.
  powerManagement.enable = true;
  powerManagement.powertop.enable = false;
  services.power-profiles-daemon.enable = false;
  services.auto-cpufreq.enable = false;
  services.tlp = {
    enable = true;
    settings = {
      TLP_DEFAULT_MODE = "AC";
      TLP_PERSISTENT_DEFAULT = 0;
      CPU_ENERGY_PERF_POLICY_ON_AC = "balance_performance";
      CPU_ENERGY_PERF_POLICY_ON_BAT = "balance_power";
      CPU_BOOST_ON_AC = 1;
      CPU_BOOST_ON_BAT = 0;
      PLATFORM_PROFILE_ON_AC = "balanced";
      PLATFORM_PROFILE_ON_BAT = "low-power";
      PCIE_ASPM_ON_AC = "default";
      PCIE_ASPM_ON_BAT = "powersupersave";
      RUNTIME_PM_ON_AC = "on";
      RUNTIME_PM_ON_BAT = "auto";
      SATA_LINKPWR_ON_AC = "med_power_with_dipm";
      SATA_LINKPWR_ON_BAT = "med_power_with_dipm";
      WIFI_PWR_ON_AC = "off";
      WIFI_PWR_ON_BAT = "on";
      WOL_DISABLE = "Y";
      SOUND_POWER_SAVE_ON_AC = 0;
      SOUND_POWER_SAVE_ON_BAT = 1;
      USB_AUTOSUSPEND = 1;
      # TLP also excludes HID input devices automatically. Do not interrupt
      # keyboard/mouse, headset, Bluetooth, phone flashing, or printer workflows.
      USB_EXCLUDE_AUDIO = 1;
      USB_EXCLUDE_BTUSB = 1;
      USB_EXCLUDE_PHONE = 1;
      USB_EXCLUDE_PRINTER = 1;
      USB_EXCLUDE_WWAN = 1;
      USB_DENYLIST = [ "1050:0407" "1050:0406" "1050:0405" "1050:0404" ];
      # Charge thresholds are deliberately NOT set here: the persistent
      # 80/100 control below is their sole owner.
    };
  };

  services.upower = {
    enable = true;
    usePercentageForPolicy = true;
    percentageLow = 15;
    percentageCritical = 8;
    percentageAction = 3;
    criticalPowerAction = "Hibernate";
  };
  services.fwupd.enable = true; # Exposes updates; does not flash firmware automatically.

  # This is the EXISTING labeled swap inside your LUKS/LVM setup. No resize,
  # formatting, new swapfile, resume_offset, or encryption changes are made.
  boot.resumeDevice = "/dev/disk/by-label/nixos-swap";
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 25;
    priority = 100;
  };

  # systemd's generic 'sleep' selects the first supported operation, falling
  # back to suspend when hibernation is unavailable (e.g. insufficient swap).
  services.logind.settings.Login = {
    HandleLidSwitch = "sleep";
    HandleLidSwitchExternalPower = "ignore";
    HandleLidSwitchDocked = "ignore";
    HandlePowerKey = "ignore"; # Sway opens the menu, rather than powering off.
    HandleSuspendKey = "sleep";
    SleepOperation = "suspend-then-hibernate suspend";
    IdleAction = "ignore"; # Session controller handles AC/BAT and manual darkness.
  };
  environment.etc."systemd/sleep.conf.d/60-framework-power.conf".text = ''
    [Sleep]
    AllowSuspend=yes
    AllowHibernation=yes
    AllowSuspendThenHibernate=yes
    SuspendState=mem
    HibernateDelaySec=1h
    HibernateOnACPower=no
  '';
  # Keep the firmware/kernel-selected suspend state. In particular do NOT
  # force mem_sleep_default=deep on a machine that only supports s2idle.
  security.pam.services.swaylock = { };
  services.udev.packages = [ pkgs.brightnessctl ];
  boot.kernelModules = [ "cros_ec_lpcs" "cros_ec_dev" ];

  environment.systemPackages = with pkgs; [
    rootControl brightnessctl swayidle powertop powerstat acpi upower
    lm_sensors nvme-cli libva-utils fw-ectool
  ];
  # Exact commands only: no unrestricted sudo ectool, shell, or writable script.
  security.sudo.extraRules = [{
    users = [ "nix" ];
    commands = map (action: {
      command = "${rootControl}/bin/framework-power-root ${action}";
      options = [ "NOPASSWD" ];
    }) allowedActions;
  }];
  environment.etc."framework-power/root-command".text =
    "${rootControl}/bin/framework-power-root\n";
  systemd.tmpfiles.rules = [
    "d /var/lib/framework-power 0755 root root -"
    "d /run/framework-power 0755 root root -"
  ];
  systemd.services.framework-charge-limit = {
    description = "Restore and verify Framework charge limit (initial default: 80%)";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-modules-load.service" "tlp.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${rootControl}/bin/framework-power-root restore-charge";
    };
  };
  # The EC/charge sysfs interface can appear or be reset after the first boot
  # oneshot.  Re-verify shortly after boot and periodically thereafter.  The
  # helper writes only when hardware differs from the persisted 80/100 choice.
  systemd.timers.framework-charge-limit = {
    description = "Re-verify Framework charge limit";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "30s";
      OnUnitActiveSec = "10min";
      AccuracySec = "15s";
      Unit = "framework-charge-limit.service";
    };
  };
  systemd.services.framework-charge-resume = {
    description = "Reapply Framework charge limit after resume";
    wantedBy = [ "sleep.target" ];
    before = [ "sleep.target" ];
    unitConfig.StopWhenUnneeded = true;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.coreutils}/bin/true";
      # Queue the retry-capable service without delaying the system resume path.
      ExecStop = "${pkgs.systemd}/bin/systemctl --no-block restart framework-charge-limit.service";
    };
  };
}
