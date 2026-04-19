{
  lib,
  pkgs,
  ...
}: let
  disabled.enable = lib.mkForce false;
in {
  # Reduce closure/store size.
  documentation.enable = false;

  # Keep only a small number of bootable generations.
  boot.loader.grub.configurationLimit = 3;

  # Periodically reclaim and deduplicate store space.
  nix = {
    gc = {
      automatic = true;
      dates = "daily";
      options = "--delete-older-than 8d";
    };
    settings.auto-optimise-store = true;
  };
  # Avoid pinning nixpkgs source into system closure via global flake registry/NIX_PATH.
  nixpkgs.flake = {
    setFlakeRegistry = false;
    setNixPath = false;
  };

  # Trim locale data to a single UTF-8 locale.
  i18n = let
    coding = "UTF-8";
    defaultLocale = "en_US.${coding}";
  in {
    inherit defaultLocale;
    supportedLocales = ["${defaultLocale}/${coding}"];
  };

  # Keep all machines headless even if hardware fact data includes a display.
  hardware.graphics = disabled;
  fonts.fontconfig = disabled;

  # Avoid XDG data in the system closure on all hosts.
  xdg = {
    icons = disabled;
    mime = disabled;
    sounds = disabled;
  };

  # Hosts are managed remotely, omit installer/rebuild helper tools.
  system.disableInstallerTools = true;
  environment.defaultPackages = lib.mkForce [];

  # D-Bus defaults to X11 autolaunch support.
  services.dbus.dbusPackage = pkgs.dbus.override {x11Support = false;};
}
