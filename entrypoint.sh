#!/usr/bin/env bash
set -euo pipefail

WG_IF="$WG_IFNAME"
WG_CONF="/etc/wireguard/${WG_IF}.conf"

# ENV: WG_SUBNET in CIDR (e.g. 10.13.13.0/24), WG_PORT (51820), WG_NUM_PEERS
# Optional: WG_ENDPOINT — if absent, auto‑detect via ifconfig.co

# Enable IPv4 forwarding
sysctl -q -w net.ipv4.ip_forward=1

# Calculate base IPs
read -r SUBNET_ADDR SUBNET_MASK <<< "$(echo $WG_SUBNET | sed 's|/| |')"
IFS=. read -r OA OB OC OD <<< "$SUBNET_ADDR"
SERVER_IP="${OA}.${OB}.${OC}.1/${SUBNET_MASK}"

# Auto detect external endpoint if not passed
if [[ -z "${WG_ENDPOINT:-}" ]]; then
  EXTERNAL_IP="$(curl -fs https://ifconfig.co || echo "")"
  if [[ -n $EXTERNAL_IP ]]; then
    WG_ENDPOINT="${EXTERNAL_IP}:${WG_PORT}"
  fi
fi

# Generate or consume server key
if [[ "$AUTOGEN_KEYS" == "true" || -z "${SERVER_PRIV:-}" ]]; then
  SERVER_PRIV="$(wg genkey)"
  SERVER_PUB="$(echo "$SERVER_PRIV" | wg pubkey)"
else
  SERVER_PUB="$(echo "$SERVER_PRIV" | wg pubkey)"
fi

cat > "$WG_CONF" <<EOF
[Interface]
Address = $SERVER_IP
ListenPort = $WG_PORT
PrivateKey = $SERVER_PRIV
SaveConfig = true
PostUp = iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PreDown = iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
EOF

# Add peers
for i in $(seq 1 $WG_NUM_PEERS); do
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

  cat > "/clients/client$i.conf" <<CFG
[Interface]
PrivateKey = $CLIENT_PRIV
Address = $CLIENT_IP
DNS = 1.1.1.1

[Peer]
PublicKey = $SERVER_PUB
PresharedKey = $CLIENT_PSK
Endpoint = $WG_ENDPOINT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
CFG
done

chmod 600 "$WG_CONF"
wg-quick up "$WG_IF"

# Web dashboard header
cat > /var/www/html/index.html <<HTML
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>${DASH_TITLE}</title>
</head>
<body>
<h1>${DASH_TITLE}</h1>
<p>Server public key: <code>${SERVER_PUB}</code></p>
<ul>
HTML

# QR & config links
for i in $(seq 1 $WG_NUM_PEERS); do
  QR_FILE="client${i}.png"
  CONF_FILE="client${i}.conf"
  qrencode -o "/var/www/html/${QR_FILE}" < "/clients/${CONF_FILE}"
  cp "/clients/${CONF_FILE}" "/var/www/html/${CONF_FILE}"
  cat >> /var/www/html/index.html <<ITEM
<li>Peer ${i}: <a href="${CONF_FILE}" download>Download .conf</a><br>
<img src="${QR_FILE}" alt="QR for client${i}" style="max-width:300px;"></li>
ITEM

  if [[ "$SHOW_ANSI_QR" == "true" ]]; then
    echo "Peer${i} QR:"
    qrencode -t ansiutf8 < "/clients/${CONF_FILE}"
  fi
done

echo "</ul></body></html>" >> /var/www/html/index.html

exec nginx -g "daemon off;"
