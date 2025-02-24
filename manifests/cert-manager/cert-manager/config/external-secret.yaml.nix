{k, ...}:
map (params: k.external-secret ./. params) [
  {
    name = "internal-ca";
    data = {
      "tls.crt" = ''
        -----BEGIN CERTIFICATE-----
        MIIBfDCCASGgAwIBAgIUAKWNK6X9aqbagqqII+9YFQsrjh0wCgYIKoZIzj0EAwIw
        EzERMA8GA1UEAwwIZG9ybmhhdXMwHhcNMjUwMjIzMjIxMTExWhcNMjYwMjIzMjIx
        MTExWjATMREwDwYDVQQDDAhkb3JuaGF1czBZMBMGByqGSM49AgEGCCqGSM49AwEH
        A0IABPb3/s93CW5xumhDjycvuZ7QgW7+eKQemDCYG4Jqvgpo4/End5YUYJugHXVX
        990Fx0IILD4+YoET54JoeDM3Q0KjUzBRMB0GA1UdDgQWBBT7rK+mWwV5l8yHIP9c
        jz3FePt3DjAfBgNVHSMEGDAWgBT7rK+mWwV5l8yHIP9cjz3FePt3DjAPBgNVHRMB
        Af8EBTADAQH/MAoGCCqGSM49BAMCA0kAMEYCIQDHJf1NNM/ihoMRj6zVn1I698QK
        D7VMDmPzsEWbk/U73gIhAIw36mZqai+Dxlk5me9wZOTtD2yvM4NABCpavoo/McLs
        -----END CERTIFICATE-----
      '';
      "tls.key" = "{{ .internal_ca_key | b64dec }}";
    };
    spec.target.template.type = "kubernetes.io/tls";
  }
  {
    name = "cloudflare-api-token";
    data.api-token = "{{ .cloudflare_api_token }}";
  }
]
