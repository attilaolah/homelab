{
  # Reduce closure/store size on this server.
  documentation.enable = false;

  # Keep only a small number of bootable generations.
  boot.loader.grub.configurationLimit = 5;

  # Periodically reclaim and deduplicate store space.
  nix = {
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 14d";
    };
    settings.auto-optimise-store = true;
  };

  # Trim locale data to a single UTF-8 locale.
  i18n = let
    coding = "UTF-8";
    defaultLocale = "en_US.${coding}";
  in {
    inherit defaultLocale;
    supportedLocales = ["${defaultLocale}/${coding}"];
  };
}
