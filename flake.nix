{
   description = "NixOS with sway";

   inputs = {
      nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
      home-manager.url = "github:nix-community/home-manager/release-25.11";
      home-manager.inputs.nixpkgs.follows = "nixpkgs";
      nur.url = "github:nix-community/NUR";
      sops-nix.url = "github:Mic92/sops-nix";
      sops-nix.inputs.nixpkgs.follows = "nixpkgs";
      nixpkgs-signal.url = "github:NixOS/nixpkgs/nixos-unstable";
   };

   outputs = { self, nixpkgs, home-manager, nur, sops-nix, ...}@inputs:
   let
      system = "x86_64-linux";
      hostname = "nixos";
      in {
         nixosConfigurations.${hostname} = nixpkgs.lib.nixosSystem {
	    inherit system;
            specialArgs = { inherit inputs; };
	    modules = [

               ({ ... }: {
                 nixpkgs.overlays = [
		   nur.overlays.default
                   (final: prev: {
                     waterfox = final.callPackage ./pkgs/waterfox-bin { };
                     ykfde-open = final.callPackage ./pkgs/ykfde-open { };
                   })
                 ];
               })

	       ./configuration.nix
	       sops-nix.nixosModules.sops
	       home-manager.nixosModules.home-manager
	       {
	          home-manager.useGlobalPkgs = true;
		  home-manager.useUserPackages = true;
		  home-manager.backupCommand = "mv -f $1 $1.bak.$(date +%Y%m%d-%H%M%S)";
		  home-manager.users.nix = import ./home.nix;
	       }
            ];
	};
   };
}
