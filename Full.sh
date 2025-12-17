#!/bin/bash

LOGFILE="/var/log/pro_install.log"

RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
CYAN="\033[1;36m"
MAGENTA="\033[1;35m"
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

# ================= TELEPÍTÉS / TÖRLÉS VÁLASZTÁS =================

ask_action() {
    while true; do
        echo ""
        echo -e "${CYAN}Válassz műveletet:${NC}"
        echo -e "${GREEN}1) Telepítés${NC}"
        echo -e "${RED}2) Törlés${NC}"
        read -rp "Choice (1/2): " choice
        case $choice in
            1) ACTION="install"; return 0 ;;
            2) ACTION="remove"; return 0 ;;
            *) echo -e "${RED}Csak 1 vagy 2 lehet!${NC}" ;;
        esac
    done
}

is_installed() {
    dpkg -l | grep -q "^ii  $1" || return 1
}

# ================= ENHANCED ANIMATION WITHOUT TEXT =================

play_background_music() {
    for freq in 800 900 1000 900 800; do
        printf '\a' >/dev/null 2>&1 || true
        sleep 0.1
    done &
}

stop_music() {
    pkill -f "play_background_music" 2>/dev/null || true
}

runner() {
    local pid=$1
    tput civis 2>/dev/null || true

    frames=(
"     ◯
    ╱ ╲
   ╱   ╲
  │     │
   ╲   ╱
    ╲ ╱"
"     ◉
    ╱ ╲
   ╱   ╲
  │  ●  │
   ╲   ╱
    ╲ ╱"
"     ●
    ╱ ╲
   ╱   ╲
  │  ◯  │
   ╲   ╱
    ╲ ╱"
"    ◯◯
    ╱ ╲
   ╱   ╲
  │  ●  │
   ╲   ╱
    ╲ ╱"
"  ◯ ◯ ◯
    ╱ ╲
   ╱   ╲
  │  ●  │
   ╲   ╱
    ╲ ╱"
"   ◯ ◯
    ╱ ╲
   ╱ ● ╲
  │     │
   ╲   ╱
    ╲ ╱"
    )

    play_background_music

    i=0
    while kill -0 "$pid" 2>/dev/null; do
        clear
        echo -e "${MAGENTA}${frames[$i]}${NC}\n"
        progress_char=( "█" "▓" "▒" "░" )
        progress_idx=$((i % 4))
        echo -e "${GREEN}Loading... ${progress_char[$progress_idx]}${NC}"
        i=$(( (i + 1) % ${#frames[@]} ))
        sleep 0.3
    done

    wait "$pid" || true
    stop_music
    clear
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

# ================= INSTALL FUNCTIONS =================

install_apache() {
    apt install -y apache2 libapache2-mod-php >> "$LOGFILE" 2>&1 &
    runner $!
    systemctl enable --now apache2 >> "$LOGFILE" 2>&1 || true
}

install_php() {
    apt install -y php php-mbstring php-zip php-gd php-json php-curl php-mysql >> "$LOGFILE" 2>&1 &
    runner $!
}

install_ssh() {
    apt install -y openssh-server >> "$LOGFILE" 2>&1 &
    runner $!
    systemctl enable --now ssh >> "$LOGFILE" 2>&1 || true
}

install_mosquitto() {
    apt install -y mosquitto mosquitto-clients >> "$LOGFILE" 2>&1 &
    runner $!
    systemctl enable --now mosquitto >> "$LOGFILE" 2>&1 || true
}

install_mariadb() {
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

install_phpmyadmin() {
    apt install -y phpmyadmin >> "$LOGFILE" 2>&1 &
    runner $!
}

install_docker() {
    apt install -y docker.io docker-compose >> "$LOGFILE" 2>&1 &
    runner $!
    systemctl enable --now docker >> "$LOGFILE" 2>&1 || true
}

install_security() {
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

# ================= REMOVE FUNCTIONS =================

remove_apache() {
    systemctl stop apache2 2>/dev/null || true
    apt purge -y apache2 libapache2-mod-php >> "$LOGFILE" 2>&1 &
    runner $!
}

remove_php() {
    apt purge -y php\* >> "$LOGFILE" 2>&1 &
    runner $!
}

remove_ssh() {
    systemctl stop ssh 2>/dev/null || true
    apt purge -y openssh-server >> "$LOGFILE" 2>&1 &
    runner $!
}

remove_mosquitto() {
    systemctl stop mosquitto 2>/dev/null || true
    apt purge -y mosquitto mosquitto-clients >> "$LOGFILE" 2>&1 &
    runner $!
}

remove_mariadb() {
    systemctl stop mariadb 2>/dev/null || true
    apt purge -y mariadb-server >> "$LOGFILE" 2>&1 &
    runner $!
}

remove_phpmyadmin() {
    apt purge -y phpmyadmin >> "$LOGFILE" 2>&1 &
    runner $!
}

remove_docker() {
    systemctl stop docker 2>/dev/null || true
    apt purge -y docker.io docker-compose >> "$LOGFILE" 2>&1 &
    runner $!
}

remove_nodered() {
    systemctl stop nodered.service 2>/dev/null || true
    apt purge -y nodered nodejs >> "$LOGFILE" 2>&1 &
    runner $!
}

remove_security() {
    ufw --force disable || true
    systemctl stop fail2ban 2>/dev/null || true
    apt purge -y ufw fail2ban >> "$LOGFILE" 2>&1 &
    runner $!
}

# ================= MAIN MENU LOOP =================

show_menu() {
    clear
    echo -e "${CYAN}════════════════════════════════════${NC}"
    echo -e "${CYAN}║${NC}    ${MAGENTA}DEBIAN INSTALLER MENU${NC}    ${CYAN}║${NC}"
    echo -e "${CYAN}════════════════════════════════════${NC}"
    echo ""
    echo -e "${YELLOW}1)${NC} Node-RED"
    echo -e "${YELLOW}2)${NC} Apache + PHP"
    echo -e "${YELLOW}3)${NC} Mosquitto MQTT"
    echo -e "${YELLOW}4)${NC} SSH"
    echo -e "${YELLOW}5)${NC} MariaDB"
    echo -e "${YELLOW}6)${NC} phpMyAdmin"
    echo -e "${YELLOW}7)${NC} Docker"
    echo -e "${YELLOW}8)${NC} Security (UFW + Fail2Ban)"
    echo -e "${YELLOW}9)${NC} System Update"
    echo -e "${RED}0)${NC} Exit"
    echo -e "${CYAN}════════════════════════════════════${NC}"
    echo ""
    echo -e "${GREEN}Multiple options allowed (e.g: 1 3 7)${NC}"
    read -rp "Choice: " choices
    echo ""

    if [[ -z "$choices" ]]; then
        return 1
    fi

    for choice in $choices; do
        if [[ $choice -ne 9 ]]; then
            ask_action
        else
            ACTION="install"
        fi

        case $choice in
            1) [[ $ACTION == "install" ]] && install_node_red || remove_nodered ;;
            2)
                if [[ $ACTION == "install" ]]; then
                    install_apache
                    install_php
                else
                    remove_apache
                    remove_php
                fi
            ;;
            3) [[ $ACTION == "install" ]] && install_mosquitto || remove_mosquitto ;;
            4) [[ $ACTION == "install" ]] && install_ssh || remove_ssh ;;
            5) [[ $ACTION == "install" ]] && install_mariadb || remove_mariadb ;;
            6) [[ $ACTION == "install" ]] && install_phpmyadmin || remove_phpmyadmin ;;
            7) [[ $ACTION == "install" ]] && install_docker || remove_docker ;;
            8) [[ $ACTION == "install" ]] && install_security || remove_security ;;
            9)
                apt update >> "$LOGFILE" 2>&1 &
                runner $!
            ;;
            0) return 0 ;;
            *) echo -e "${RED}Invalid option: $choice${NC}"; sleep 2 ;;
        esac
    done
    return 1
}

