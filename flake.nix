{
  description = "Cached builds for native KDE wheel, touchpad and taskbar navigation";

  # Keep this revision identical to the local NixOS package set: changing it
  # changes derivation paths and prevents substitution of these remote builds.
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/5d2b81a7a3be3e2f832879028e4d60abbf58e9a0";

  nixConfig = {
    extra-substituters = [ "https://gandhuttt-plasma.cachix.org" ];
    extra-trusted-public-keys = [
      "gandhuttt-plasma.cachix.org-1:dwZd2llRGEsg5zLwR4svLkI4Gj8RI6zONEdEfut61Ro="
    ];
  };

  outputs = { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      # Reuse the original module overlays verbatim, including KWin's native
      # integration test. Personal NixOS configuration stays outside this repo.
      modules = [
        (import ./kwin-navigation-wheel.nix { inherit (nixpkgs) lib; })
        (import ./plasma-taskbar-no-wrap.nix { })
        (import ./plasma-compiler-cache.nix { inherit (nixpkgs) lib; })
      ];
      pkgs = import nixpkgs {
        inherit system;
        overlays = builtins.concatMap (module: module.nixpkgs.overlays) modules;
      };
      kde = pkgs.kdePackages;

      # These are the other Plasma desktop packages whose derivations change
      # with these overlays at the pinned revision. Mobile/bigscreen sessions
      # are deliberately excluded; hardware/service settings stay local.
      supportNames = [
        "bluedevil"
        "kinfocenter"
        "plasma-browser-integration"
        "plasma-login-manager"
        "plasma-pa"
        "plasma-setup"
        "powerdevil"
        "print-manager"
        "xdg-desktop-portal-kde"
      ];
      support = pkgs.linkFarm "patched-plasma-support" (
        builtins.concatMap (name: [
          { inherit name; path = kde.${name}.out; }
          { name = "${name}-dev"; path = kde.${name}.dev; }
        ]) supportNames
      );
    in
    {
      nixosModules.compiler-cache = import ./plasma-compiler-cache.nix;
      # Metadata/tools let CI and throwaway smoke derivations use exactly the
      # same wrapped compiler, limits and sandbox path as the desktop builds.
      legacyPackages.${system}.plasmaCompilerCache = pkgs.plasmaCompilerCache;
      packages.${system} = builtins.listToAttrs (
        map (name: { inherit name; value = kde.${name}; }) supportNames
      ) // {
        inherit (kde) kwin plasma-workspace plasma-desktop kdeplasma-addons;
        inherit support;
        # Hold runtime and development outputs in the cache, without forcing
        # the large debug outputs. NixOS also consumes workspace's sessions.
        default = pkgs.linkFarm "patched-plasma-desktop" [
          { name = "kwin"; path = kde.kwin.out; }
          { name = "kwin-dev"; path = kde.kwin.dev; }
          { name = "plasma-workspace"; path = kde.plasma-workspace.out; }
          { name = "plasma-workspace-dev"; path = kde.plasma-workspace.dev; }
          { name = "plasma-workspace-sessions"; path = kde.plasma-workspace.sessions; }
          { name = "plasma-desktop"; path = kde.plasma-desktop.out; }
          { name = "plasma-desktop-dev"; path = kde.plasma-desktop.dev; }
          { name = "kdeplasma-addons"; path = kde.kdeplasma-addons.out; }
          { name = "kdeplasma-addons-dev"; path = kde.kdeplasma-addons.dev; }
          { name = "support"; path = support; }
        ];
      };
    };
}
