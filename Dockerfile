# === WireGuard + Web Dashboard (QR & config) ===
FROM debian:stable-slim

ENV DEBIAN_FRONTEND=noninteractive \
    WG_IFNAME=wg0 \
    WG_SUBNET=10.13.13.0/24 \
    WG_PORT=51820 \
    WG_NUM_PEERS=1 \
    AUTOGEN_KEYS="true" \
    SHOW_ANSI_QR="true" \
    DASH_TITLE="WireGuard VPN 🌐"

# Install packages
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        wireguard-tools iproute2 qrencode procps curl nginx && \
    rm -rf /var/lib/apt/lists/*

# Directory layout
RUN mkdir -p /etc/wireguard /clients /var/www/html

# Add entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 80/tcp 51820/udp

ENTRYPOINT ["/entrypoint.sh"]
