{k, ...}:
k.external-secret ./. {
  name = k.appname ./.;
  data.password = "{{ .redis_oauth_db_password }}";
}
