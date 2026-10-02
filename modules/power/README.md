# Framework power configuration

Patch base: the exact working files in the uploaded `nixconfig(4).tar`, not an older Git commit. The patch changes two existing files (`configuration.nix` and `home.nix`) and adds this module. It leaves `flake.lock`, storage layout, virtualization, networking, browsers, secrets, and the original Waybar configuration/CSS unchanged.

## Apply and activate

Run from the root of your existing `nixos-dots` checkout, with the patch saved in `~/Downloads`. Do not use `git am`, reset your checkout, or discard existing changes.

```sh
git apply --check "$HOME/Downloads/framework-power.patch" &&
git apply "$HOME/Downloads/framework-power.patch" &&
git add -N modules/power &&
nixos-rebuild build --flake .#nixos
```

`git add -N` makes the new files visible to the Git-backed flake without committing or staging the contents of your existing changes. The build command does not activate the new generation. Stop if any step fails.

After a successful build, save open work. The next command activates new power services and can restart/reload Waybar, idle handling, and power management. The initial charge limit becomes **80%** when hardware verification succeeds.

```sh
sudo nixos-rebuild switch --flake .#nixos
```

**Reboot once after activation**, with work saved, so the new resume configuration/initrd and session configuration are active. Do not test hibernation before that reboot.

```sh
sudo reboot
```

After logging back into Sway:

```sh
framework-power doctor
```

The Python tests also run as a build dependency. A successful generation provides `/etc/framework-power/tests-passed`. This marker proves those software tests passed, not that your laptop completed a hibernate/resume round trip.

## Requested controls

| Control | Behavior |
| --- | --- |
| Brightness down | Reduces brightness through progressively finer low-end steps to 0%. |
| Brightness down again at 0% | Powers off currently lit displays, including attached displays, without suspending the computer or moving workspaces. Also turns off supported keyboard backlighting. |
| Brightness up after manual screen-off | Sets the internal panel to 1% before turning the saved displays back on. Further presses increase brightness normally. |
| Mouse movement / ordinary keys after manual screen-off | Do not intentionally wake the displays through the idle controller. |
| Left-click existing power icon | Toggles the charge limit between 80% and 100%. |
| Right-click power icon | Opens charging, power-policy, display, idle, sleep, and diagnostics controls. |
| Middle-click power icon | Locks the screen. |
| Left/right-click battery module | Also toggle the cap / open the menu, respectively. |
| Super+Shift+O | Explicit screen-off, leaving applications running. |
| Super+Ctrl+O | Explicit screen-on. |
| Super+Shift+P | Power menu. |
| Super+Escape | Lock. |
| Physical power key in an unlocked Sway session | Opens the power menu instead of immediately shutting down. |

The brightness and explicit display on/off bindings have Sway's `--locked` flag, so they remain usable under swaylock. Screen-off is **not** screen-lock: automatic locking remains enabled unless you pause automatic idle actions. The physical power-key menu binding is not available while locked; the hardware long-press emergency action is not changed.

Manual darkness and idle blanking are tracked separately. Manual darkness prevents the new *idle-triggered* sleep action, allowing overnight applications to continue running. It does not override an explicit lid-close sleep request, a manually requested sleep, or critical-battery handling. Opening/closing a lid, firmware behavior, monitor hotplug, restarting Sway, and unrelated display-management software are outside the “ordinary input does not wake” guarantee.

External monitors return at their own existing brightness; software backlight control here changes only the laptop's native backlight. Supported keyboard LEDs are restored to their saved setting when manual darkness ends.

## Charge cap

The first successful initialization sets 80%. Left-click toggles 80/100; the menu also provides explicit selections. The desired setting is stored in `/var/lib/framework-power/desired-charge.json` and reapplied at boot and after resume. The restore service retries transient EC/sysfs startup failures, is re-verified 30 seconds after boot and every 10 minutes, and resume queues that retry-capable service asynchronously so charge control cannot delay display wake.

The root helper prefers a kernel `charge_control_end_threshold` interface when one system battery provides it, otherwise it uses the pinned `fw-ectool`'s Framework-specific `fwchargelimit` command. It checks the machine vendor, allows only fixed operations, and reads the hardware setting back before reporting success. It does not flash firmware, execute arbitrary shell commands, or grant unrestricted root access to ectool.

The icon reports the last verified cap and verification time, with a `?`/error if verification fails or the cached result came from another boot. It is not a continuously polled EC measurement. A change made outside this controller may not appear until the next verification. Refresh explicitly with:

```sh
framework-power charge-status
```

An 80% cap does not force an already-full battery to discharge immediately. A 100% selection permits full charging; it does not promise instantaneous charging or remove the firmware's safety protections.

Hardware/BIOS compatibility is not established by the uploaded configuration. An unsupported EC/interface results in an error, not a fabricated “80% enabled” indicator. Check:

```sh
journalctl -b -u framework-charge-limit -u framework-charge-resume --no-pager
```

