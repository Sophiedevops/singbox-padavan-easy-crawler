#!/bin/sh

# === CONFIG ===
WANTED=10
PERFECT_SPEED_KBPS=500
TEST_PORT=25555
TEST_URLS="https://speed.cloudflare.com/__down?bytes=10485760 https://cachefly.cachefly.net/10mb.test"
WORKDIR="/opt/home/admin/singbox_original"
TEMP="/opt/tmp/sb_upd3"
BIN="$WORKDIR/sing-box"
CONF_BASE="$WORKDIR/conf3_final.json"
CONF_TARGET="$WORKDIR/conf2_final.json"

# PRIORITY: NL -> DE -> US
FILTER_COUNTRIES="NL,DE,US,PL,FI"
FILTER_PROTOCOLS="vless,shadowsocks,hysteria2,trojan,vmess"
BATCH_SIZE=10

SUBS_LIST="
https://raw.githubusercontent.com/sakha1370/OpenRay/refs/heads/main/output/all_valid_proxies.txt
https://raw.githubusercontent.com/hamedcode/port-based-v2ray-configs/main/sub/port_443.txt
https://raw.githubusercontent.com/amirkma/proxykma/refs/heads/main/mix.txt
https://raw.githubusercontent.com/hans-thomas/v2ray-subscription/refs/heads/master/servers.txt
https://raw.githubusercontent.com/DukeMehdi/FreeList-V2ray-Configs/refs/heads/main/Configs/ShadowSocks-V2Ray-Configs-By-DukeMehdi.txt
https://raw.githubusercontent.com/gongchandang49/TelegramV2rayCollector/refs/heads/main/sub/mix
https://raw.githubusercontent.com/SoliSpirit/v2ray-configs/refs/heads/main/Protocols/ss.txt
https://raw.githubusercontent.com/LonUp/NodeList/main/node.txt
"

# --- PREPARE ---
rm -rf "$TEMP" && mkdir -p "$TEMP"
touch "$TEMP/results.txt"

# 1. Create helper files (JQ and AWK)
# Ãåíåðàòîð êîíôèãà äëÿ òåñòà
echo '. as $n | { "log": { "level": "error" }, "experimental": { "clash_api": { "external_controller": "127.0.0.1:9091" } }, "route": { "final": "tester_group" }, "inbounds": [ { "type": "socks", "tag": "socks-test", "listen": "127.0.0.1", "listen_port": '$TEST_PORT' } ], "outbounds": ($n + [{ "type": "urltest", "tag": "tester_group", "outbounds": ($n | map(.tag)), "url": "http://cp.cloudflare.com/generate_204", "interval": "1m", "tolerance": 50 }]) }' > "$TEMP/gen.jq"

# Ïàðñåð API äëÿ ïîèñêà ëó÷øåãî óçëà
echo '.proxies|to_entries|map(select(.value.history|length>0)|select(.value.history[-1].delay>0))|sort_by(.value.history[-1].delay)|map(.key)|.[]' > "$TEMP/api.jq"

# Ñåëåêòîð äëÿ ôèíàëüíîãî êîíôèãà
echo '{ "type": "urltest", "tag": "Best-Auto", "outbounds": $tags[0], "url": "http://cp.cloudflare.com/generate_204", "interval": "3m", "tolerance": 50 }' > "$TEMP/sel.jq"

# Ìåðæ â ôèíàëüíûé êîíôèã
echo '.log.level = "warn" | .outbounds += $nodes[0] | .outbounds += $sel | .route.final = "Best-Auto"' > "$TEMP/fin.jq"

# AWK äëÿ ðàñ÷åòà ñêîðîñòè
echo '{ k = int($1 / 1024); print k }' > "$TEMP/calc_speed.awk"

# Ôèëüòðû JQ
echo 'map(select( (.tag|ascii_downcase|contains($c)) and (.type=="shadowsocks") ))' > "$TEMP/filter_ss.jq"
echo 'map(select( (.tag|ascii_downcase|contains($c)) and (.type!="shadowsocks") ))' > "$TEMP/filter_other.jq"

# --- HELPER: Find active URL ---
ACTIVE_TEST_URL=""
for U in $TEST_URLS; do
    if curl -Is --connect-timeout 3 "$U" | grep -q "200 OK"; then 
        ACTIVE_TEST_URL="$U"
        break
    fi
done
[ -z "$ACTIVE_TEST_URL" ] && echo "No active test URL" && exit 1

