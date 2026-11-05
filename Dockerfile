# syntax=docker/dockerfile:1
# Xray (VLESS) with WebSocket + XHTTP on ONE public port, via Caddy path routing.
# Intended for platforms that terminate TLS and forward plain HTTP to $PORT
# (Railway, Render, Fly, behind a CDN, ...).
#
# Environment variables:
#   UUID     client id (SET THIS, otherwise a random one is generated on every start)
#   DOMAIN   your public domain, used only to print ready-made client links
#   WS_PATH  default /ws
#   XH_PATH  default /xh
#   PORT     provided by the platform (default 8080)

FROM alpine:3.20

RUN apk add --no-cache curl unzip ca-certificates caddy \
 && curl -fsSL -o /tmp/xray.zip https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip \
 && unzip -o /tmp/xray.zip xray geoip.dat geosite.dat -d /usr/local/bin \
 && chmod +x /usr/local/bin/xray \
 && rm /tmp/xray.zip

RUN <<'EOF' cat > /entry.sh
#!/bin/sh
set -e
export PORT="${PORT:-8080}"
export WS_PATH="${WS_PATH:-/ws}"
export XH_PATH="${XH_PATH:-/xh}"
export UUID="${UUID:-$(cat /proc/sys/kernel/random/uuid)}"
DOMAIN="${DOMAIN:-YOUR.DOMAIN}"

cat > /etc/xray.json <<JSON
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "tag": "ws-in",
      "listen": "127.0.0.1",
      "port": 10001,
      "protocol": "vless",
      "settings": { "clients": [ { "id": "${UUID}" } ], "decryption": "none" },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "${WS_PATH}" }
      }
    },
    {
      "tag": "xhttp-in",
      "listen": "127.0.0.1",
      "port": 10002,
      "protocol": "vless",
      "settings": { "clients": [ { "id": "${UUID}" } ], "decryption": "none" },
      "streamSettings": {
        "network": "xhttp",
        "xhttpSettings": { "path": "${XH_PATH}", "mode": "auto" }
      }
    }
  ],
  "outbounds": [ { "protocol": "freedom" } ]
}
JSON

cat > /etc/Caddyfile <<CADDY
{
  admin off
  auto_https off
}
:${PORT} {
  handle ${WS_PATH}* {
    reverse_proxy 127.0.0.1:10001
  }
  handle ${XH_PATH}* {
    reverse_proxy 127.0.0.1:10002 {
      flush_interval -1
    }
  }
  handle {
    respond "OK" 200
  }
}
CADDY

echo "=============== CLIENT LINKS ==============="
echo "vless://${UUID}@${DOMAIN}:443?encryption=none&security=tls&type=ws&host=${DOMAIN}&path=${WS_PATH}&sni=${DOMAIN}&fp=chrome&alpn=http/1.1#WS"
echo "vless://${UUID}@${DOMAIN}:443?encryption=none&security=tls&type=xhttp&mode=packet-up&host=${DOMAIN}&path=${XH_PATH}&sni=${DOMAIN}&fp=chrome&alpn=h2%2Chttp/1.1#XHTTP"
echo "============================================="

xray run -c /etc/xray.json &
exec caddy run --config /etc/Caddyfile --adapter caddyfile
EOF

RUN chmod +x /entry.sh
EXPOSE 8080
CMD ["/entry.sh"]
