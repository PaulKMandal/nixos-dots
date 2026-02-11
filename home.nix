{ config, pkgs, ...}:

{
   home.stateVersion = "25.11";

   home.packages = with pkgs; [
      kitty
      rofi
      wofi
      waybar
      mako
      grim
      slurp
      wl-clipboard
      pkgs.nerd-fonts."jetbrains-mono"
      font-awesome
      material-design-icons
   ];

   #Sway
   wayland.windowManager.sway = {
      enable = true;

      config = rec {
         modifier = "Mod4"; #modifier
	 terminal = "${pkgs.kitty}/bin/kitty";
	 menu = "${pkgs.wofi}/bin/wofi --show drun";

	 #keybinds
	 keybindings = {
	 "Mod4+return" = "exec ${terminal}";
	 "Mod4+d" = "exec ${menu}";
	 "Mod4+q" = "kill";
	 };

         bars = [ { command = "${pkgs.waybar}/bin/waybar"; } ];
	 startup = [
	   { command = "${pkgs.mako}/bin/mako"; always = true;}
	];

      };
   };

   #Kitty Config
   home.file.".config/kitty/kitty.conf".text = ''
      font_family      JetBrainsMono Nerd Font
      font_size        12.0
      adjust_line_height 0
      adjust_column_width 0
      '';

}

