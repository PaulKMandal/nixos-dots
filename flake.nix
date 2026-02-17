{
   description = "NixOS with sway";

   inputs = {
      nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
      home-manager.url = "github:nix-community/home-manager/release-25.11";
      home-manager.inputs.nixpkgs.follows = "nixpkgs";

      waterfox = {
        url = "github:sammypanda/nixos-waterfox";
        inputs.nixpkgs.follows = "nixpkgs";
      };
   };

   outputs = { self, nixpkgs, home-manager, waterfox, ...}:
   let
      system = "x86_64-linux";
      hostname = "nixos";
      in {
         nixosConfigurations.${hostname} = nixpkgs.lib.nixosSystem {
	    inherit system;
	    modules = [

               ({ ... }: {
                 nixpkgs.overlays = [
                   (final: prev: {
                     waterfox = waterfox.packages.${system}.default;
                   })
                 ];
               })

	       ./configuration.nix
	       home-manager.nixosModules.home-manager
	       {
	          home-manager.useGlobalPkgs = true;
		  home-manager.useUserPackages = true;

		  home-manager.users.nix = import ./home.nix;
	       }
            ];
	};
   };
}
