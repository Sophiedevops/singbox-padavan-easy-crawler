#!/bin/sh

# === КОНФИГУРАЦИЯ ===
GITHUB_USER="Sophiedevops"
REPO_NAME="singbox-padavan-easy-crawler"
GITHUB_RAW="https://raw.githubusercontent.com/$GITHUB_USER/$REPO_NAME/main"
INSTALL_PATH="/opt/tmp_sb_ext/sing-box-1.12.12-extended-1.5.1-linux-mipsle"
BACKUP_PATH="${INSTALL_PATH}.bak"
SNI_DOMAIN="icloud.com"

echo "=================================================="
echo "    $REPO_NAME: Installer v1.0"
echo "=================================================="

# 1. ПРОВЕРКА СИСТЕМЫ
echo "[1/8] Checking System..."
[ ! -x "/opt/bin/opkg" ] && { echo "ERROR: Entware not found in /opt."; exit 1; }

# Проверка ресурсов
FREE_RAM=$(free -m | awk '/Mem:/ {print $4}')
[ -z "$FREE_RAM" ] && FREE_RAM=$(grep MemFree /proc/meminfo | awk '{print int($2/1024)}')
FREE_DISK=$(df -m /opt | awk 'NR==2 {print $4}')

if [ "$FREE_RAM" -lt 30 ] || [ "$FREE_DISK" -lt 128 ]; then
    echo "ERROR: Not enough resources (RAM: ${FREE_RAM}MB, Disk: ${FREE_DISK}MB)."
    exit 1
fi

# 2. ЗАВИСИМОСТИ
echo "[2/8] Checking Dependencies..."
[ -z "$(which lua)" ] && { echo "ERROR: Lua not found."; exit 1; }

if ! command -v jq > /dev/null 2>&1; then
    echo "Installing JQ..."
    opkg update && opkg install jq
fi

if ! command -v curl > /dev/null 2>&1; then
    echo "Installing curl..."
    opkg update && opkg install curl
fi

if ! command -v wget > /dev/null 2>&1; then
    echo "Installing wget..."
    opkg update && opkg install wget
fi

if ! command -v openssl > /dev/null 2>&1; then
    echo "Installing OpenSSL..."
    opkg install openssl-util
fi

# 3. ИНТЕРАКТИВ
if [ -d "$INSTALL_PATH" ]; then
    echo "--------------------------------------------------"
    echo "Existing installation found!"
    echo "1) Smart Backup (Keep old config)"
    echo "2) Clean Install (DELETE ALL)"
    echo "3) Exit"
    echo "--------------------------------------------------"
    read -p "Your choice [1-3]: " CHOICE < /dev/tty
    #read -p "Your choice [1-3]: " CHOICE
    case $CHOICE in
        1)
            rm -rf "$BACKUP_PATH" && mv "$INSTALL_PATH" "$BACKUP_PATH"
            mkdir -p "$INSTALL_PATH"
            [ -f "$BACKUP_PATH/conf2_final.json" ] && cp "$BACKUP_PATH/conf2_final.json" "$INSTALL_PATH/"
            echo "Backup created at $BACKUP_PATH"
            ;;
        2) rm -rf "$INSTALL_PATH" && mkdir -p "$INSTALL_PATH" ;;
        *) exit 0 ;;
    esac
else
    mkdir -p "$INSTALL_PATH"
fi

# 4. ЗАГРУЗКА
echo "[4/8] Downloading components..."
cd "$INSTALL_PATH"

# Скачиваем бинарник из Релизов
wget -q --no-check-certificate -O "sing-box" "https://github.com/$GITHUB_USER/$REPO_NAME/releases/download/1.0.0/sing-box"
[ ! -s "sing-box" ] && { echo "ERROR: Binary download failed!"; exit 1; }

# Скачиваем остальные файлы
FILES="converter.lua utils.lua update3.sh gen_links.sh conf3_final.json"
for f in $FILES; do
    case $f in
        *.lua|*.sh) SUBDIR="scripts" ;;
        *.json) SUBDIR="templates" ;;
    esac
    wget -q --no-check-certificate -O "$f" "$GITHUB_RAW/$SUBDIR/$f"
done
chmod +x sing-box update3.sh gen_links.sh

# 5. ГЕНЕРАЦИЯ СЕКРЕТОВ
echo "[5/8] Generating unique keys..."
mkdir -p certs/grpc
UUID=$(lua -e 'math.randomseed(os.time()); local t="xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"; print((string.gsub(t, "[xy]", function (c) return string.format("%x", (c=="x") and math.random(0,15) or math.random(8,11)) end)))')
PASS_SS=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | head -c 16)
PASS_HY=$(openssl rand -hex 10)
PASS_ST=$(openssl rand -base64 15 | tr -dc 'a-zA-Z0-9' | head -c 20)
KEYS=$(./sing-box generate reality-keypair)
REALITY_PRIV=$(echo "$KEYS" | awk -F': ' '/Private key/ {print $2}' | tr -d ' ')
#REALITY_PRIV=$(./sing-box generate reality-keypair | grep "Private key" | awk '{print $3}')
REALITY_SHORT=$(openssl rand -hex 4)

# Сертификаты
openssl req -x509 -newkey rsa:2048 -nodes -keyout "certs/grpc/h2.pem" -out "certs/grpc/h2.cert" -days 3650 -subj "/CN=$SNI_DOMAIN" > /dev/null 2>&1

# 6. АДАПТАЦИЯ
echo "[6/8] Adapting configuration..."
sed -i "s|WORKDIR=.*|WORKDIR=\"$INSTALL_PATH\"|g" update3.sh gen_links.sh
sed -i "s|uuid-here|$UUID|g" conf3_final.json
sed -i "s|ss-password-here|$PASS_SS|g" conf3_final.json
sed -i "s|hy2-password-here|$PASS_HY|g" conf3_final.json
sed -i "s|shadowtls-secret-here|$PASS_ST|g" conf3_final.json
sed -i "s|reality-private-key-here|$REALITY_PRIV|g" conf3_final.json
sed -i "s|short-id-here|$REALITY_SHORT|g" conf3_final.json
sed -i "s|icloud.com|$SNI_DOMAIN|g" conf3_final.json

# 7. ВЕРИФИКАЦИЯ
echo "[7/8] Verifying..."
if ! ./sing-box version > /dev/null 2>&1; then
    echo "ERROR: Binary failed! Rolling back..."
    [ -d "$BACKUP_PATH" ] && { rm -rf "$INSTALL_PATH" && mv "$BACKUP_PATH" "$INSTALL_PATH"; }
    exit 1
fi

# 8. АВТОЗАПУСК
echo "[8/8] Setting up autostart..."
STARTED_SCRIPT="/etc/storage/started_script.sh"
RUN_CMD="$INSTALL_PATH/sing-box run -c $INSTALL_PATH/conf2_final.json &"

if ! grep -q "$INSTALL_PATH/sing-box" "$STARTED_SCRIPT"; then
    echo "" >> "$STARTED_SCRIPT"
    echo "$RUN_CMD" >> "$STARTED_SCRIPT"
    mtd_storage.sh save > /dev/null 2>&1
fi

echo "DONE! Use ./update3.sh to start."
