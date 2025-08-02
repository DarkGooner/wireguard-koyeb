FROM linuxserver/wireguard:latest AS wireguard_base

# Install qrencode, curl, python for fallback IP detection + minimal server.
RUN apk add --no-cache qrencode curl python3 \
    && ln -s /usr/bin/python3 /usr/bin/python

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 51821/udp            # WireGuard port
EXPOSE 8080/tcp             # HTTP server port

ENTRYPOINT ["/entrypoint.sh"]
