{pkgs, ...}: let
  silent = true;
  age-file = "$DEVENV_ROOT/age.key";
  writeShellApplication = inputs: let
    name = "sops-task";
    params = inputs // {inherit name;};
  in "${pkgs.writeShellApplication params}/bin/${name}";

  have-age-file = {
    sh = writeShellApplication {
      runtimeInputs = with pkgs; [coreutils];
      text = ''
        test -f "${age-file}"
      '';
    };
    msg = "SOPS Age key file not found; run sops:age-keygen or sops:age-restore-bw.";
  };
in {
  version = 3;

  tasks = {
    age-keygen = {
      inherit silent;
      desc = "Create a new Age key";
      status = [have-age-file.sh];
      cmd = writeShellApplication {
        runtimeInputs = with pkgs; [age];
        text = ''
          age-keygen --output "${age-file}"
        '';
      };
    };

    age-restore-bw = {
      inherit silent;
      desc = "Restore the Age key from a Bitwarden vault";
      status = [have-age-file.sh];
      cmd = writeShellApplication {
        runtimeInputs = with pkgs; [rbw];
        text = ''
          rbw login
          rbw unlock
          rbw get home_lab_age_key > "${age-file}"
        '';
      };
    };

    encrypt-file = {
      inherit silent;
      internal = true;
      cmd = let
        cmd = writeShellApplication {
          runtimeInputs = with pkgs; [age];
          text = ''
            file="$1"

            cd "$DEVENV_ROOT"
            sops --encrypt --in-place "$file"
            age-keygen --output "${age-file}"
          '';
        };
      in ''"${cmd}" "{{.file}}"'';
      requires.vars = ["file"];
      preconditions = [have-age-file];
    };
  };
}
