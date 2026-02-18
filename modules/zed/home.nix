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
    };

    # optional later:
    # extensions = [ "nix" "rust" ];
    # extraPackages = [ pkgs.nixd pkgs.rust-analyzer ];
    extraPackages = with pkgs; [
      # Nix
      nixd

      # Rust
      rust-analyzer

      # Python
      pyright

      # C/C++
      clang-tools  # provides clangd

      # TS/JS (if you want it)
      nodejs_22
      nodePackages.typescript-language-server
    ];
  };
}

