{pkgs, ...}: let
  inherit (pkgs.lib) getExe getExe';

  age-keygen = getExe' pkgs.age "age-keygen";
  sops = getExe pkgs.sops;
  test = getExe' pkgs.coreutils "test";

  age-file = "$DEVENV_ROOT/age.key";
  age-test = ''
    ${test} -f "${age-file}"
  '';
  have-age-file = {
    sh = age-test;
    msg = "SOPS Age key file not found; run age-keygen or age-restore-bw.";
  };
in {
  version = 3;

  tasks = {
    age-keygen = {
      desc = "Create a new Age key";
      cmd = "${age-keygen} --output ${age-file}";
      status = [age-test];
      silent = true;
    };

    age-restore-bw = {
      desc = "Restore the Age key from a Bitwarden vault";
      # NOTE: This uses the system `rbw` binary for compatibility with the agent.
      # To restore the SOPS Age key from Bitwarden, the operator needs to have `rbw` installed.
      cmd = "rbw login && rbw unlock && rbw get home_lab_age_key > ${age-file}";
      status = [age-test];
      silent = true;
    };

    encrypt-file = {
      internal = true;
      cmd = ''
        cd "$DEVENV_ROOT"
        ${sops} --encrypt --in-place "{{.file}}"
      '';
      requires.vars = ["file"];
      preconditions = [have-age-file];
      silent = true;
    };
  };
}