## Power and display policies

**TLP is the sole CPU/device policy manager.** Power-profiles-daemon, auto-cpufreq, and automatic PowerTOP tuning are disabled to avoid overlapping policy writers.

| Setting | AC / forced AC | Battery / forced battery |
| --- | --- | --- |
| CPU energy-performance preference | balance_performance | balance_power |
| CPU boost | Allowed | Disabled |
| Platform profile, where supported | balanced | low-power |
| PCIe ASPM, where supported | Firmware/kernel default | powersupersave; no forced ASPM kernel flag |
| PCI runtime power management | on | auto |
| Wi-Fi power saving | off | on |
| Audio device power saving | off | on |
| Internal display | Restore saved pre-battery setting | Cap to 35% on transition; use native-resolution ~60 Hz only when advertised |
| Keyboard backlight | Restore saved setting | Off on transition |

The watcher runs every 15 seconds, not on every keypress. It does not repeatedly clamp brightness after you manually raise it on battery. It changes only internal-panel refresh modes and does not fabricate unsupported modes. AC restoration is based on settings saved during the current Sway session. Forced policy selections last until you return to automatic mode or reboot.

After system resume, the display controller reasserts DPMS-on twice with a short settle interval and suppresses automatic refresh-rate changes for eight seconds. This avoids racing Sway/wlroots/DRM panel recovery while preserving explicit manual screen-off state.

Battery boost-off is a deliberate performance tradeoff. Use the right-click menu's **force AC settings** option for compilation or other work where performance matters more than runtime, including while unplugged. Unsupported TLP controls may be skipped by the hardware/kernel; inspect actual state with `sudo tlp-stat -s -p`.

USB autosuspend is enabled with exclusions for supported audio, Bluetooth, phone, printer, WWAN devices, plus explicit common YubiKey IDs. TLP excludes HID inputs automatically. No Bluetooth radios, virtualization services, running guests, containers, or background applications are deliberately stopped. Unusual USB devices may need an additional ID in `USB_DENYLIST`; identify them with `sudo tlp-stat -u` rather than blindly running `powertop --auto-tune`.

The patch adds a 25%-of-RAM logical zram swap device using zstd at priority 100, while retaining your existing disk swap. Zram can reduce disk swapping under some workloads; it does not create physical RAM, guarantee lower power use, or provide a hibernation target. Existing fstrim remains unchanged.

## Idle and sleep defaults

| Trigger | Action |
| --- | --- |
| 3 minutes idle, on battery | Dim the internal panel to 10%, unless already lower. |
| 10 minutes idle, either power source | Lock. |
| 11 minutes idle, either power source | Idle display-off. Ordinary input can restore this, unlike manual darkness. |
| 30 minutes idle, on battery | Request systemd sleep only when not manually dark/paused and no busy workload is detected. |
| Lid close, AC or docked | Ignore, preserving your existing AC behavior and normal docked behavior. |
| Lid close, battery and undocked | Request systemd sleep. |
| Supported suspend-then-hibernate | Suspend first; hibernate after the configured one-hour battery delay. |
| Battery 15% / 8% | Low / critical warning. |
| Battery 3% | UPower critical action configured as Hibernate. |

The idle-sleep check skips running libvirt system VMs, Docker containers, or load-average >= 1; inability to query a workload service also skips sleep. These are conservative checks, not a complete workload detector. The timeout is evaluated when it fires; a busy workload ending later does not itself retrigger that same idle timeout. Keyboard activity followed by a new idle interval can trigger a fresh check.

Pause automatic idle actions from the menu when keeping an otherwise idle machine available for SSH, downloads, presentations, or a long task that does not register as CPU load. Pausing does not disable before-sleep locking, lid behavior, or critical-battery protection. Explicit menu sleep honors logind sleep inhibitors. This patch does not add workload inhibitors to every possible application or override lid behavior based on VM state.

Hibernation uses the **existing** `/dev/disk/by-label/nixos-swap` configured in `storage.nix`; the scanned hardware file also identifies the original LVM swap device. No volume is formatted or resized. The config does not reveal actual RAM size, free disk-swap capacity, live encryption topology, or successful firmware resume behavior. These must be checked on the laptop.

Systemd is configured to prefer suspend-then-hibernate and fall back to suspend when that operation is unavailable. That fallback does **not** prove hibernation is safe. UPower may fall back to **poweroff** when hibernation is unavailable, so do not rely on the 3% action to preserve unsaved work before testing. Save work and run the diagnostics after the required reboot, then make the first controlled test while able to recover a failed resume:

```sh
framework-power hibernate
```

There is no forced `mem_sleep_default=deep`, no invented resume offset, and no change to your disk-encryption setup.

## Waybar preservation

Your archive intentionally does not contain a managed Waybar main config or stylesheet. The wrapper therefore discovers the actual config at launch, parses JSON/JSONC (including common include/group/multiple-bar layouts), and writes an overlaid copy under `$XDG_RUNTIME_DIR/framework-power-user/waybar.json`.

