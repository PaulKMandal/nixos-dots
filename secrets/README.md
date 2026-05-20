# Secrets layout

This repo uses a hybrid model:

1. `sops-nix` manages runtime secrets that need to exist as files.
2. YubiKey-backed GPG protects major backup material.
3. SSH/GPG keys should use their native encrypted or hardware-backed storage when possible.
4. Plaintext staging files should be shredded after import or conversion.

## Runtime secrets

The main SOPS file is:

```text
secrets/sops.yaml
```

It should contain runtime secrets such as WireGuard configs:

```yaml
wireguard:
  proton_ca924_conf: |
    [Interface]
    ...
  proton_ca924_filter_conf: |
    [Interface]
    ...
  gpu_server_conf: |
    [Interface]
    ...
```

These are materialized by `sops-nix` to:

```text
/run/secrets/wireguard/proton_ca924.conf
/run/secrets/wireguard/proton_ca924_filter.conf
/run/secrets/wireguard/gpu_server.conf
```

## Encrypted bootstrap backups

Suggested encrypted backup locations:

```text
secrets/bootstrap/sops-age-key.txt.asc.gpg
secrets/ssh/github-nixos-fw13.asc.gpg
```
