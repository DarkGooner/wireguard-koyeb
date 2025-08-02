#!/usr/bin/env bash
set -euo pipefail

WG_IF="${WG_IFNAME:-wg0}"
WG_CONF="/etc/wireguard/$WG_IF.conf"
WG_PORT="${WG_PORT:-51820}"
WG_NUM_PEERS="${WG_NUM_PEERS:-1}"

# Enable IPv4 forwarding + NAT rules
sysctl -q -w net.ipv4.ip_forward=1  >/dev/null

SERVER_PRIV="${SERVER_PRIVKEY:-}"
AUTOGEN="${AUTOGEN_KEYS:-true}"

if [ "$AUTOGEN" = "true" ] || [ -z "${SERVER_PRIV}" ]; then
  SERVER_PRIV="$(wg genkey)"
  SERVER_PUB="$(echo "$SERVER_PRIV" | wg pubkey)"
else
  SERVER_PUB="$(echo "$SERVER_PRIV" | wg pubkey)"
fi

cat > "$WG_CONF" <<EOF
[Interface]
Address = ${SERVER_IP:-10.13.13.1}/24
ListenPort = $WG_PORT
PrivateKey = $SERVER_PRIV
SaveConfig = true
PostUp = iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PreDown = iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
EOF

##### – Insert the WG_ENDPOINT block from above patch here – #####

for i in $(seq 1 "$WG_NUM_PEERS"); do
  # … generate clients like before …
done

chmod 600 "$WG_CONF"
wg-quick up "$WG_IF"

cat > /var/www/html/index.html <<HTML
<!DOCTYPE html><html><body>
<h1>WireGuard VPN</h1><p>Server: ${SERVER_PUB}</p><ul>
HTML

for i in $(seq 1 "$WG_NUM_PEERS"); do
  qrencode -t png -o "/var/www/html/client${i}.png" < "/clients/client${i}.conf"
  cp "/clients/client${i}.conf" "/var/www/html/client${i}.conf"
  cat >> /var/www/html/index.html <<ITEM
<li>Peer${i}: <a href="client${i}.conf">DOWNLOAD</a><br>
<img src="client${i}.png" style="max-width:200px;"></li>
ITEM
done

echo "</ul></body></html>" >> /var/www/html/index.html
exec nginx -g "daemon off;"
