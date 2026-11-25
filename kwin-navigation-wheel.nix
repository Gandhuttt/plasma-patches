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
          # to Meta+L/Meta+H for native previews and modifier-release activation.
          # Normal [TabBox] switching is unchanged.
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
          doCheck = true;
          checkPhase = ''
            runHook preCheck
            export XDG_RUNTIME_DIR="$TMPDIR/kwin-navigation-runtime"
            mkdir -m 700 "$XDG_RUNTIME_DIR"
            # Real native previews need KWin's EGL compositor, not just a
            # software Qt Quick backend. CI binds a readable /dev/udmabuf.
            export __EGL_VENDOR_LIBRARY_FILENAMES=${previous.mesa}/share/glvnd/egl_vendor.d/50_mesa.json
            export LIBGL_ALWAYS_SOFTWARE=1
            export FONTCONFIG_FILE=${previous.makeFontsConf { fontDirectories = [ previous.dejavu_fonts ]; }}
            # Separate compositor processes test opted-in and absent-option paths.
            # KWin initializes its linked KGlobalAccelD on this private bus; do not
            # launch an external daemon. WAYLANDTEST_MAIN selects KWin's own QPA.
            KWIN_TEST_NAVIGATION_GESTURES=1 \
              dbus-run-session --config-file=${previous.dbus}/share/dbus-1/session.conf \
              ./bin/testGlobalShortcuts testNavigationWheel testNavigationGestures \
                testNavigationGestureBoundaries testDefaultTouchpadGestures
            KWIN_TEST_NAVIGATION_GESTURES=0 \
              dbus-run-session --config-file=${previous.dbus}/share/dbus-1/session.conf \
              ./bin/testGlobalShortcuts testNavigationWheel testDefaultTouchpadGestures
            mkdir -p "$TMPDIR/kwin-tabbox-data/kwin/tabbox"
            ln -s "$PWD/../src/tabbox/switchers/thumbnail_grid" \
              "$TMPDIR/kwin-tabbox-data/kwin/tabbox/thumbnail_grid"
            XDG_DATA_DIRS="$TMPDIR/kwin-tabbox-data''${XDG_DATA_DIRS:+:$XDG_DATA_DIRS}" \
              QT_PLUGIN_PATH="$PWD/bin''${QT_PLUGIN_PATH:+:$QT_PLUGIN_PATH}" \
              QML_IMPORT_PATH="$PWD/bin''${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}" \
              QSG_RHI_BACKEND=opengl \
              dbus-run-session --config-file=${previous.dbus}/share/dbus-1/session.conf \
              gdb --batch --return-child-result -ex run -ex "thread apply all bt" \
              --args ./bin/testTabBox testTaskbarNavigation testTaskbarUpdates \
                testTaskbarProviders testTaskbarDesktopFilter testTaskbarDefaultMode \
                testMoveForward testMoveBackward
            runHook postCheck
          '';
        });
      });
    })
  ];
}
