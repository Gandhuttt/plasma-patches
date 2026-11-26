{ lib, ... }:
{
  # Opt in per user in kwinrc: [MouseBindings] NavigationWheel=true and/or
  # [Touchpad] NavigationGestures=true. Native recognition leaves scroll intact.
  nixpkgs.overlays = [
    (_final: previous: {
      kdePackages = previous.kdePackages.overrideScope (_kfinal: kprevious: {
        kwin = kprevious.kwin.overrideAttrs (old: {
          # [TabBoxAlternative] SwitchingMode=2 uses live taskbar UUID order and
          # bounded navigation. Bind Walk Through Windows Alternative/Reverse
          # to Meta+L/Meta+H: each selection focuses immediately, and Escape
          # restores the original window. Normal [TabBox] switching is unchanged.
          outputs = old.outputs ++ [ "tests" ];
          patches = (old.patches or [ ]) ++ [
            ./kwin-navigation-wheel.patch
            ./kwin-navigation-wheel-tests.patch
            ./kwin-taskbar-switcher.patch
          ];
          cmakeFlags = builtins.filter
            (flag: !lib.hasPrefix "-DBUILD_TESTING" flag)
            (old.cmakeFlags or [ ]) ++ [ "-DBUILD_TESTING=ON" ];
          buildInputs = (old.buildInputs or [ ]) ++ [ kprevious.kwayland ];
          nativeCheckInputs = (old.nativeCheckInputs or [ ]) ++ [ previous.dbus previous.gdb ];
          # Build production targets normally, then only the relevant test binary.
          postPatch = (old.postPatch or "") + ''
            substituteInPlace CMakeLists.txt \
              --replace-fail 'add_subdirectory(autotests)' 'add_subdirectory(autotests EXCLUDE_FROM_ALL)' \
              --replace-fail 'add_subdirectory(tests)' 'add_subdirectory(tests EXCLUDE_FROM_ALL)'
          '';
          postBuild = (old.postBuild or "") + ''
            cmake --build . --target testGlobalShortcuts testTabBox --parallel "$NIX_BUILD_CORES"
          '';
          # GitHub's hosted kernel lacks udmabuf. Run these real compositor
          # integration tests separately on a machine with a render device.
          doCheck = false;
          postInstall = (old.postInstall or "") + ''
            mkdir -p "$tests/bin" "$tests/share/kwin/tabbox"
            cp bin/testGlobalShortcuts bin/testTabBox "$tests/bin/"
            # Test executables link to the just-built libkwin. Replace build
            # tree RPATH entries with the installed library before Nix fixup.
            for binary in "$tests/bin/"*; do
              IFS=: read -r -a paths <<< "$(patchelf --print-rpath "$binary")"
              rpath="$out/lib"
              for path in "''${paths[@]}"; do
                [[ "$path" == /build/* || -z "$path" ]] || rpath="$rpath:$path"
              done
              patchelf --set-rpath "$rpath" "$binary"
            done
            cp -r ../src/tabbox/switchers/thumbnail_grid "$tests/share/kwin/tabbox/"
          '';
        });
      });
    })
  ];
}
