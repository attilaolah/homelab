let
  inherit (builtins) attrNames elem mapAttrs;

  # ALL machines need to be registered here.
  # Numbers are used to build the network suffix, i.e. 8 -> 192.168.1.8.
  ids = {
    acer = 121;
    aloe = 116;
    aria = 102;
    hoya = 104;
    ilex = 103;
    inga = 105;
    iris = 101;
    rosa = 120;
    sida = 122;
    unio = 117;
  };

  # Additional tags per machine.
  tags = {
    # Machines running the Smallstep ACME server.
    # Only machines with TPM 1.2 hardware can be added here.
    # Currently only a single instance until the backing database is upgraded.
    acme = [
      "acer"
    ];
    # Machines running the Lego ACME client.
    # Only machines with no TPM hardware should be added here.
    # Machines with TPM hardware will already provision a certificate using the local intermediate CA.
    acme_client = [
      "aloe"
      "aria"
      "ilex"
      "rosa"
      "sida"
      "unio"
    ];
    # Machines currently being bootstrapped into the "acme_client" tag.
    # The workflow is: add to acme_client_bootstrap, deploy, add to acme_client, provision, deploy.
    acme_client_bootstrap = [
    ];
    # Laptops that require special config to keep them awake when the lid is closed.
    laptop = [
      "acer"
      "rosa"
      "sida"
    ];
    # Machines with TPM 1.2 hardware (now considered legacy).
    # These will have an intermediate CA and can issue short-lived leaf certificates.
    tpm12 = [
      "acer"
      "hoya"
      "inga"
      "iris"
    ];
    # Machines currently being bootstrapped into the "tpm12" tag.
    # The workflow is: add to tpm12_bootstrap, deploy, configure, add to tpm12, provision, deploy.
    tpm12_bootstrap = [
    ];
    # Machines with a hardware watchdog device.
    # Systemd will be configured on these devices to pet the watchdog.
    watchdog = [
      "acer"
      "hoya"
      "inga"
      "iris"
      "rosa"
    ];
  };

  # Machines that are on the internal network.
  # These should eventually be moved to the external network after initial setup.
  internal = [
  ];

  ip4 = x: y: "192.168.${toString x}.${toString y}";

  machines =
    mapAttrs (name: id: let
      lan =
        if elem name internal
        then 0
        else 1;
      ip = ip4 lan id;
    in {
      inherit ip;

      tags = builtins.filter (tag: elem name tags.${tag}) (attrNames tags);
    })
    ids;
in {
  inherit ids internal machines tags;
}
