#!/usr/bin/env bash
set -euo pipefail

# Default values (safely handle unset vars)
WG_IF="${WG_IFNAME:-wg0}"
WG_PORT="${WG_PORT:-51820}"
WG_NUM_PEERS="${WG_NUM_PEERS:-1}"       # default 1 peer
SERVER_PRIV="${SERVER_PRIVKEY:-}"
AUTOGEN="${AUTOGEN_KEYS:-true}"
SHOW_ANSI_QR="${SHOW_ANSI_QR:-true}"
WG_SUBNET="${WG_SUBNET:-10.13.13.0/24}"

# Enable NAT + forwarding
sysctl -q -w net.ipv4.ip_forward=1 >/dev/null

# Compute server address
read -r SUBNET_ADDR SUBNET_MASK <<< "${WG_SUBNET//\// }"
IFS=. read -r OA OB OC OD <<< "$SUBNET_ADDR"
SERVER_IP="${OA}.${OB}.${OC}.1/${SUBNET_MASK}"

# Auto-discover endpoint if not set
if [[ -n "${WG_ENDPOINT:-}" ]]; then
  ENDPOINT="${WG_ENDPOINT//\/\//}:${WG_PORT}"
else
  if ext=$(curl -fs https://ifconfig.co/ip); then
    ENDPOINT="${ext}:${WG_PORT}"
    echo "Auto-discovered endpoint IP: $ENDPOINT"
  else
    echo "❌ WG_ENDPOINT unset and public IP lookup failed – exiting."
    exit 1
  fi
fi

# Generate server key pair if needed
if [[ "$AUTOGEN" == "true" || -z "${SERVER_PRIV}" ]]; then
  SERVER_PRIV="$(wg genkey)"
fi
SERVER_PUB="$(echo "$SERVER_PRIV" | wg pubkey)"

WG_CONF="/etc/wireguard/${WG_IF}.conf"
cat > "$WG_CONF" <<EOF
[Interface]
Address = $SERVER_IP
ListenPort = $WG_PORT
PrivateKey = $SERVER_PRIV
SaveConfig = true
PostUp = iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PreDown = iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
EOF

mkdir -p /clients

# ✅ Fixed loop with correct `do` and matching `done`
for i in $(seq 1 "$WG_NUM_PEERS"); do
  CLIENT_PRIV="$(wg genkey)"
  CLIENT_PUB="$(echo "$CLIENT_PRIV" | wg pubkey)"
  CLIENT_PSK="$(wg genpsk)"
  CLIENT_IP="${OA}.${OB}.${OC}.$((OD + i))/32"

  cat >> "$WG_CONF" <<PEER
[Peer]
PublicKey = $CLIENT_PUB
PresharedKey = $CLIENT_PSK
AllowedIPs = ${CLIENT_IP%/*}/32
PEER

  cat > "/clients/client${i}.conf" <<CFG
[Interface]
PrivateKey = $CLIENT_PRIV
Address = $CLIENT_IP
DNS = 1.1.1.1

[Peer]
PublicKey = $SERVER_PUB
PresharedKey = $CLIENT_PSK
Endpoint = $ENDPOINT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
CFG
done  # <— closing the loop correctly with `done`

chmod 600 "$WG_CONF"
wg-quick up "$WG_IF"

# Generate dashboard
mkdir -p /var/www/html
cat > /var/www/html/index.html <<HTML
<!DOCTYPE html>
<html lang="en">
<head><meta charset="UTF-8"><title>WireGuard Peers</title></head>
<body>
  <h1>WireGuard Server</h1>
  <p>Server public key: <code>$SERVER_PUB</code></p>
  <ul>
HTML

for i in $(seq 1 "$WG_NUM_PEERS"); do
  cp "/clients/client${i}.conf" "/var/www/html/client${i}.conf"
  qrencode -o "/var/www/html/client${i}.png" < "/clients/client${i}.conf"
  cat >> /var/www/html/index.html <<ITEM
    <li>Peer ${i}: <a href="client${i}.conf">Download</a><br>
    <img src="client${i}.png" style="max-width:200px;"></li>
ITEM

  if [[ "$SHOW_ANSI_QR" == "true" ]]; then
    qrencode -t ansiutf8 < "/clients/client${i}.conf"
  fi
done

cat >> /var/www/html/index.html <<HTML
  </ul>
</body>
</html>
HTML

exec nginx -g "daemon off;"
