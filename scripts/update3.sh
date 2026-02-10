#!/bin/sh

# === НАСТРОЙКИ ===
WANTED=10
PERFECT_SPEED_KBPS=500
TEST_PORT=25555
TEST_URLS="https://speed.cloudflare.com/__down?bytes=10485760 https://cachefly.cachefly.net/10mb.test"
WORKDIR="/opt/tmp_sb_ext/sing-box-1.12.12-extended-1.5.1-linux-mipsle"
TEMP="/opt/tmp/sb_upd3"
BIN="$WORKDIR/sing-box"
CONF_BASE="$WORKDIR/conf3_final.json"
CONF_TARGET="$WORKDIR/conf2_final.json"

# ВАЖНО: Порядок стран определяет приоритет проверки!
FILTER_COUNTRIES="NL,DE,US,PL,FI"
FILTER_PROTOCOLS="shadowsocks,vless,hysteria2,trojan,vmess"

SUBS_LIST="
https://raw.githubusercontent.com/sakha1370/OpenRay/refs/heads/main/output/all_valid_proxies.txt
https://raw.githubusercontent.com/ebrasha/free-v2ray-public-list/refs/heads/main/all_extracted_configs.txt
https://raw.githubusercontent.com/V2RayRoot/V2RayConfig/refs/heads/main/Config/vless.txt
https://raw.githubusercontent.com/acymz/AutoVPN/refs/heads/main/data/V2.txt
https://raw.githubusercontent.com/roosterkid/openproxylist/refs/heads/main/V2RAY.txt
https://raw.githubusercontent.com/amirkma/proxykma/refs/heads/main/mix.txt
https://raw.githubusercontent.com/mahdibland/V2RayAggregator/refs/heads/master/sub/sub_merge.txt
https://raw.githubusercontent.com/gongchandang49/TelegramV2rayCollector/refs/heads/main/sub/mix
https://raw.githubusercontent.com/SoliSpirit/v2ray-configs/refs/heads/main/Protocols/ss.txt
https://raw.githubusercontent.com/LonUp/NodeList/main/node.txt
"

