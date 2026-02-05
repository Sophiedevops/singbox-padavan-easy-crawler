#!/bin/sh

# === CONFIG ===
SUBS_URL="https://raw.githubusercontent.com/Farid-Karimi/Config-Collector/refs/heads/main/ss_iran.txt"
WORKDIR="/opt/tmp_sb_ext/sing-box-1.12.12-extended-1.5.1-linux-mipsle"
TEMP="/tmp/sb_upd"
BIN="$WORKDIR/sing-box"
CONF_BASE="$WORKDIR/conf3_final.json"
CONF_TARGET="$WORKDIR/conf2_final.json"
INIT_SCRIPT="/opt/etc/init.d/S99sing-box"
WANTED=5

# === PREPARE ===
# Не убиваем сервис в начале! Пусть работает, пока мы ищем новые.
rm -rf $TEMP
mkdir -p $TEMP

# === JQ RULES ===
F_GEN="$TEMP/gen.jq"
echo '{ "log": { "level": "debug", "timestamp": true }, "experimental": { "clash_api": { "external_controller": "127.0.0.1:9091", "store_selected": false } }, "inbounds": [], "outbounds": ($nodes[0] + [{ "type": "urltest", "tag": "tester_group", "outbounds": ($nodes[0] | map(.tag)), "url": "http://cp.cloudflare.com/generate_204", "interval": "1m", "tolerance": 50 }]) }' > "$F_GEN"

F_API="$TEMP/api.jq"
echo '.proxies|to_entries|map(select(.value.history|length>0)|select(.value.history[-1].delay>0))|map(.key)|.[]' > "$F_API"

F_FILT="$TEMP/filt.jq"
echo 'map(select(.tag as $t | $tags[0] | index($t)))' > "$F_FILT"

F_SEL="$TEMP/sel.jq"
echo '{ "type": "urltest", "tag": "Best-Auto", "outbounds": $tags[0], "url": "http://cp.cloudflare.com/generate_204", "interval": "10m", "tolerance": 50 }' > "$F_SEL"

F_FIN="$TEMP/fin.jq"
echo '.outbounds += $nodes[0] | .outbounds += $sel | .route.final = "Best-Auto"' > "$F_FIN"

# === START ===
echo "Net check..."
if ! ping -c 1 8.8.8.8 > /dev/null 2>&1; then echo "No Internet."; exit 1; fi

echo "Download..."
wget --no-check-certificate -q -O "$TEMP/sub.txt" "$SUBS_URL"
if test ! -s "$TEMP/sub.txt"; then echo "DL Failed"; exit 1; fi

cp "$TEMP/sub.txt" "$WORKDIR/subs_raw.txt"
cd "$WORKDIR"
TOTAL=$(lua converter.lua)
mv all_nodes.json "$TEMP/all.json"

if test -z "$TOTAL"; then echo "Zero nodes"; exit 1; fi
echo "Nodes: $TOTAL"

CUR=0
BATCH=20
DONE=0
echo "[]" > "$TEMP/good.json"

while test $DONE -lt 15; do
    if test $CUR -ge $TOTAL; then break; fi
    NXT=$(expr $CUR + $BATCH)
    echo "Scan: $CUR-$NXT"

    jq ".[$CUR:$NXT]" "$TEMP/all.json" > "$TEMP/batch.json"
    LEN=$(jq 'length' "$TEMP/batch.json")
    if test "$LEN" -eq 0; then break; fi

    jq --slurpfile nodes "$TEMP/batch.json" -f "$F_GEN" "$TEMP/batch.json" > "$TEMP/run.json"

    # Останавливаем основной сервис перед тестом для чистоты порта
    killall -9 sing-box > /dev/null 2>&1

    rm -f "$TEMP/run.log"
    $BIN run -c "$TEMP/run.json" > "$TEMP/run.log" 2>&1 &
    PID=$!
    
    # Wait loop
    for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
        if ! kill -0 $PID > /dev/null 2>&1; then break; fi
        sleep 1
    done

    curl -s --connect-timeout 2 http://127.0.0.1:9091/proxies > "$TEMP/api.json"
    jq -r -f "$F_API" "$TEMP/api.json" > "$TEMP/ok_tags.txt"

    kill $PID > /dev/null 2>&1
    wait $PID 2>/dev/null

    if test -s "$TEMP/ok_tags.txt"; then
        CNT=$(wc -l < "$TEMP/ok_tags.txt")
        echo "Found: $CNT"
        
        jq -R . "$TEMP/ok_tags.txt" | jq -s . > "$TEMP/tags.json"
        jq --slurpfile tags "$TEMP/tags.json" -f "$F_FILT" "$TEMP/batch.json" > "$TEMP/new.json"
        jq --slurpfile new "$TEMP/new.json" '(. + $new[0]) | unique_by(.tag)' "$TEMP/good.json" > "$TEMP/tmp.json" && mv "$TEMP/tmp.json" "$TEMP/good.json"
        
        SAVED=$(jq 'length' "$TEMP/good.json")
        echo "Saved: $SAVED"
        if test "$SAVED" -ge "$WANTED"; then echo "Enough."; break; fi
    else
        echo "None."
    fi
    
    CUR=$NXT
    DONE=$(expr $DONE + 1)
done

SAVED=$(jq 'length' "$TEMP/good.json")
if test "$SAVED" -eq 0; then 
    echo "Fail. Restarting old config via Init.d..."
    $INIT_SCRIPT start
    exit 1
fi

echo "Finalize..."
jq '.[0:10]' "$TEMP/good.json" > "$TEMP/final.json"
jq 'map(.tag)' "$TEMP/final.json" > "$TEMP/ftags.json"
jq -n --slurpfile tags "$TEMP/ftags.json" -f "$F_SEL" > "$TEMP/sel.json"

if test ! -f "$CONF_BASE"; then echo '{ "log": {}, "inbounds": [], "outbounds": [], "route": {} }' > "$CONF_BASE"; fi

jq --slurpfile nodes "$TEMP/final.json" --slurpfile sel "$TEMP/sel.json" -f "$F_FIN" "$CONF_BASE" > "$CONF_TARGET"

echo "Restarting Service via Init.d..."
$INIT_SCRIPT restart
echo "DONE!"