# ================= LOOP MENU UNTIL EXIT =================

while true; do
    if show_menu; then
        break
    fi
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  Press ${GREEN}Enter${NC} to return to menu...     ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════╝${NC}"
    read -r
done

# ================= FINAL RESULTS =================

clear
echo -e "${CYAN}════════════════════════════════════${NC}"
echo -e "${CYAN}║${NC}    ${GREEN}INSTALLATION COMPLETE!${NC}    ${CYAN}║${NC}"
echo -e "${CYAN}════════════════════════════════════${NC}"
echo ""

check_service apache2 "Apache2"
check_service ssh "SSH"
check_service mosquitto "Mosquitto"
check_service nodered.service "Node-RED"
check_service mariadb "MariaDB"
check_service docker "Docker"
check_service fail2ban "Fail2Ban"

echo -e "${YELLOW}Installation Results:${NC}"
for key in "${!RESULTS[@]}"; do
    if [[ "${RESULTS[$key]}" == "SUCCESS" ]]; then
        echo -e "  ${GREEN}✓${NC} $key : ${GREEN}${RESULTS[$key]}${NC}"
    else
        echo -e "  ${RED}✗${NC} $key : ${RED}${RESULTS[$key]}${NC}"
    fi
done

echo ""
echo -e "${YELLOW}Open ports:${NC}"
ss -tuln | grep -E ':(22|80|1883)' || echo "  No relevant ports"

echo ""
echo -e "${YELLOW}Apache HTTP test:${NC}"
curl -Is http://localhost 2>/dev/null | head -n 1 || echo "  Apache not responding"

END_TIME=$(date +%s)
echo ""
echo -e "${GREEN}Script execution time: $((END_TIME - START_TIME)) seconds${NC}"
echo -e "${YELLOW}Note:${NC} Firewall recommended for open services."
echo ""

log "Script completed successfully"
