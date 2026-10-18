{lib}: attrs:
lib.mapAttrsToList (name: value: "${lib.toUpper name}=${toString value}") attrs
