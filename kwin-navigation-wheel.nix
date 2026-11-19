{ lib, ... }:
{
  # Opt in per user with [MouseBindings] NavigationWheel=true in kwinrc.
  # Reuse KWin's native axis shortcuts; no evdev grab or virtual input device.
  nixpkgs.overlays = [
    (_final: previous: {
      kdePackages = previous.kdePackages.overrideScope (_kfinal: kprevious: {
        kwin = kprevious.kwin.overrideAttrs (old: {
          patches = (old.patches or [ ]) ++ [
            ./kwin-navigation-wheel.patch
            ./kwin-navigation-wheel-tests.patch
          ];
          cmakeFlags = builtins.filter
            (flag: !lib.hasPrefix "-DBUILD_TESTING" flag)
            (old.cmakeFlags or [ ]) ++ [ "-DBUILD_TESTING=ON" ];
          buildInputs = (old.buildInputs or [ ]) ++ [ kprevious.kwayland ];
          nativeCheckInputs = (old.nativeCheckInputs or [ ]) ++ [ previous.dbus ];
          # Build production targets normally, then only the relevant test binary.
          postPatch = (old.postPatch or "") + ''
            substituteInPlace CMakeLists.txt \
              --replace-fail 'add_subdirectory(autotests)' 'add_subdirectory(autotests EXCLUDE_FROM_ALL)' \
              --replace-fail 'add_subdirectory(tests)' 'add_subdirectory(tests EXCLUDE_FROM_ALL)'
          '';
          postBuild = (old.postBuild or "") + ''
            cmake --build . --target testGlobalShortcuts --parallel "$NIX_BUILD_CORES"
          '';
          doCheck = true;
          checkPhase = ''
            runHook preCheck
            export XDG_RUNTIME_DIR="$TMPDIR/kwin-wheel-runtime"
            mkdir -m 700 "$XDG_RUNTIME_DIR"
            dbus-run-session --config-file=${previous.dbus}/share/dbus-1/session.conf \
              ./bin/testGlobalShortcuts testNavigationWheel
            runHook postCheck
          '';
        });
      });
    })
  ];
}
