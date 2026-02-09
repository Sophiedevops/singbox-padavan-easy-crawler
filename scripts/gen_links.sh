#!/bin/sh
# ==================== gen_links.sh (без VLESS) ====================

WORKDIR="/opt/tmp_sb_ext/sing-box-1.12.12-extended-1.5.1-linux-mipsle"
CONF="$WORKDIR/conf2_final.json"
OUT_FILE="$WORKDIR/clients.txt"
SERVER_IP="192.168.1.1"                     # ← поменяй на внешний IP если нужно

echo "Generating links (без VLESS) → $OUT_FILE"
echo "" > "$OUT_FILE"

# base64 через openssl
b64enc() {
    echo -n "$1" | openssl base64 -A 2>/dev/null | tr -d '\n\r'
}

# ====================== 1. ShadowTLS ======================
echo "--- ShadowTLS ---"
jq -c '.inbounds[] | select(.type=="shadowtls")' "$CONF" | while read -r line; do
    TAG=$(echo "$line" | jq -r '.tag')
    PORT=$(echo "$line" | jq -r '.listen_port')
    PASS=$(echo "$line" | jq -r '.users[0].password')
    HOST=$(echo "$line" | jq -r '.handshake.server // "icloud.com"')
    
    LINK="shadowtls://$PASS@$SERVER_IP:$PORT?version=3&host=$HOST#$TAG"
    echo "$LINK"
    echo "$LINK" >> "$OUT_FILE"
done

# ====================== 2. Shadowsocks ======================
echo "--- Shadowsocks ---"
jq -c '.inbounds[] | select(.type=="shadowsocks")' "$CONF" | while read -r line; do
    TAG=$(echo "$line" | jq -r '.tag')
    PORT=$(echo "$line" | jq -r '.listen_port')
    METHOD=$(echo "$line" | jq -r '.method')
    PASS=$(echo "$line" | jq -r '.password')
    
    AUTH=$(b64enc "$METHOD:$PASS")
    LINK="ss://$AUTH@$SERVER_IP:$PORT#$TAG"
    echo "$LINK"
    echo "$LINK" >> "$OUT_FILE"
done

# ====================== 3. Hysteria 2 ======================
echo "--- Hysteria 2 ---"
jq -c '.inbounds[] | select(.type=="hysteria2")' "$CONF" | while read -r line; do
    TAG=$(echo "$line" | jq -r '.tag')
    PORT=$(echo "$line" | jq -r '.listen_port')
    PASS=$(echo "$line" | jq -r '.users[0].password')
    
    LINK="hy2://$PASS@$SERVER_IP:$PORT?insecure=1#$TAG"
    echo "$LINK"
    echo "$LINK" >> "$OUT_FILE"
done

echo ""
echo "Готово! Ссылки (без VLESS) сохранены в $OUT_FILE"
