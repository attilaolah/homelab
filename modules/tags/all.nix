{
  lib,
  pkgs,
  config,
  inputs,
  ...
}: let
  b = "ca";
  crt = "${b}.crt";
  key = "${b}.key";
  cagen = "tls-ca";

  machineData = import (inputs.self + /inventory/data.nix);
  acmeHosts =
    builtins.listToAttrs
    (map (machine: lib.nameValuePair "${machine}.acme" machine) machineData.tags.acme);
  lanHosts =
    lib.mapAttrs'
    (name: machine: lib.nameValuePair machine.ip [(fqdn name)])
    machineData.machines;
  acmeLanHosts =
    lib.mapAttrs'
    (name: machine: let
      ip = machineData.machines.${machine}.ip;
    in
      lib.nameValuePair ip (lanHosts.${ip} ++ [(fqdn name)]))
    acmeHosts;
  fqdn = name: "${name}.${config.networking.domain}";
  disabled.enable = lib.mkForce false;
in {
  options.homelab.lan.ip4 = lib.mkOption {
    type = lib.types.str;
    description = "Primary LAN IPv4 address for this machine.";
  };
  options.homelab.acme.hosts = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    description = "ACME endpoint host aliases mapped to machine names.";
  };

  config = {
    homelab.acme.hosts = acmeHosts;
    homelab.lan.ip4 = machineData.machines.${config.networking.hostName}.ip;

    clan.core.vars.generators.${cagen} = {
      share = true;
      files.${key} = {
        secret = true;
        deploy = false;
      };
      files.${crt} = {
        secret = false;
        deploy = false;
      };
      runtimeInputs = with pkgs; [step-cli];
      script = ''
        step certificate create "TLS CA: ${config.networking.domain}" "$out/${crt}" "$out/${key}" \
          --profile root-ca \
          --kty EC \
          --curve P-256 \
          --no-password \
          --insecure
      '';
    };

    security.pki.certificateFiles = [
      config.clan.core.vars.generators.${cagen}.files.${crt}.path
    ];

    networking.hosts = lanHosts // acmeLanHosts;
    networking.firewall.extraCommands = lib.mkAfter ''
      iptables -I nixos-fw 1 -s 192.168.1.1 -j DROP
    '';

    users.groups.tls = {};

    systemd.tmpfiles.rules = [
      "d /run/pki/tls 0750 root tls - -"
    ];

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

    services = {
      # D-Bus defaults to X11 autolaunch support.
      dbus.dbusPackage = pkgs.dbus.override {x11Support = false;};
      openssh.startWhenNeeded = true;
    };
  };
}
