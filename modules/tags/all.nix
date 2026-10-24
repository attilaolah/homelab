{
  lib,
  pkgs,
  config,
  inputs,
  ...
}: let
  pki = import (inputs.self + /modules/lib/pki.nix);
  machineData = import (inputs.self + /inventory/data.nix);
  template = import (inputs.self + /modules/lib/template.nix);

  crt = pki.cluster.ca.crt;
  key = pki.cluster.ca.key;
  cagen = pki.cluster.ca.gen;

  acmeHosts = builtins.listToAttrs (map (machine: lib.nameValuePair machine machine) machineData.tags.acme);
  lanHosts =
    lib.mapAttrs'
    (name: machine: lib.nameValuePair machine.ip [name "${name}.node.${config.networking.domain}"])
    machineData.machines;
  disabled.enable = lib.mkForce false;
in {
  options.homelab.lan.ip4 = lib.mkOption {
    type = lib.types.str;
    description = "Primary LAN IPv4 address for this machine.";
  };
  options.homelab.acme.hosts = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    description = "ACME endpoint hostnames mapped to machine names.";
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
      script = template ./tls_ca_generate.sh {
        certificateFile = crt;
        domain = config.networking.domain;
        keyFile = key;
      };
    };

    security.pki.certificateFiles = [
      config.clan.core.vars.generators.${cagen}.files.${crt}.path
    ];

    networking = {
      hosts =
        lanHosts
        // lib.mapAttrs'
        (name: machine: let
          ip = machineData.machines.${machine}.ip;
        in
          lib.nameValuePair ip (lanHosts.${ip} ++ ["${name}.acme.${config.networking.domain}"]))
        acmeHosts;
      nftables = {
        enable = true;
        tables.homelab = {
          family = "inet";
          content = ''
            chain input {
              type filter hook input priority filter - 1; policy accept;
              ip saddr 192.168.1.1 drop
            }
          '';
        };
      };
      firewall.backend = "nftables";
    };

    users.groups.tls = {};

    systemd.tmpfiles.rules = [
      "d ${pki.tls.dir} 0750 root tls - -"
    ];

    # Reduce closure/store size.
    documentation.enable = false;

    boot = {
      # Follow the latest stable kernel.
      kernelPackages = pkgs.linuxPackages_latest;
      # Keep only a small number of bootable generations.
      # Some nodes have too small disks, limiting how many kernel images + module sets can be kept.
      loader.grub.configurationLimit = 3;
    };

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
