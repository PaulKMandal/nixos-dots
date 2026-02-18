{ ... }:
{
  xdg.configFile."zed/settings.json".text = builtins.toJSON {
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

    format_on_save = true;
  };

  # If you later want:
  # xdg.configFile."zed/keymap.json".text = builtins.toJSON [ ... ];
}

