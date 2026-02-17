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
      wlogout
      swaylock
      swaybg
      discord
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
	   # --- basics ---
	  "${modifier}+Return"   = "exec ${terminal}";
	  "${modifier}+d"        = "exec ${menu}";
	  "${modifier}+q"        = "kill";   # your preference
	  "${modifier}+Shift+c"  = "reload";
	  "${modifier}+Shift+e"  = "exec swaynag -t warning -m 'Exit sway?' -b 'Yes' 'swaymsg exit'";
	  "Print"       = "exec ${pkgs.grim}/bin/grim -g \"$(${pkgs.slurp}/bin/slurp)\" - | ${pkgs.wl-clipboard}/bin/wl-copy";

	  # --- focus movement (vim keys + arrows) ---
	  "${modifier}+h"        = "focus left";
	  "${modifier}+j"        = "focus down";
	  "${modifier}+k"        = "focus up";
	  "${modifier}+l"        = "focus right";
	  "${modifier}+Left"     = "focus left";
	  "${modifier}+Down"     = "focus down";
	  "${modifier}+Up"       = "focus up";
	  "${modifier}+Right"    = "focus right";

	  # --- move windows (vim keys + arrows) ---
	  "${modifier}+Shift+h"  = "move left";
	  "${modifier}+Shift+j"  = "move down";
	  "${modifier}+Shift+k"  = "move up";
	  "${modifier}+Shift+l"  = "move right";
	  "${modifier}+Shift+Left"  = "move left";
	  "${modifier}+Shift+Down"  = "move down";
	  "${modifier}+Shift+Up"    = "move up";
	  "${modifier}+Shift+Right" = "move right";

	  # --- workspaces 1..10 ---
	  "${modifier}+1" = "workspace number 1";
	  "${modifier}+2" = "workspace number 2";
	  "${modifier}+3" = "workspace number 3";
	  "${modifier}+4" = "workspace number 4";
	  "${modifier}+5" = "workspace number 5";
	  "${modifier}+6" = "workspace number 6";
	  "${modifier}+7" = "workspace number 7";
	  "${modifier}+8" = "workspace number 8";
	  "${modifier}+9" = "workspace number 9";
	  "${modifier}+0" = "workspace number 10";

	  "${modifier}+Shift+1" = "move container to workspace number 1";
	  "${modifier}+Shift+2" = "move container to workspace number 2";
	  "${modifier}+Shift+3" = "move container to workspace number 3";
	  "${modifier}+Shift+4" = "move container to workspace number 4";
	  "${modifier}+Shift+5" = "move container to workspace number 5";
	  "${modifier}+Shift+6" = "move container to workspace number 6";
	  "${modifier}+Shift+7" = "move container to workspace number 7";
	  "${modifier}+Shift+8" = "move container to workspace number 8";
	  "${modifier}+Shift+9" = "move container to workspace number 9";
	  "${modifier}+Shift+0" = "move container to workspace number 10";

	  # --- splits & layouts ---
	  "${modifier}+b" = "splith";                  # horizontal split
	  "${modifier}+v" = "splitv";                  # vertical split
	  "${modifier}+s" = "layout stacking";
	  "${modifier}+w" = "layout tabbed";
	  "${modifier}+e" = "layout toggle split";

	  "${modifier}+f" = "fullscreen toggle";
	  "${modifier}+Shift+space" = "floating toggle";

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
   
   xdg.configFile."waybar/power_menu.xml".text = ''
      <?xml version="1.0" encoding="UTF-8"?>
      <interface>
        <object class="GtkMenu" id="menu">
          <child>
            <object class="GtkMenuItem" id="suspend">
              <property name="label">Suspend</property>
            </object>
          </child>
          <child>
            <object class="GtkMenuItem" id="hibernate">
              <property name="label">Hibernate</property>
            </object>
          </child>
          <child>
            <object class="GtkMenuItem" id="shutdown">
              <property name="label">Shutdown</property>
            </object>
          </child>
          <child>
            <object class="GtkSeparatorMenuItem" id="delimiter1"/>
          </child>
          <child>
            <object class="GtkMenuItem" id="reboot">
              <property name="label">Reboot</property>
            </object>
          </child>
        </object>
      </interface>
      '';
}

