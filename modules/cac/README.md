# CAC/PIV host and VM support

This module gives the physical reader one owner at a time:

- `cac-toggle host` detaches it from libvirt, enables `pcscd`, and returns it
  to LibreWolf/OpenSC.
- `cac-toggle vm` stops and runtime-masks `pcscd`, then attaches the reader to
  the running `win11` domain as a live USB host device.
- `cac-toggle` toggles between those states.
- `cac-toggle status` reports the selected owner.
- `cac-doctor` checks USB, PC/SC, OpenSC, p11-kit, PKCS#11 slots, and the
  generated LibreWolf policy.

The defaults match the Identiv SCR33xx reader (`04e6:5116`) and the `win11`
domain. Override them for one invocation, for example:

```console
CAC_VM='Windows 11' cac-toggle vm
CAC_VENDOR=1234 CAC_PRODUCT=5678 cac-toggle status
```

LibreWolf is configured declaratively. Fully quit all LibreWolf processes and
reopen it after the first rebuild. In `about:policies`, the active policy should
include `SecurityDevices`; under Settings -> Privacy & Security -> Certificates
-> Security Devices, `p11-kit-proxy` should appear.

Chromium and Brave store PKCS#11 modules in a per-user NSS database rather than
accepting the Firefox enterprise policy. Run `cac-chromium-setup` after a Nix
upgrade whenever one of those browsers needs CAC access.

Do not also select the reader through virt-manager's **Redirect USB Device**
menu. The helper uses libvirt USB hostdev directly, and simultaneous SPICE
redirection creates competing ownership paths.
