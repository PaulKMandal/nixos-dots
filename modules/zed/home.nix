{ pkgs, ... }:
{
  programs.zed-editor = {
    enable = true;

    # IMPORTANT: allow Zed to write/migrate settings.json
    mutableUserSettings = true;

    userSettings = {
      icon_theme = {
        mode = "system";
        light = "Zed (Default)";
        dark = "Zed (Default)";
      };

      ui_font_size = 16;
      buffer_font_size = 15;

      theme = {
        mode = "system";
        light = "One Light";
        dark = "One Dark";
      };

      format_on_save = "on";

      show_completions_on_input = true;

      # Tell Zed which language server to prefer for each language
      languages = {
        Python = { language_servers = [ "pyright" "..." ]; };
        Nix = { language_servers = [ "nixd" "..." ]; };
        Rust = { language_servers = [ "rust-analyzer" "..." ]; };
    
        C = { language_servers = [ "clangd" "..." ]; };
        "C++" = { language_servers = [ "clangd" "..." ]; };
    
        JavaScript = { language_servers = [ "typescript-language-server" "..." ]; };
        TypeScript = { language_servers = [ "typescript-language-server" "..." ]; };
        TSX = { language_servers = [ "typescript-language-server" "..." ]; };
      };
    
      # Force Zed to use the system binaries (critical on NixOS)
      lsp = {
        pyright = {
          binary = {
            ignore_system_version = false;
            path = "/run/current-system/sw/bin/pyright-langserver";
            arguments = [ "--stdio" ];
          };
        };
    
        nixd = {
          binary = {
            ignore_system_version = false;
            path = "/run/current-system/sw/bin/nixd";
          };
        };
    
        "rust-analyzer" = {
          binary = {
            ignore_system_version = false;
            path = "/run/current-system/sw/bin/rust-analyzer";
          };
        };
    
        clangd = {
          binary = {
            ignore_system_version = false;
            path = "/run/current-system/sw/bin/clangd";
          };
        };
    
        "typescript-language-server" = {
          binary = {
            ignore_system_version = false;
            path = "/run/current-system/sw/bin/typescript-language-server";
            arguments = [ "--stdio" ];
          };
        };
      };
    };

  };
}

