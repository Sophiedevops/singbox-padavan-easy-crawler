#!/bin/sh

# === CONFIG ===
WANTED=10
PERFECT_SPEED_KBPS=900
TEST_PORT=25555
TEST_URLS="https://speed.cloudflare.com/__down?bytes=10485760 https://cachefly.cachefly.net/10mb.test"
WORKDIR="/opt/home/admin/singbox_original"
TEMP="/opt/tmp/sb_upd3"
BIN="$WORKDIR/sing-box"
CONF_BASE="$WORKDIR/conf3_final.json"
CONF_TARGET="$WORKDIR/conf2_final.json"

# PRIORITY: NL -> DE -> US
FILTER_COUNTRIES="NL,DE,US,PL,FI"
FILTER_PROTOCOLS="shadowsocks,vless,hysteria2,trojan,vmess"

SUBS_LIST="
https://raw.githubusercontent.com/sakha1370/OpenRay/refs/heads/main/output/all_valid_proxies.txt
https://raw.githubusercontent.com/amirkma/proxykma/refs/heads/main/mix.txt
https://raw.githubusercontent.com/mahdibland/V2RayAggregator/refs/heads/master/sub/sub_merge.txt
https://raw.githubusercontent.com/DukeMehdi/FreeList-V2ray-Configs/refs/heads/main/Configs/ShadowSocks-V2Ray-Configs-By-DukeMehdi.txt
https://raw.githubusercontent.com/gongchandang49/TelegramV2rayCollector/refs/heads/main/sub/mix
https://raw.githubusercontent.com/SoliSpirit/v2ray-configs/refs/heads/main/Protocols/ss.txt
https://raw.githubusercontent.com/hamedcode/port-based-v2ray-configs/main/sub/ss.txt
"

prepare_temp() {
    rm -rf "$TEMP" && mkdir -p "$TEMP"
    touch "$TEMP/results.txt"
    echo '. as $n | { "log": { "level": "error" }, "experimental": { "clash_api": { "external_controller": "127.0.0.1:9091" } }, "route": { "final": "tester_group" }, "inbounds": [ { "type": "socks", "tag": "socks-test", "listen": "127.0.0.1", "listen_port": '$TEST_PORT' } ], "outbounds": ($n + [{ "type": "urltest", "tag": "tester_group", "outbounds": ($n | map(.tag)), "url": "http://cp.cloudflare.com/generate_204", "interval": "1m", "tolerance": 50 }]) }' > "$TEMP/gen.jq"
    echo '.proxies|to_entries|map(select(.value.history|length>0)|select(.value.history[-1].delay>0))|sort_by(.value.history[-1].delay)|map(.key)|.[]' > "$TEMP/api.jq"
    echo '{ "type": "urltest", "tag": "Best-Auto", "outbounds": $tags[0], "url": "http://cp.cloudflare.com/generate_204", "interval": "3m", "tolerance": 50 }' > "$TEMP/sel.jq"
    echo '.log.level = "warn" | .outbounds += $nodes[0] | .outbounds += $sel | .route.final = "Best-Auto"' > "$TEMP/fin.jq"
}

check_provider() {
    for U in $TEST_URLS; do
        if curl -Is --connect-timeout 3 "$U" | grep -q "200 OK"; then ACTIVE_TEST_URL="$U"; return 0; fi
    done
    return 1
}

# === 1. FAST CHECK ===
if [ -f "$CONF_TARGET" ]; then
    echo "Checking existing nodes (Strict Mode)..."
    prepare_temp && check_provider || exit 1
    
    # Extract nodes excluding system types
    jq '[.outbounds[] | select(.type != "urltest" and .type != "selector" and .type != "direct" and .type != "dns" and .type != "block")]' "$CONF_TARGET" > "$TEMP/fast_nodes.json"
    
    # Bulletproof counting logic
    NODE_CNT=0
    if [ -s "$TEMP/fast_nodes.json" ]; then
        RAW_CNT=$(jq 'length' "$TEMP/fast_nodes.json" 2>/dev/null)
        # Verify it is a pure integer
        if echo "$RAW_CNT" | grep -qE '^[0-9]+$'; then
            NODE_CNT=$RAW_CNT
        fi
    fi
    
    if [ "$NODE_CNT" -gt 0 ]; then
        jq -f "$TEMP/gen.jq" "$TEMP/fast_nodes.json" > "$TEMP/run_fast.json"
        "$BIN" run -c "$TEMP/run_fast.json" > /dev/null 2>&1 &
        FPID=$! && sleep 10
        
        PASS=0
        for i in 1 2 3; do
            SPD=$(curl -x socks5://127.0.0.1:$TEST_PORT -s -o /dev/null -w "%{speed_download}" --max-time 8 "$ACTIVE_TEST_URL")
            # Force integer conversion
            KBPS=$(echo "$SPD" | awk '{print int($1 / 1024)}')
            # Safe check if empty
            case "$KBPS" in ''|*[!0-9]*) KBPS=0 ;; esac
            
            echo "  Test $i: $KBPS KB/s"
            if [ "$KBPS" -ge "$PERFECT_SPEED_KBPS" ]; then
                PASS=$(expr $PASS + 1)
            fi
            sleep 1
        done
        kill -9 $FPID > /dev/null 2>&1
        
        if [ "$PASS" -ge 2 ]; then
            echo "  Nodes are stable ($PASS/3 passes). Restarting service..."
            killall -9 sing-box >/dev/null 2>&1; sleep 1
            "$BIN" run -c "$CONF_TARGET" >/dev/null 2>&1 &
            rm -rf "$TEMP" && exit 0
        fi
        echo "  Unstable nodes. Forcing full update..."
    fi
