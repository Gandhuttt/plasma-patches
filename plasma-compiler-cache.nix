{ lib, ... }:
let
  directory = "/var/cache/plasma-ccache";
  # 3.56 GB live, leaving room in Actions' free 10 GB quota for immutable
  # replacement snapshots. GitHub LRU eviction still applies to older snapshots.
  limits = {
    kwin = "1G";
    plasma-workspace = "768M";
    plasma-desktop = "384M";
    kdeplasma-addons = "256M";
    bluedevil = "128M";
    kinfocenter = "128M";
    plasma-browser-integration = "128M";
    plasma-login-manager = "128M";
    plasma-pa = "128M";
    plasma-setup = "128M";
    powerdevil = "128M";
    print-manager = "128M";
    xdg-desktop-portal-kde = "128M";
  };
in
{
  # Follow programs.ccache's root:nixbld convention, but only bind this cache
  # and change these packages: ccacheStdenv globally would rebuild stock nixpkgs.
  nix.settings.extra-sandbox-paths = [ directory ];
  systemd.tmpfiles.rules = map (path: "d ${path} 2770 root nixbld -") (
    [ directory ] ++ map (name: "${directory}/${name}") (builtins.attrNames limits)
  );

  nixpkgs.overlays = [
    (_final: previous:
      let
        # ccache must run INSIDE cc-wrapper, after expansion of NIX_CFLAGS_* and
        # hardening flags. An outer CMake launcher could incorrectly hide those
        # environment-dependent flags from ccache's direct-mode cache key.
        compiler = previous.ccacheWrapper.override {
          cc = previous.stdenv.cc;
          extraConfig = ''
            export CCACHE_COMPILERCHECK=content
            export CCACHE_COMPRESS=1
            export CCACHE_UMASK=007
            if [[ -z "''${CCACHE_DIR:-}" || ! -w "$CCACHE_DIR" ]]; then
              echo "plasma ccache: sandbox cache directory is missing or not writable: ''${CCACHE_DIR:-unset}" >&2
              exit 1
            fi
          '';
        };
      in
      {
        plasmaCompilerCache = {
          inherit directory limits compiler;
          ccache = previous.ccache;
        };
        kdePackages = previous.kdePackages.overrideScope (_kfinal: kprevious:
          lib.mapAttrs (name: maximum: kprevious.${name}.overrideAttrs (old: {
            # stdenv otherwise seeds GCC from $out's hash, defeating EVERY hit
            # after a patch edit. Use its supported deterministic-seed override,
            # not ccache's unsafe random_seed sloppiness: actual flags are hashed.
            env = (old.env or { }) // {
              NIX_OUTPATH_USED_AS_RANDOM_SEED = builtins.hashString "sha256" (
                "plasma-ccache-v1-${name}-${old.version}"
              );
            };
            preConfigure = (old.preConfigure or "") + ''
              export CC=${compiler}/bin/cc
              export CXX=${compiler}/bin/c++
              export CCACHE_DIR=${directory}/${name}
              export CCACHE_MAXSIZE=${maximum}
              # Keep ccache's default path/header hashing. Install-prefix defines
              # and generated headers MUST invalidate objects when outputs move;
              # never ignore them or enable sloppy hashes to manufacture hits.
            '';
          })) limits
        );
      })
  ];
}
