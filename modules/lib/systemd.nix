{lib}: attrs:
lib.mapAttrsToList (name: value: "name=${toString value}") attrs
