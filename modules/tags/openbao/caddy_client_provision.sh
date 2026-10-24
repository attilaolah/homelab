bao policy write caddy-@node@ - <<'POLICY'
path "gocryptfs/data/@node@/mount-key" {
  capabilities = ["read"]
}
POLICY

# Roles trust the TPM cluster CA and constrain the DNS SAN. This avoids
# copying a Caddy private key or public certificate to a server.
bao write auth/cert/certs/caddy-@node@ \
  certificate=@"@tlsCa@" \
  allowed_dns_sans="@node@.node.@domain@" \
  policies=caddy-@node@ \
  token_ttl=1h \
  token_max_ttl=4h

if ! bao kv get -mount=gocryptfs @node@/mount-key >/dev/null 2>&1; then
  client_key=$(openssl rand -base64 48)
  bao kv put -mount=gocryptfs @node@/mount-key key="$client_key"
fi
