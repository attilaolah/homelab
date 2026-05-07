{}: final: _prev: {
  acme-eab-write = final.buildGoModule {
    pname = "acme-eab-write";
    version = final.step-ca.version;

    src = final.runCommand "acme-eab-write-src" {} ''
      cp -R --no-preserve=mode,ownership ${final.step-ca.src}/. "$out"
      mkdir -p "$out/cmd/acme-eab-write"
      cp ${../tools/acme_eab_write/main.go} "$out/cmd/acme-eab-write/main.go"
    '';

    vendorHash = final.step-ca.vendorHash;

    subPackages = ["cmd/acme-eab-write"];
  };
}
