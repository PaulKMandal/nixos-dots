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
   ];

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
}

