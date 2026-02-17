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
      udiskie
      polkit_gnome
      adw-gtk3
      papirus-icon-theme
      gnome-themes-extra  # fallback themes
      dconf               # for gsettings/dconf
   ];

   #Sway
   wayland.windowManager.sway = {
      enable = true;
      
      systemd.enable = true;

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
	  "${modifier}+r" 	 = "exec ${pkgs.xfce.thunar}/bin/thunar";
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
	  "${modifier}+Shift+b" = "split auto";
	  "${modifier}+s" = "layout stacking";
	  "${modifier}+w" = "layout tabbed";
	  "${modifier}+e" = "layout toggle split";

	  "${modifier}+f" = "fullscreen toggle";
	  "${modifier}+Shift+space" = "floating toggle";

          # LARBS-ish gaps controls
         "${modifier}+a" = "gaps inner all toggle 10; gaps outer all toggle 5";
         "${modifier}+z" = "gaps inner all plus 2";
         "${modifier}+x" = "gaps inner all minus 2";

         # Optional: control *outer* gaps separately (nice to have)
         "${modifier}+Shift+z" = "gaps outer all plus 2";
         "${modifier}+Shift+x" = "gaps outer all minus 2";

	 };

         bars = [ { command = "${pkgs.waybar}/bin/waybar"; } ];
	 startup = [
	   { command = "${pkgs.swaybg}/bin/swaybg -i ${config.home.homeDirectory}/Pictures/Wallpapers/xPiPUEr.jpg -m fill"; always = true; }
	   { command = "${pkgs.mako}/bin/mako"; always = true;}
	   #{ command = "${pkgs.waybar}/bin/waybar"; always = true; }

	   # polkit agent (needed so mounting is authorized)
           { command = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1"; always = true; }

           # automounter
           { command = "${pkgs.udiskie}/bin/udiskie --tray --appindicator"; always = true; }
	];
      };

      extraConfig = ''
	 default_border pixel 2
	 default_floating_border pixel 2
	 for_window [all] border pixel 2
	 titlebar_border_thickness 2

         # default gaps
         gaps inner 10
         gaps outer 5

        # only show gaps when >1 window in workspace
        #smart_gaps on
      '';

      extraSessionCommands = ''
         export WLR_NO_HARDWARE_CURSORS=1
      '';

   };

   #Shell (fish)
   /*
   programs.fish = {
     enable = true;
   };
   */

   #Shell (zsh)
   programs.zsh = {
     enable = true;
     enableCompletion = true;
     autosuggestion.enable = true;
     syntaxHighlighting.enable = true;
     historySubstringSearch.enable = true;

   # optional but nice:
   history = {
     size = 10000;
     save = 10000;
     share = true;
   };

   initExtra = ''
      # Better completion menu
      zstyle ':completion:*' menu select

      # Accept autosuggestion with Right Arrow (keep this if you like)
      bindkey '^[[C' autosuggest-accept

      # Fish-like: type prefix, then Up/Down cycles matching history
      autoload -Uz up-line-or-beginning-search down-line-or-beginning-search
      zle -N up-line-or-beginning-search
      zle -N down-line-or-beginning-search
      bindkey '^[[A' history-search-backward
      bindkey '^[[B' history-search-forward
    '';
   };

   #wofi config
   programs.wofi = {
     enable = true;
     settings = {
       show = "drun";
       sort_order = "alphabetical";
     };
   };

   #Kitty Config
   programs.kitty = {
     enable = true;
   
     font = {
       name = "JetBrainsMono Nerd Font";
       size = 12.0;
     };
   
     settings = {
       adjust_line_height = "0";
       adjust_column_width = "0";
   
       # transparency
       background_opacity = "0.90";          # 0.0..1.0
       dynamic_background_opacity = "yes";
     };
   };

    gtk = {
    enable = true;

    theme = {
      name = "adw-gtk3-dark";
      package = pkgs.adw-gtk3;
    };

    iconTheme = {
      name = "Papirus-Dark";
      package = pkgs.papirus-icon-theme;
    };

    # optional cursor theme
    # cursorTheme = { name = "Adwaita"; package = pkgs.gnome-themes-extra; };

    gtk3.extraConfig = {
      "gtk-application-prefer-dark-theme" = 1;
    };

    gtk4.extraConfig = {
      "gtk-application-prefer-dark-theme" = 1;
    };
  };

  # This makes many GTK4/libadwaita apps prefer dark
  dconf.settings."org/gnome/desktop/interface" = {
    color-scheme = "prefer-dark";
    gtk-theme = "adw-gtk3-dark";
    icon-theme = "Papirus-Dark";
  };

  #Services
  systemd.user.services.protonmail-bridge = {
    Unit = {
      Description = "Proton Mail Bridge";
      Wants = [ "network-online.target" ];
      After  = [ "network-online.target" ];
    };
  
    Service = {
      ExecStart = "${pkgs.protonmail-bridge}/bin/protonmail-bridge --noninteractive";
      Restart = "on-failure";
      RestartSec = 3;
  
      # Good hygiene
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
    };
  
    Install = {
      WantedBy = [ "default.target" ];
    };
  };
  
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