prepare_temp() {
    rm -rf "$TEMP" && mkdir -p "$TEMP"
    touch "$TEMP/results.txt"
    # Исправленный генератор конфига для тестов
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

# === 1. FAST CHECK (Strict 3-pass logic) ===
if [ -f "$CONF_TARGET" ]; then
    echo "Checking existing nodes (Strict Mode)..."
    prepare_temp && check_provider || exit 1
    # Исправлена выборка узлов, исключаем служебные типы
    jq '[.outbounds[] | select(.type != "urltest" and .type != "selector" and .type != "direct" and .type != "dns" and .type != "block")]' "$CONF_TARGET" > "$TEMP/fast_nodes.json"
    
    if [ $(jq 'length' "$TEMP/fast_nodes.json") -gt 0 ]; then
        jq -f "$TEMP/gen.jq" "$TEMP/fast_nodes.json" > "$TEMP/run_fast.json"
        "$BIN" run -c "$TEMP/run_fast.json" > /dev/null 2>&1 &
        FPID=$! && sleep 10
        
        PASS=0
        for i in 1 2 3; do
            SPD=$(curl -x socks5://127.0.0.1:$TEST_PORT -s -o /dev/null -w "%{speed_download}" --max-time 8 "$ACTIVE_TEST_URL")
            KBPS=$(echo "$SPD" | awk '{print int($1 / 1024)}')
            echo "  Test $i: $KBPS KB/s"
            [ "$KBPS" -ge "$PERFECT_SPEED_KBPS" ] && PASS=$((PASS+1))
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
    wget --no-check-certificate -q -O "$TEMP/part.txt" "$URL"
    if [ -s "$TEMP/part.txt" ]; then
        echo "  [OK] $FNAME"
        cat "$TEMP/part.txt" >> "$TEMP/all_subs.txt"
    else
        echo "  [FAIL] $FNAME"
    fi
done

# Конвертация через ваш Lua скрипт
cd "$WORKDIR" && cp "$TEMP/all_subs.txt" subs_raw.txt && lua converter.lua > /dev/null 2>&1
mv all_nodes.json "$TEMP/raw.json"

# === 3. PRIORITY SORTING LOGIC (New) ===
echo "Building Priority Queue..."

# Сначала фильтруем всё лишнее (протоколы), чтобы работать с чистым списком
PJ="["
for P in $(echo "$FILTER_PROTOCOLS" | tr ',' ' '); do [ "$PJ" = "[" ] && PJ="$PJ\"$P\"" || PJ="$PJ,\"$P\""; done; PJ="$PJ]"
jq --argjson protos "$PJ" 'map(select(.type as $t | $protos | index($t)))' "$TEMP/raw.json" > "$TEMP/all_protos.json"

# Создаем пустой массив для отсортированного списка
echo "[]" > "$TEMP/sorted_final.json"

# Проходим по странам в порядке приоритета (NL -> DE -> US)
for C in $(echo "$FILTER_COUNTRIES" | tr ',' ' '); do
    C_L=$(echo "$C" | tr '[:upper:]' '[:lower:]')
    echo "  > Processing Country: $C ($C_L)"

    # Этап 1: Shadowsocks для текущей страны
    jq --arg c "$C_L" 'map(select( (.tag|ascii_downcase|contains($c)) and (.type=="shadowsocks") ))' "$TEMP/all_protos.json" > "$TEMP/chunk_ss.json"
    CNT_SS=$(jq 'length' "$TEMP/chunk_ss.json")
    if [ "$CNT_SS" -gt 0 ]; then
        echo "    + Added $CNT_SS Shadowsocks nodes"
        # Добавляем к общему списку
        jq -s '.[0] + .[1]' "$TEMP/sorted_final.json" "$TEMP/chunk_ss.json" > "$TEMP/sorted_tmp.json" && mv "$TEMP/sorted_tmp.json" "$TEMP/sorted_final.json"
    fi

    # Этап 2: Остальные протоколы для текущей страны
    jq --arg c "$C_L" 'map(select( (.tag|ascii_downcase|contains($c)) and (.type!="shadowsocks") ))' "$TEMP/all_protos.json" > "$TEMP/chunk_other.json"
    CNT_OTH=$(jq 'length' "$TEMP/chunk_other.json")
    if [ "$CNT_OTH" -gt 0 ]; then
         echo "    + Added $CNT_OTH other nodes"
         jq -s '.[0] + .[1]' "$TEMP/sorted_final.json" "$TEMP/chunk_other.json" > "$TEMP/sorted_tmp.json" && mv "$TEMP/sorted_tmp.json" "$TEMP/sorted_final.json"
    fi
done

# Переименовываем в all.json для совместимости с циклом сканирования
mv "$TEMP/sorted_final.json" "$TEMP/all.json"

TOTAL=$(jq 'length' "$TEMP/all.json")
echo "Scanning Priority Queue ($TOTAL nodes)..."

# === 4. BATCH SCANNING ===
CUR=0; DONE=0
while [ $DONE -lt 200 ] && [ $CUR -lt $TOTAL ]; do
    NXT=$(expr $CUR + 5)
    echo "Batch $CUR-$NXT..."
    jq ".[$CUR:$NXT]" "$TEMP/all.json" | jq -f "$TEMP/gen.jq" > "$TEMP/run.json"
    
    "$BIN" run -c "$TEMP/run.json" > /dev/null 2>&1 &
    PID=$! && sleep 10 # Даем время на старт и коннект
    
    # Запрос к API sing-box для выбора лучшего
    BEST=$(curl -s http://127.0.0.1:9091/proxies | jq -r -f "$TEMP/api.jq" | head -n 1)
    
    if [ -n "$BEST" ] && [ "$BEST" != "null" ]; then
        # Реальный тест скорости
        SPD=$(curl -x socks5://127.0.0.1:$TEST_PORT -s -w "%{speed_download}" -o /dev/null --max-time 15 "$ACTIVE_TEST_URL")
        KBPS=$(echo "$SPD" | awk '{print int($1 / 1024)}')
        
        if [ "$KBPS" -ge "$PERFECT_SPEED_KBPS" ]; then
            echo "  [FOUND] $BEST: $KBPS KB/s"
            echo "$KBPS|$BEST" >> "$TEMP/results.txt"
            
            # Проверка количества найденных хороших узлов
            G_COUNT=$(awk -F'|' -v p="$PERFECT_SPEED_KBPS" '$1 >= p {c++} END {print c+0}' "$TEMP/results.txt")
            echo "  Total Found: $G_COUNT / $WANTED"
            
            if [ "$G_COUNT" -ge "$WANTED" ]; then 
                echo ">>> Target reached! Stopping scan."
                kill -9 $PID > /dev/null 2>&1
                break 
            fi
        fi
    fi
    
    kill -9 $PID > /dev/null 2>&1
    wait $PID 2>/dev/null
    CUR=$NXT
    DONE=$(expr $DONE + 1)
done

# === 5. FINAL CONFIG GENERATION ===
echo "Generating Final Config..."
# Берем только лучшие результаты, обрезаем до WANTED
sort -rn "$TEMP/results.txt" | head -n $WANTED | cut -d'|' -f2 > "$TEMP/top_tags.txt"

# Создаем JSON массив из имен тегов
jq -R . "$TEMP/top_tags.txt" | jq -s . > "$TEMP/tags.json"

# Выбираем полные объекты узлов из all.json, которые совпадают с тегами
jq --slurpfile tags "$TEMP/tags.json" 'map(. as $node | select($tags[0] | index($node.tag)))' "$TEMP/all.json" > "$TEMP/final.json"

# Создаем список тегов для selector/urltest
jq 'map(.tag)' "$TEMP/final.json" > "$TEMP/ftags.json"
jq -n --slurpfile tags "$TEMP/ftags.json" -f "$TEMP/sel.jq" > "$TEMP/sel.json"

# Сборка финального конфига (исправлены ошибки в конце вашего файла)
jq --slurpfile nodes "$TEMP/final.json" --slurpfile sel "$TEMP/sel.json" -f "$TEMP/fin.jq" "$CONF_BASE" > "$CONF_TARGET"

# === 6. RESTART ===
if [ -s "$CONF_TARGET" ]; then
    echo "Restarting service with new config..."
    killall -9 sing-box > /dev/null 2>&1; sleep 1
    "$BIN" run -c "$CONF_TARGET" > /dev/null 2>&1 &
    echo "DONE!"
else
    echo "ERROR: Config generation failed (empty file)."
fi

rm -rf "$TEMP"
