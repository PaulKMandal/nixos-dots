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
      playerctl
      brightnessctl
      pulseaudio
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
	 "${modifier}+return" = "exec ${terminal}";
	 "${modifier}+d" = "exec ${menu}";
	 "${modifier}+q" = "kill";
	 "${modifier}+Shift+e" = "exec swaymsg exit";
	 "${modifier}+Shift+c" = "reload";
	 };

         bars = [ { command = "${pkgs.waybar}/bin/waybar"; } ];
	 startup = [
	   { command = "${pkgs.mako}/bin/mako"; always = true;}
	   #{ command = "${pkgs.waybar}/bin/waybar"; always = true; }
	];
      };

      extraConfig = ''
	 default_border pixel 2
	 default_floating_border pixel 2
	 for_window [all] border pixel 2
      '';

   };

   #Kitty Config
   home.file.".config/kitty/kitty.conf".text = ''
      font_family      JetBrainsMono Nerd Font
      font_size        12.0
      adjust_line_height 0
      adjust_column_width 0
      '';

}