# === 1. FAST CHECK ===
if [ -f "$CONF_TARGET" ]; then
    echo "Checking existing nodes (Strict Mode)..."
    
    jq '[.outbounds[] | select(.type != "urltest" and .type != "selector" and .type != "direct" and .type != "dns" and .type != "block")]' "$CONF_TARGET" > "$TEMP/fast_nodes.json"
    
    NODE_CNT=0
    if [ -s "$TEMP/fast_nodes.json" ]; then
        NODE_CNT=$(grep -c "type" "$TEMP/fast_nodes.json")
    fi
    
    if [ "$NODE_CNT" -gt 0 ]; then
        jq -f "$TEMP/gen.jq" "$TEMP/fast_nodes.json" > "$TEMP/run_fast.json"
        "$BIN" run -c "$TEMP/run_fast.json" > /dev/null 2>&1 &
        FPID=$!
        sleep 10
        
        PASS=0
        for i in 1 2 3; do
            SPD=$(curl -x socks5://127.0.0.1:$TEST_PORT -s -o /dev/null -w "%{speed_download}" --max-time 8 "$ACTIVE_TEST_URL")
            KBPS=$(echo "$SPD" | awk -f "$TEMP/calc_speed.awk")
            [ -z "$KBPS" ] && KBPS=0
            
            echo "  Test $i: $KBPS KB/s"
            if [ "$KBPS" -ge "$PERFECT_SPEED_KBPS" ]; then
                PASS=$(expr $PASS + 1)
            fi
            sleep 1
        done
        kill -9 $FPID > /dev/null 2>&1
        
        if [ "$PASS" -ge 2 ]; then
            echo "  Nodes are stable. Restarting..."
            killall -9 sing-box >/dev/null 2>&1; sleep 1
            "$BIN" run -c "$CONF_TARGET" >/dev/null 2>&1 &
            rm -rf "$TEMP" && exit 0
        fi
        echo "  Unstable nodes. Forcing full update..."
    fi
fi

# === 2. FULL UPDATE ===
echo "Starting Full Update..."
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

# Ôîðìèðóåì JSON ìàññèâ ïðîòîêîëîâ äëÿ JQ
PJ="["
for P in $(echo "$FILTER_PROTOCOLS" | tr ',' ' '); do 
    if [ "$PJ" = "[" ]; then PJ="$PJ\"$P\""; else PJ="$PJ,\"$P\""; fi
done
PJ="$PJ]"

jq --argjson protos "$PJ" 'map(select(.type as $t | $protos | index($t)))' "$TEMP/raw.json" > "$TEMP/all_protos.json"

echo "[]" > "$TEMP/sorted_final.json"

# Loop: Countries
for C in $(echo "$FILTER_COUNTRIES" | tr ',' ' '); do
    C_L=$(echo "$C" | tr '[:upper:]' '[:lower:]')
    echo "  > Processing Country: $C ($C_L)"

    # Priority A: Shadowsocks
    jq --arg c "$C_L" -f "$TEMP/filter_ss.jq" "$TEMP/all_protos.json" > "$TEMP/chunk_ss.json"
    
    if [ -s "$TEMP/chunk_ss.json" ]; then
         LEN=$(grep -c "type" "$TEMP/chunk_ss.json")
         if [ "$LEN" -gt 0 ]; then
             echo "    + Added Shadowsocks nodes"
             jq -s '.[0] + .[1]' "$TEMP/sorted_final.json" "$TEMP/chunk_ss.json" > "$TEMP/sorted_tmp.json" && mv "$TEMP/sorted_tmp.json" "$TEMP/sorted_final.json"
         fi
    fi

    # Priority B: Other
    jq --arg c "$C_L" -f "$TEMP/filter_other.jq" "$TEMP/all_protos.json" > "$TEMP/chunk_other.json"
    
    if [ -s "$TEMP/chunk_other.json" ]; then
         LEN=$(grep -c "type" "$TEMP/chunk_other.json")
         if [ "$LEN" -gt 0 ]; then
             echo "    + Added other nodes"
             jq -s '.[0] + .[1]' "$TEMP/sorted_final.json" "$TEMP/chunk_other.json" > "$TEMP/sorted_tmp.json" && mv "$TEMP/sorted_tmp.json" "$TEMP/sorted_final.json"
         fi
    fi
done

mv "$TEMP/sorted_final.json" "$TEMP/all.json"
TOTAL=$(grep -c "type" "$TEMP/all.json")
echo "Scanning Priority Queue (~$TOTAL nodes)..."

# === 4. BATCH SCANNING (RESTORED) ===
CUR=0
DONE=0
G_COUNT=0

# Îñíîâíîé öèêë ïðîâåðêè
while [ "$DONE" -lt 200 ] && [ "$CUR" -lt "$TOTAL" ]; do
    # Âû÷èñëÿåì êîíåö ñëàéñà (èñïîëüçóåì expr äëÿ ñîâìåñòèìîñòè ñ sh)
    END=$(expr $CUR + $BATCH_SIZE)
    
    # Èçâëåêàåì ïà÷êó óçëîâ
    jq ".[$CUR:$END]" "$TEMP/all.json" > "$TEMP/batch.json"
    
    # Åñëè óçëîâ íåò (ïóñòîé ìàññèâ), ïðåðûâàåì
    if [ ! -s "$TEMP/batch.json" ] || [ "$(grep -c "type" "$TEMP/batch.json")" -eq 0 ]; then
        break
    fi

    # Ãåíåðèðóåì êîíôèã äëÿ òåñòà
    jq -f "$TEMP/gen.jq" "$TEMP/batch.json" > "$TEMP/run.json"
    
    # Çàïóñêàåì sing-box
    "$BIN" run -c "$TEMP/run.json" > /dev/null 2>&1 &
    PID=$!
    sleep 10
    
    # Ñïðàøèâàåì API, êàêîé óçåë ëó÷øå (ñàìûé áûñòðûé îòâåò)
    BEST=$(curl -s http://127.0.0.1:9091/proxies | jq -r -f "$TEMP/api.jq" | head -n 1)
    
    if [ -n "$BEST" ] && [ "$BEST" != "null" ]; then
        # Çàìåðÿåì ñêîðîñòü ñêà÷èâàíèÿ ÷åðåç ýòîò ëó÷øèé óçåë
        SPD=$(curl -x socks5://127.0.0.1:$TEST_PORT -s -w "%{speed_download}" -o /dev/null --max-time 15 "$ACTIVE_TEST_URL")
        
        # Êîíâåðòèðóåì â KB (èñïîëüçóåì âíåøíèé AWK)
        KBPS=$(echo "$SPD" | awk -f "$TEMP/calc_speed.awk")
        [ -z "$KBPS" ] && KBPS=0
        
        if [ "$KBPS" -ge "$PERFECT_SPEED_KBPS" ]; then
            echo "  [FOUND] $BEST: $KBPS KB/s"
            echo "$KBPS|$BEST" >> "$TEMP/results.txt"
            
            # Ñ÷èòàåì, ñêîëüêî ìû íàøëè ãîäíûõ óçëîâ
            G_COUNT=$(expr $G_COUNT + 1)
            echo "  Total Found: $G_COUNT"
            
            # Åñëè íàøëè äîñòàòî÷íî - âûõîäèì
            if [ "$G_COUNT" -ge "$WANTED" ]; then 
                kill -9 $PID > /dev/null 2>&1
                break 
            fi
        fi
    fi
  
    kill -9 $PID > /dev/null 2>&1
    wait $PID 2>/dev/null

    # Ñäâèãàåì êóðñîð
    CUR=$END
    DONE=$(expr $DONE + 1)
done

# === 5. FINAL CONFIG (RESTORED) ===
echo "Generating Final Config..."

if [ -s "$TEMP/results.txt" ]; then
    # Ñîðòèðóåì ðåçóëüòàòû ïî ñêîðîñòè (÷èñëåííî, ðåâåðñ) è áåðåì òîï
    sort -rn "$TEMP/results.txt" | head -n "$WANTED" > "$TEMP/top.txt"
    
    # Èçâëåêàåì òîëüêî òåãè (êîëîíêà 2)
    cut -d'|' -f2 "$TEMP/top.txt" > "$TEMP/top_tags.txt"
    
    # Ïðåâðàùàåì òåãè â JSON ìàññèâ ñòðîê
    jq -R . "$TEMP/top_tags.txt" | jq -s . > "$TEMP/tags_array.json"
    
    # Âûòàñêèâàåì ïîëíûå îáúåêòû íîä èç all.json ïî ýòèì òåãàì
    jq --slurpfile tags "$TEMP/tags_array.json" 'map(select(.tag as $t | $tags[0] | index($t)))' "$TEMP/all.json" > "$TEMP/final_nodes.json"
    
    # Ñîáèðàåì ôèíàëüíûé ñåëåêòîð
    jq -n --slurpfile tags "$TEMP/tags_array.json" -f "$TEMP/sel.jq" > "$TEMP/sel.json"
    
    # Ìåðäæèì âñå â áàçîâûé êîíôèã
    jq --slurpfile nodes "$TEMP/final_nodes.json" --slurpfile sel "$TEMP/sel.json" -f "$TEMP/fin.jq" "$CONF_BASE" > "$CONF_TARGET"
else
    echo "No working nodes found."
fi

# === 6. RESTART ===
if [ -s "$CONF_TARGET" ]; then
    echo "Restarting service with new config..."
    killall -9 sing-box > /dev/null 2>&1; sleep 1
    "$BIN" run -c "$CONF_TARGET" > /dev/null 2>&1 &
    echo "DONE"
else
    echo "ERROR: Config generation failed or no nodes found."
fi

rm -rf "$TEMP"
