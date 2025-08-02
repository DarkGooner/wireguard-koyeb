#!/usr/bin/env bash
set -euo pipefail

# Required env: PEERS, CHILD_IF (e.g. eth0), WG_PORT (defaults to 51821)
PEERS="${PEERS:-1}"
CHILD_IF="${CHILD_IF:-eth0}"
WG_PORT="${WG_PORT:-51821}"
WG_IF="wg0"

# Use Koyeb's runtime domain if available, else fallback to external IP detection
if [ -n "${KOYEB_PUBLIC_DOMAIN:-}" ]; then
  ENDPOINT="${KOYEB_PUBLIC_DOMAIN}:${WG_PORT}"
  echo "📡 Using Koyeb public domain: $ENDPOINT"
else
  echo "No KOYEB_PUBLIC_DOMAIN – trying external IP lookup..."
  if ! host_ip="$(curl -4s ifconfig.me/ip || curl -4s ipinfo.io/ip)"; then
    echo "❌ Failed to detect public IP; set WG_ENDPOINT manually"
    exit 1
  fi
  ENDPOINT="${host_ip}:${WG_PORT}"
  echo "🌐 Detected public IP endpoint: $ENDPOINT"
fi

# Export to container for wg config
export SERVERURL="$ENDPOINT"

# Enable IPv4 forwarding (necessary for router/NAT mode)
if [ "$(id -u)" = "0" ]; then
  echo "Enabling IPv4 forwarding"
  sysctl -w net.ipv4.ip_forward=1 || :
  iptables -t nat -A POSTROUTING -o "${CHILD_IF}" -j MASQUERADE
fi

# Set environment variables for linuxserver/wireguard
export PEERS
export PUBLIC_IP="$host_ip"
export SERVERPORT="$WG_PORT"
export INTERNAL_SUBNET="${INTERNAL_SUBNET:-10.13.13.0/24}"
export PEERDNS="${PEERDNS:-auto}"
export LOG_CONFS="true"
export ENDPOINT
export LOG_QUICK="true"

# Start WireGuard daemon in background
echo "Starting WireGuard server…"
exec /init
