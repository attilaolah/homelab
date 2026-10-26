#!/usr/bin/env bash

set -euo pipefail

lan_interface="$(ip -o -4 addr show | awk -v address="${HOST_IP}/24" '$4 == address { print $2; exit }')"
if [[ -z "$lan_interface" ]]; then
  echo "Could not find the LAN interface for ${HOST_IP}" >&2
  exit 1
fi

cat > /run/keepalived/keepalived.conf <<EOF
global_defs {
  max_auto_priority
  enable_script_security
  script_user keepalived_script keepalived_script
}

vrrp_script caddy {
  script "$CADDY_VRRP_HEALTH_CHECK"
  interval 2
  timeout 2
  fall 2
  rise 2
  weight -100
}
vrrp_instance CADDY {
  state $VRRP_STATE
  interface $lan_interface
  virtual_router_id 51
  priority $VRRP_PRIORITY
  advert_int 1
  virtual_ipaddress {
    $VIRTUAL_IP/24 dev $lan_interface
  }
  track_script {
    caddy
  }
}
EOF
