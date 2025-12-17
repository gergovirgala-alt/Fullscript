#!/bin/bash

LOGFILE="/var/log/pro_install.log"

RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
NC="\033[0m"

set -Eeuo pipefail

START_TIME=$(date +%s)
echo "===== Script started: $(date) =====" >> "$LOGFILE"

trap 'echo -e "${RED}Error occurred! (line: $LINENO)${NC}";
      echo "ERROR $(date) line: $LINENO" >> "$LOGFILE"' ERR

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Root privileges required!${NC}"
    exit 1
fi

log() {
    echo "$(date '+%F %T') - $1" >> "$LOGFILE"
}

ask_yes_no() {
    while true; do
        read -rp "$1 (y/n): " yn
        case $yn in
            [yY]*) return 0 ;;
            [nN]*) return 1 ;;
            *) echo "Only y or n allowed!" ;;
        esac
    done
}

is_installed() {
    dpkg -l | grep -q "^ii  $1" || return 1
}

# ================= RUNNING PERSON ANIMATION =================
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
        echo -e "${BLUE}Downloading servers...${NC}\n"
        echo -e "${GREEN}${frames[$i]}${NC}"
        i=$(( (i + 1) % ${#frames[@]} ))
        sleep 0.2
    done

    wait "$pid" || true
    clear
    echo -e "${GREEN}[✓] Download complete!${NC}"
    tput cnorm 2>/dev/null || true
}

declare -A RESULTS

set_result() {
    RESULTS["$1"]="$2"
}

check_service() {
    systemctl is-active --quiet "$1" \
        && set_result "$2" "SUCCESS" \
        || set_result "$2" "ERROR"
}

clear
echo -e "${BLUE}Updating system...${NC}"
apt update >> "$LOGFILE" 2>&1 &
runner $!

# ================= INSTALL FUNCTIONS =================

install_apache() {
    echo -e "${GREEN}Installing Apache...${NC}"
    if ! is_installed apache2; then
        apt install -y apache2 libapache2-mod-php >> "$LOGFILE" 2>&1 &
        runner $!
    fi
    systemctl enable --now apache2 >> "$LOGFILE" 2>&1 || true
}

install_php() {
    echo -e "${GREEN}Installing PHP...${NC}"
    apt install -y php php-mbstring php-zip php-gd php-json php-curl php-mysql >> "$LOGFILE" 2>&1 &
    runner $!
}

install_ssh() {
    echo -e "${GREEN}Installing SSH...${NC}"
    apt install -y openssh-server >> "$LOGFILE" 2>&1 &
    runner $!
    systemctl enable --now ssh >> "$LOGFILE" 2>&1 || true
}

install_mosquitto() {
    echo -e "${GREEN}Installing Mosquitto...${NC}"
    apt install -y mosquitto mosquitto-clients >> "$LOGFILE" 2>&1 &
    runner $!
    systemctl enable --now mosquitto >> "$LOGFILE" 2>&1 || true
}

install_mariadb() {
    echo -e "${GREEN}Installing MariaDB...${NC}"
    apt install -y mariadb-server >> "$LOGFILE" 2>&1 &
    runner $!
    systemctl enable --now mariadb >> "$LOGFILE" 2>&1 || true

    echo "Database configuration:"
    read -rp "Username: " DB_USER
    read -rsp "Password: " DB_PASS; echo
    read -rp "Database name: " DB_NAME

    mysql -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME};" || true
    mysql -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';" || true
    mysql -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';" || true
    mysql -e "FLUSH PRIVILEGES;" || true
}

install_node_red() {
    echo -e "${GREEN}Installing Node-RED...${NC}"
    command -v curl >/dev/null || apt install -y curl >> "$LOGFILE" 2>&1
    curl -fsSL https://raw.githubusercontent.com/node-red/linux-installers/master/deb/update-nodejs-and-nodered | bash >> "$LOGFILE" 2>&1 &
    runner $!
    systemctl enable --now nodered.service >> "$LOGFILE" 2>&1 || true
}

install_phpmyadmin() {
    echo -e "${GREEN}Installing phpMyAdmin...${NC}"
    apt install -y phpmyadmin >> "$LOGFILE" 2>&1 &
    runner $!
}

install_docker() {
    echo -e "${GREEN}Installing Docker...${NC}"
    apt install -y docker.io docker-compose >> "$LOGFILE" 2>&1 &
    runner $!
    systemctl enable --now docker >> "$LOGFILE" 2>&1 || true
}

install_security() {
    echo -e "${GREEN}Installing UFW + Fail2Ban...${NC}"
    apt install -y ufw fail2ban >> "$LOGFILE" 2>&1 &
    runner $!

    ufw default deny incoming || true
    ufw default allow outgoing || true
    ufw allow 22/tcp || true
    ufw allow 80/tcp || true
    ufw allow 1883/tcp || true
    ufw --force enable || true

    systemctl enable --now fail2ban >> "$LOGFILE" 2>&1 || true
}

# ================= MENU =================

clear
echo "======================================"
echo "        DEBIAN INSTALLER MENU"
echo "======================================"
echo "1) Node-RED"
echo "2) Apache + PHP"
echo "3) Mosquitto MQTT"
echo "4) SSH"
echo "5) phpMyAdmin"
echo "6) Docker"
echo "7) Security (UFW + Fail2Ban)"
echo "0) Exit"
echo "======================================"
echo "Multiple options allowed (e.g: 1 3 7)"
read -rp "Choice: " choices

for choice in $choices; do
    case $choice in
        1) install_node_red ;;
        2) install_apache; install_php; ask_yes_no "Install MariaDB too?" && install_mariadb ;;
        3) install_mosquitto ;;
        4) install_ssh ;;
        5) install_apache; install_php; install_phpmyadmin ;;
        6) install_docker ;;
        7) install_security ;;
        0) exit 0 ;;
        *) echo -e "${RED}Invalid option: $choice${NC}" ;;
    esac
done

# ================= TEST & VALIDATION =================

check_service apache2 "Apache2"
check_service ssh "SSH"
check_service mosquitto "Mosquitto"
check_service nodered.service "Node-RED"
check_service mariadb "MariaDB"
check_service docker "Docker"
check_service fail2ban "Fail2Ban"

clear
echo "======================================"
echo "        INSTALLATION RESULTS"
echo "======================================"
for key in "${!RESULTS[@]}"; do
    echo "$key : ${RESULTS[$key]}"
done

echo
echo "Open ports:"
ss -tuln | grep -E ':(22|80|1883)' || echo "No relevant ports"

echo
echo "Apache HTTP test:"
curl -Is http://localhost 2>/dev/null | head -n 1 || echo "Apache not responding"

END_TIME=$(date +%s)
echo
echo -e "${GREEN}Script execution time: $((END_TIME - START_TIME)) seconds${NC}"
echo -e "${YELLOW}Note:${NC} Firewall recommended for open services."

log "Script completed successfully"
