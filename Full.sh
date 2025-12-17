#!/bin/bash

LOGFILE="/var/log/pro_install.log"

RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
NC="\033[0m"

set -Eeuo pipefail

START_TIME=$(date +%s)
echo "===== Script indult: $(date) =====" >> "$LOGFILE"

trap 'echo -e "${RED}Hiba történt! (sor: $LINENO)${NC}";
      echo "HIBA $(date) sor: $LINENO" >> "$LOGFILE"' ERR

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Root jogosultság szükséges!${NC}"
    exit 1
fi

log() {
    echo "$(date '+%F %T') - $1" >> "$LOGFILE"
}

ask_yes_no() {
    while true; do
        read -rp "$1 (i/n): " yn
        case $yn in
            [iI]*) return 0 ;;
            [nN]*) return 1 ;;
            *) echo "Csak i vagy n válasz megengedett!" ;;
        esac
    done
}

is_installed() {
    dpkg -l | grep -q "^ii  $1"
}

# ================= FUTÓ EMBER ANIMÁCIÓ =================
runner() {
    local pid=$1
    tput civis 2>/dev/null || true

    frames=(
"  o
 /|\\
 / \\"
" \\o
  |\\
 / \\"
"  o/
 /|
 / \\"
"  o
 \\|/
 / \\"
    )

    i=0
    while kill -0 "$pid" 2>/dev/null; do
        clear
        echo -e "${BLUE}Szerverek letöltése folyamatban...${NC}\n"
        echo -e "${GREEN}${frames[$i]}${NC}"
        i=$(( (i + 1) % ${#frames[@]} ))
        sleep 0.2
    done

    clear
    echo -e "${GREEN}[✓] Letöltés kész!${NC}"
    tput cnorm 2>/dev/null || true
}

declare -A RESULTS
set_result() { RESULTS["$1"]="$2"; }

check_service() {
    systemctl is-active --quiet "$1" \
        && set_result "$2" "SIKERES" \
        || set_result "$2" "HIBA"
}

clear
echo -e "${BLUE}Rendszer frissítése...${NC}"
apt update >> "$LOGFILE" 2>&1 &
runner $!

# ================= TELEPÍTŐ FÜGGVÉNYEK =================

install_apache() {
    echo -e "${GREEN}Apache telepítése...${NC}"
    is_installed apache2 || {
        apt install -y apache2 libapache2-mod-php >> "$LOGFILE" 2>&1 &
        runner $!
    }
    systemctl enable --now apache2
}

install_php() {
    echo -e "${GREEN}PHP telepítése...${NC}"
    apt install -y php php-mbstring php-zip php-gd php-json php-curl php-mysql >> "$LOGFILE" 2>&1 &
    runner $!
}

install_ssh() {
    echo -e "${GREEN}SSH telepítése...${NC}"
    apt install -y openssh-server >> "$LOGFILE" 2>&1 &
    runner $!
    systemctl enable --now ssh
}

install_mosquitto() {
    echo -e "${GREEN}Mosquitto telepítése...${NC}"
    apt install -y mosquitto mosquitto-clients >> "$LOGFILE" 2>&1 &
    runner $!
    systemctl enable --now mosquitto
}

install_mariadb() {
    echo -e "${GREEN}MariaDB telepítése...${NC}"
    apt install -y mariadb-server >> "$LOGFILE" 2>&1 &
    runner $!
    systemctl enable --now mariadb

    echo "Adatbázis beállítása:"
    read -rp "Felhasználónév: " DB_USER
    read -rsp "Jelszó: " DB_PASS; echo
    read -rp "Adatbázis neve: " DB_NAME

    mysql -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME};"
    mysql -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';"
    mysql -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';"
    mysql -e "FLUSH PRIVILEGES;"
}

install_node_red() {
    echo -e "${GREEN}Node-RED telepítése...${NC}"
    command -v curl >/dev/null || apt install -y curl >> "$LOGFILE" 2>&1
    curl -fsSL https://raw.githubusercontent.com/node-red/linux-installers/master/deb/update-nodejs-and-nodered | bash
    systemctl enable --now nodered.service
}

install_phpmyadmin() {
    echo -e "${GREEN}phpMyAdmin telepítése...${NC}"
    apt install -y phpmyadmin >> "$LOGFILE" 2>&1 &
    runner $!
}

install_docker() {
    echo -e "${GREEN}Docker telepítése...${NC}"
    apt install -y docker.io docker-compose >> "$LOGFILE" 2>&1 &
    runner $!
    systemctl enable --now docker
}

install_security() {
    echo -e "${GREEN}UFW + Fail2Ban telepítése...${NC}"
    apt install -y ufw fail2ban >> "$LOGFILE" 2>&1 &
    runner $!

    ufw default deny incoming
    ufw default allow outgoing
    ufw allow 22/tcp
    ufw allow 80/tcp
    ufw allow 1883/tcp
    ufw --force enable

    systemctl enable --now fail2ban
}

# ================= MENÜ =================

clear
echo "======================================"
echo "        DEBIAN TELEPÍTŐ MENÜ"
echo "======================================"
echo "1) Node-RED"
echo "2) Apache + PHP"
echo "3) Mosquitto MQTT"
echo "4) SSH"
echo "5) phpMyAdmin"
echo "6) Docker"
echo "7) Biztonság (UFW + Fail2Ban)"
echo "0) Kilépés"
echo "======================================"
echo "Több opció megadható (pl: 1 3 7)"
read -rp "Választás: " choices

for choice in $choices; do
    case $choice in
        1) install_node_red ;;
        2) install_apache; install_php; ask_yes_no "MariaDB is kell?" && install_mariadb ;;
        3) install_mosquitto ;;
        4) install_ssh ;;
        5) install_apache; install_php; install_phpmyadmin ;;
        6) install_docker ;;
        7) install_security ;;
        0) exit 0 ;;
        *) echo -e "${RED}Érvénytelen opció: $choice${NC}" ;;
    esac
done

# ================= TESZT & ELLENŐRZÉS =================

check_service apache2 "Apache2"
check_service ssh "SSH"
check_service mosquitto "Mosquitto"
check_service nodered.service "Node-RED"
check_service mariadb "MariaDB"
check_service docker "Docker"
check_service fail2ban "Fail2Ban"

clear
echo "======================================"
echo "        TELEPÍTÉSI EREDMÉNYEK"
echo "======================================"
for key in "${!RESULTS[@]}"; do
    echo "$key : ${RESULTS[$key]}"
done

echo
echo "Nyitott portok:"
ss -tuln | grep -E ':(22|80|1883)' || echo "Nincs releváns port"

echo
echo "Apache HTTP teszt:"
curl -Is http://localhost | head -n 1 || echo "Apache nem válaszol"

END_TIME=$(date +%s)
echo
echo -e "${GREEN}Script futási ideje: $((END_TIME - START_TIME)) mp${NC}"
echo -e "${YELLOW}Megjegyzés:${NC} Nyitott szolgáltatások esetén tűzfal használata ajánlott."

log "Script sikeresen lefutott"
