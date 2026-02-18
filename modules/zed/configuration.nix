{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    zed-editor

    # Nix
    nixd
    alejandra
    statix
    deadnix

    # Python
    pyright
    ruff
    black

    # Rust
    rust-analyzer

    # JS/TS
    nodejs_22
    nodePackages.typescript-language-server
    nodePackages.prettier
  ];
}

