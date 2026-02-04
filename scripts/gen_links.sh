#!/bin/sh

WORKDIR="/opt/tmp_sb_ext/sing-box-1.12.12-extended-1.5.1-linux-mipsle"
CONF="$WORKDIR/conf2_final.json"
OUT_FILE="$WORKDIR/clients.txt"
SERVER_IP="192.168.1.1"

echo "Generating links for server: $SERVER_IP"
echo "" > "$OUT_FILE"

# --- 1. SHADOWSOCKS ---
echo "--- Shadowsocks ---"
jq -c '.inbounds[] | select(.type=="shadowsocks")' "$CONF" | while read -r line; do
    TAG=$(echo "$line" | jq -r '.tag')
    PORT=$(echo "$line" | jq -r '.listen_port')
    PASS=$(echo "$line" | jq -r '.password')
    METHOD=$(echo "$line" | jq -r '.method')
    
    # Кодируем (method:password)
    AUTH=$(echo -n "$METHOD:$PASS" | base64 | tr -d '\n')
    LINK="ss://$AUTH@$SERVER_IP:$PORT#$TAG"
    
    echo "$LINK"
    echo "$LINK" >> "$OUT_FILE"
done

# --- 2. VLESS ---
echo "--- VLESS ---"
jq -c '.inbounds[] | select(.type=="vless")' "$CONF" | while read -r line; do
    TAG=$(echo "$line" | jq -r '.tag')
    PORT=$(echo "$line" | jq -r '.listen_port')
    UUID=$(echo "$line" | jq -r '.users[0].uuid')
    FLOW=$(echo "$line" | jq -r '.users[0].flow // empty')
    
    PBK=$(echo "$line" | jq -r '.tls.reality.public_key // empty')
    SNI=$(echo "$line" | jq -r '.tls.server_name // empty')
    FP=$(echo "$line" | jq -r '.tls.reality.fingerprint // empty')
    SID=$(echo "$line" | jq -r '.tls.reality.short_id[0] // empty')
    TYPE=$(echo "$line" | jq -r '.transport.type // "tcp"')
    
    PARAMS="security=reality&type=$TYPE"
    if [ ! -z "$PBK" ]; then PARAMS="$PARAMS&pbk=$PBK"; fi
    if [ ! -z "$SNI" ]; then PARAMS="$PARAMS&sni=$SNI"; fi
    if [ ! -z "$FP" ]; then PARAMS="$PARAMS&fp=$FP"; fi
    if [ ! -z "$SID" ]; then PARAMS="$PARAMS&sid=$SID"; fi
    if [ ! -z "$FLOW" ]; then PARAMS="$PARAMS&flow=$FLOW"; fi

    LINK="vless://$UUID@$SERVER_IP:$PORT?$PARAMS#$TAG"
    
    echo "$LINK"
    echo "$LINK" >> "$OUT_FILE"
done

# --- 3. VMESS ---
echo "--- VMESS ---"
jq -c '.inbounds[] | select(.type=="vmess")' "$CONF" | while read -r line; do
    TAG=$(echo "$line" | jq -r '.tag')
    PORT=$(echo "$line" | jq -r '.listen_port')
    UUID=$(echo "$line" | jq -r '.users[0].uuid')
    NET=$(echo "$line" | jq -r '.transport.type // "tcp"')
    
    # Формируем JSON вручную
    JSON="{\"v\":\"2\",\"ps\":\"$TAG\",\"add\":\"$SERVER_IP\",\"port\":\"$PORT\",\"id\":\"$UUID\",\"aid\":\"0\",\"net\":\"$NET\",\"type\":\"none\",\"host\":\"\",\"path\":\"\",\"tls\":\"\"}"
    
    B64=$(echo -n "$JSON" | base64 | tr -d '\n')
    LINK="vmess://$B64"
    
    echo "$LINK"
    echo "$LINK" >> "$OUT_FILE"
done

# --- 4. TROJAN ---
echo "--- TROJAN ---"
jq -c '.inbounds[] | select(.type=="trojan")' "$CONF" | while read -r line; do
    TAG=$(echo "$line" | jq -r '.tag')
    PORT=$(echo "$line" | jq -r '.listen_port')
    PASS=$(echo "$line" | jq -r '.users[0].password')
    SNI=$(echo "$line" | jq -r '.tls.server_name // empty')
    
    PARAMS="security=tls"
    if [ ! -z "$SNI" ]; then PARAMS="$PARAMS&sni=$SNI"; fi
    
    LINK="trojan://$PASS@$SERVER_IP:$PORT?$PARAMS#$TAG"
    
    echo "$LINK"
    echo "$LINK" >> "$OUT_FILE"
done

# --- 5. HYSTERIA 2 ---
echo "--- HYSTERIA 2 ---"
jq -c '.inbounds[] | select(.type=="hysteria2")' "$CONF" | while read -r line; do
    TAG=$(echo "$line" | jq -r '.tag')
    PORT=$(echo "$line" | jq -r '.listen_port')
    PASS=$(echo "$line" | jq -r '.users[0].password')
    
    LINK="hy2://$PASS@$SERVER_IP:$PORT?insecure=1#$TAG"
    
    echo "$LINK"
    echo "$LINK" >> "$OUT_FILE"
done

echo ""
echo "Done! Links saved to: $OUT_FILE"