fi

# === 2. FULL UPDATE ===
echo "Starting Full Update..."
prepare_temp && check_provider || exit 1
> "$TEMP/all_subs.txt"
for URL in $SUBS_LIST; do
    FNAME=$(echo $URL | awk -F/ '{print $(NF-1)"/"$NF}')
    rm -f "$TEMP/part.txt"
    wget --no-check-certificate -q -O "$TEMP/part.txt" "$URL"
    if [ -s "$TEMP/part.txt" ]; then
        echo "  [OK] $FNAME"
        cat "$TEMP/part.txt" >> "$TEMP/all_subs.txt"
    else
        echo "  [FAIL] $FNAME"
    fi
done

cd "$WORKDIR" && cp "$TEMP/all_subs.txt" subs_raw.txt && lua converter.lua > /dev/null 2>&1
mv all_nodes.json "$TEMP/raw.json"

# === 3. PRIORITY SORTING ===
echo "Building Priority Queue..."

PJ="["
for P in $(echo "$FILTER_PROTOCOLS" | tr ',' ' '); do [ "$PJ" = "[" ] && PJ="$PJ\"$P\"" || PJ="$PJ,\"$P\""; done; PJ="$PJ]"
jq --argjson protos "$PJ" 'map(select(.type as $t | $protos | index($t)))' "$TEMP/raw.json" > "$TEMP/all_protos.json"

echo "[]" > "$TEMP/sorted_final.json"

for C in $(echo "$FILTER_COUNTRIES" | tr ',' ' '); do
    C_L=$(echo "$C" | tr '[:upper:]' '[:lower:]')
    echo "  > Processing Country: $C ($C_L)"

    # Priority 1: Shadowsocks
    jq --arg c "$C_L" 'map(select( (.tag|ascii_downcase|contains($c)) and (.type=="shadowsocks") ))' "$TEMP/all_protos.json" > "$TEMP/chunk_ss.json"
    CNT_SS=$(jq 'length' "$TEMP/chunk_ss.json")
    if [ "$CNT_SS" -gt 0 ]; then
        echo "    + Added $CNT_SS Shadowsocks nodes"
        jq -s '.[0] + .[1]' "$TEMP/sorted_final.json" "$TEMP/chunk_ss.json" > "$TEMP/sorted_tmp.json" && mv "$TEMP/sorted_tmp.json" "$TEMP/sorted_final.json"
    fi

    # Priority 2: Other protocols
    jq --arg c "$C_L" 'map(select( (.tag|ascii_downcase|contains($c)) and (.type!="shadowsocks") ))' "$TEMP/all_protos.json" > "$TEMP/chunk_other.json"
    CNT_OTH=$(jq 'length' "$TEMP/chunk_other.json")
    if [ "$CNT_OTH" -gt 0 ]; then
         echo "    + Added $CNT_OTH other nodes"
         jq -s '.[0] + .[1]' "$TEMP/sorted_final.json" "$TEMP/chunk_other.json" > "$TEMP/sorted_tmp.json" && mv "$TEMP/sorted_tmp.json" "$TEMP/sorted_final.json"
    fi
done

mv "$TEMP/sorted_final.json" "$TEMP/all.json"
TOTAL=$(jq 'length' "$TEMP/all.json")
echo "Scanning Priority Queue ($TOTAL nodes)..."

# === 4. BATCH SCANNING ===
CUR
w

    echo "Batch $CUR-$N
    jq ".[$CUR:$NXT]" "$TEMP/a
    
    "$BIN" run -c "$TEMP/run.json" > /dev/null
    PID=$!
    sleep 10
    
    BEST=$(curl -s http://127.0.0.1:9091/proxies | jq -r -f "$TEMP/api.jq" | head -n 1)
    
    if [ -n "$BEST" ] && [ "$BEST" != "null" ]; then
        SPD=$(curl -x socks5://127.0.0.1:$TEST_PORT -s -w "%{speed_download}" -o /dev/null --max-time 15 "$ACTIVE_TEST_URL")
        KBPS=$(echo "$SPD" | awk '{print int($1 / 1024)}')
        # Safety for KBPS
        case "$KBPS" in ''|*[!0-9]*) KBPS=0 ;; esac
        
        if [ "$KBPS" -ge "$P
            echo "  [FOUND] $BEST: $KBPS KB/s"
       
            
            G_CO
          
      
    
                echo ">>> Target r
                kill -9 $PID > /dev/null 2>&1
                break 
            fi
        fi
    fi
    
    kill -9 $PID > /dev/null 2>&
    wait $PID 2>/dev/null
 
    DONE
done

# === 5. FINAL CONFIG ===
echo "Generating Final Config..."
sort -rn "$TEMP/results.txt" | head -n $WANTED | cut -d'|' -f2 > "$TEMP/top_tags.txt"
jq -R . "$TEMP/to
jq --slurpfile tags "$TEMP/tags.json" 

jq 'map(.tag)' "$TEMP/final.json" > "$TEMP/ftags.json"
jq -n --slurpfile tags "$TEMP/ftags.json" -f "$TEMP/sel.jq" > "$TEMP/sel.json"
jq --slurpfile nodes "$TEMP/final.json" --slurpfile sel "$TEMP/sel.json" -f "$TEMP/fin.jq" "$CONF_BASE" > "$CONF_TARGET"

# === 6. RESTART ===
if [ -s "$CONF_TARGET" ]; then
    echo "Restarting service w
    killall 
    "$BIN" run -c "$CONF_TARGET" > /de
    echo "DONE!"
else
    echo "ERROR: Config generation failed (empty file)."
fi

rm -rf "$TEMP"
