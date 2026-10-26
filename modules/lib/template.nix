path: attrs:
builtins.replaceStrings
(map (name: "@${name}@") (builtins.attrNames attrs))
(builtins.attrValues attrs)
(builtins.readFile path)
