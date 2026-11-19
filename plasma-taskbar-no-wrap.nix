{ ... }:
{
  # Read the live task model instead of animated delegates/icon geometry.
  # Preserve manual task order, but stop previous/next actions at either end.
  nixpkgs.overlays = [
    (_final: previous: {
      kdePackages = previous.kdePackages.overrideScope (_kfinal: kprevious: {
        plasma-desktop = kprevious.plasma-desktop.overrideAttrs (old: {
          patches = (old.patches or [ ]) ++ [ ./plasma-taskbar-no-wrap.patch ];
        });
      });
    })
  ];
}
