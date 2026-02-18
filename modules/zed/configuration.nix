{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    zed-editor

    # C/C++
    clang-tools        # provides clangd (LSP), clang-format, etc.
    bear               # optional: generate compile_commands.json from make
    cmake              # optional but common
    gnumake            # optional but common
    pkg-config         # optional but common

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