Recognized existing power module IDs and their positions/icons are reused. The battery module keeps its existing format. Other module commands and original config/CSS files are preserved. If no recognizable power module exists, one `custom/framework-power` module is appended. If the config cannot be safely parsed, the original bar is launched unchanged; the menu and display hotkeys remain available.

This cannot prove that an unknown custom power module in the missing live config will be recognized. Standard names (`custom/power`, `custom/powermenu`, `custom/wlogout`, etc.), common power glyphs, and `power_menu` menu files are detected. Arbitrary shell expansion in include filenames is deliberately not executed. Explicitly configured standard `style.css` is reused; highly custom launch-time styling flags are not reconstructed.

Home Manager's existing systemd service remains the only Waybar owner. After changing your original Waybar configuration later, regenerate the overlay and reload the bar with:

```sh
systemctl --user reload waybar
```

## Installed tools and useful commands

The patch includes TLP, brightnessctl, swayidle, PowerTOP, powerstat, acpi, UPower, lm_sensors, nvme-cli, libva-utils, fwupd support, fw-ectool, and the `framework-power` command/menu. Existing swaylock, wofi, and notification facilities are reused. Firmware updates are available for deliberate inspection/installation; no automatic firmware flash is added.

```sh
framework-power menu
framework-power charge-100
framework-power charge-80
framework-power profile-auto
framework-power profile-battery
framework-power profile-ac
framework-power idle-toggle
framework-power sleep
framework-power suspend
framework-power hibernate
framework-power doctor
sudo tlp-stat -s -p -b -u
journalctl --user -b -u framework-power-watch -u swayidle -u waybar --no-pager
```

Power-policy and charge controls use narrowly allowed sudo commands without a password prompt. Normal display controls use brightnessctl's udev/video-group access rather than unrestricted root privileges.

## Recovery / rollback

For an unexpectedly dark Sway session, first use brightness up or Super+Ctrl+O. From a terminal that has the running session's `SWAYSOCK`:

```sh
swaymsg 'output * power on'
brightnessctl --class=backlight set 35%
```

When removing the power module entirely, select full charging **before** removing it if that is the desired rollback state:

```sh
framework-power charge-100
```

Rolling back NixOS does not automatically erase an EC charge limit. The charge helper's persistent setting also survives a NixOS rollback and would be restored if the module is re-enabled later.

To remove only this patch from an otherwise unchanged patched checkout:

```sh
git apply -R --check "$HOME/Downloads/framework-power.patch" &&
git apply -R "$HOME/Downloads/framework-power.patch" &&
git restore --staged -- modules/power &&
sudo nixos-rebuild switch --flake .#nixos
```

If you have since edited these files, do not force the reverse patch. Review the changes instead. To recover an unusable generation, select the previous NixOS generation from the boot menu or, where appropriate, run `sudo nixos-rebuild switch --rollback`; reboot for boot/initrd changes.

## Validation scope

The supplied Python suite covers fake sysfs charge interfaces, strict EC parsing, read-back failures, allowed root actions, manual/idle display separation, brightness ordering, AC/BAT restoration, unsupported refresh modes, workload safeguards, stale caches, and Waybar JSONC/includes/groups/source preservation.

The authoring environment ran these hardware-free tests and checked patch application/reversal against the exact uploaded files. It did **not** have Nix installed, a live Sway session, the actual unmanaged Waybar config, or access to your Framework hardware. A complete NixOS evaluation/build and real EC/sleep tests remain to be performed on your machine. Build before switching; do not interpret unit tests as hardware certification.

## Primary implementation references

- Pinned nixpkgs: `687f05a9184cad4eaf905c48b63649e3a86f5433` (TLP 1.8.0, systemd 258.7).
- Pinned Home Manager: `d1686dc7d36cbd1234cb226ad6ef97e882716acb` (swayidle / Waybar module interfaces).
- Sway output power versus disabling outputs: https://github.com/swaywm/sway/blob/master/sway/sway-output.5.scd
- Swayidle events and locking handshake: https://github.com/swaywm/swayidle/blob/master/swayidle.1.scd
- Systemd sleep configuration: https://github.com/systemd/systemd/blob/v258/man/systemd-sleep.conf.xml
- Systemd logind sleep selection / lid policy: https://github.com/systemd/systemd/blob/v258/man/logind.conf.xml
- Framework-specific EC charge command in the pinned source: https://github.com/DHowett/ectool/blob/abdd574ebe3640047988cb928bb6789a15dd1390/src/ectool.cc
- TLP processor controls: https://linrunner.de/tlp/settings/processor.html
- TLP USB exclusions: https://linrunner.de/tlp/settings/usb.html
- Waybar include/search behavior: https://github.com/Alexays/Waybar/blob/0.14.0/src/config.cpp
