#!/bin/bash

LOGFILE="$HOME/.pro_install.log"

RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
CYAN="\033[1;36m"
MAGENTA="\033[1;35m"
BLACK="\033[0;30m"
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

# ================= MATRIX FALLING NUMBERS ANIMATION =================

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
    local message="${2:-Processing}"
    tput civis 2>/dev/null || true

    # Matrix falling numbers animation
    frames=(
"
${GREEN}1 0 1 1 0 0 1 0 1 1${NC}
${GREEN}0 1 0 1 1 0 1 0 1 1${NC}
${GREEN}1 1 0 1 0 1 1 0 1 0${NC}
${GREEN}0 1 1 0 1 0 1 1 0 1${NC}
${GREEN}1 0 1 0 1 1 0 1 0 1${NC}
"

"
${GREEN}0 1 0 1 1 0 1 0 1 1${NC}
${GREEN}1 1 0 1 0 1 1 0 1 0${NC}
${GREEN}0 1 1 0 1 0 1 1 0 1${NC}
${GREEN}1 0 1 0 1 1 0 1 0 1${NC}
${GREEN}0 0 1 1 0 1 0 1 1 0${NC}
"

"
${GREEN}1 1 0 1 0 1 1 0 1 0${NC}
${GREEN}0 1 1 0 1 0 1 1 0 1${NC}
${GREEN}1 0 1 0 1 1 0 1 0 1${NC}
${GREEN}0 0 1 1 0 1 0 1 1 0${NC}
${GREEN}1 0 1 1 0 0 1 0 1 1${NC}
"

"
${GREEN}0 1 1 0 1 0 1 1 0 1${NC}
${GREEN}1 0 1 0 1 1 0 1 0 1${NC}
${GREEN}0 0 1 1 0 1 0 1 1 0${NC}
${GREEN}1 0 1 1 0 0 1 0 1 1${NC}
${GREEN}0 1 0 1 1 0 1 0 1 1${NC}
"

"
${GREEN}1 0 1 0 1 1 0 1 0 1${NC}
${GREEN}0 0 1 1 0 1 0 1 1 0${NC}
${GREEN}1 0 1 1 0 0 1 0 1 1${NC}
${GREEN}0 1 0 1 1 0 1 0 1 1${NC}
${GREEN}1 1 0 1 0 1 1 0 1 0${NC}
"

"
${GREEN}0 0 1 1 0 1 0 1 1 0${NC}
${GREEN}1 0 1 1 0 0 1 0 1 1${NC}
${GREEN}0 1 0 1 1 0 1 0 1 1${NC}
${GREEN}1 1 0 1 0 1 1 0 1 0${NC}
${GREEN}0 1 1 0 1 0 1 1 0 1${NC}
"

"
${GREEN}1 0 1 1 0 0 1 0 1 1${NC}
${GREEN}0 1 0 1 1 0 1 0 1 1${NC}
${GREEN}1 1 0 1 0 1 1 0 1 0${NC}
${GREEN}0 1 1 0 1 0 1 1 0 1${NC}
${GREEN}1 0 1 0 1 1 0 1 0 1${NC}
"

"
${GREEN}0 1 0 1 1 0 1 0 1 1${NC}
${GREEN}1 1 0 1 0 1 1 0 1 0${NC}
${GREEN}0 1 1 0 1 0 1 1 0 1${NC}
${GREEN}1 0 1 0 1 1 0 1 0 1${NC}
${GREEN}0 0 1 1 0 1 0 1 1 0${NC}
"
    )

    play_background_music

    i=0
    while kill -0 "$pid" 2>/dev/null; do
        clear
        echo ""
        echo -e "${CYAN}╔════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${NC}     $message                ${CYAN}║${NC}"
        echo -e "${CYAN}╚════════════════════════════════════╝${NC}\n"
        
        # Matrix animation
        echo "${frames[$i]}"
        
        # Progress indicator
        progress_char=( "▓▓▓░░░" "▓▓▓▓░░" "▓▓▓▓▓░" "▓▓▓▓▓▓" "░▓▓▓▓▓" "░░▓▓▓▓" )
        progress_idx=$((i % 6))
        echo -e "\n${MAGENTA}${progress_char[$progress_idx]}${NC}"
        
        i=$(( (i + 1) % ${#frames[@]} ))
        sleep 0.35
    done

    wait "$pid" || true
    stop_music
    
    clear
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}    ${GREEN}[✓] TASK COMPLETE!${NC}          ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════╝${NC}"
    sleep 1
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

# ================= INSTALLATION STATUS CHECK =================

check_installed_packages() {
    clear
    echo ""
    echo -e "${CYAN}════════════════════════════════════${NC}"
    echo -e "${CYAN}║${NC}   ${MAGENTA}INSTALLATION STATUS CHECK${NC}    ${CYAN}║${NC}"
    echo -e "${CYAN}════════════════════════════════════${NC}"
    echo ""
    
    packages=(
        "apache2:Apache Web Server"
        "php:PHP"
        "openssh-server:SSH Server"
        "mosquitto:Mosquitto MQTT"
        "mariadb-server:MariaDB Database"
        "docker.io:Docker"
        "nodejs:Node.js"
        "ufw:UFW Firewall"
        "fail2ban:Fail2Ban"
        "phpmyadmin:phpMyAdmin"
    )
    
    installed_count=0
    not_installed_count=0
    
    for package_info in "${packages[@]}"; do
        package="${package_info%%:*}"
        name="${package_info##*:}"
        
        if is_installed "$package"; then
            echo -e "  ${GREEN}✓${NC} $name"
            ((installed_count++))
        else
            echo -e "  ${RED}✗${NC} $name"
            ((not_installed_count++))
        fi
    done
    
    echo ""
    echo -e "${GREEN}Installed: $installed_count${NC}"
    echo -e "${RED}Not Installed: $not_installed_count${NC}"
    echo ""
    echo -e "${CYAN}════════════════════════════════════${NC}"
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  Press ${GREEN}Enter${NC} to return to menu...     ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════╝${NC}"
    read -r
}

# ================= INSTALL FUNCTIONS =================

install_apache() {
    echo -e "${GREEN}Installing Apache...${NC}"
    if ! is_installed apache2; then
        apt install -y apache2 libapache2-mod-php >> "$LOGFILE" 2>&1 &
        runner $! "Apache Installation"
    else
        echo -e "${YELLOW}Apache already installed${NC}"
    fi
    systemctl enable --now apache2 >> "$LOGFILE" 2>&1 || true
}

install_php() {
    echo -e "${GREEN}Installing PHP...${NC}"
    if ! is_installed php; then
        apt install -y php php-mbstring php-zip php-gd php-json php-curl php-mysql >> "$LOGFILE" 2>&1 &
        runner $! "PHP Installation"
    else
        echo -e "${YELLOW}PHP already installed${NC}"
    fi
}

install_ssh() {
    echo -e "${GREEN}Installing SSH...${NC}"
    if ! is_installed openssh-server; then
        apt install -y openssh-server >> "$LOGFILE" 2>&1 &
        runner $! "SSH Installation"
    else
        echo -e "${YELLOW}SSH already installed${NC}"
    fi
    systemctl enable --now ssh >> "$LOGFILE" 2>&1 || true
}

install_mosquitto() {
    echo -e "${GREEN}Installing Mosquitto...${NC}"
    if ! is_installed mosquitto; then
        apt install -y mosquitto mosquitto-clients >> "$LOGFILE" 2>&1 &
        runner $! "Mosquitto Installation"
    else
        echo -e "${YELLOW}Mosquitto already installed${NC}"
    fi
    systemctl enable --now mosquitto >> "$LOGFILE" 2>&1 || true
}

install_mariadb() {
    echo -e "${GREEN}Installing MariaDB...${NC}"
    if ! is_installed mariadb-server; then
        apt install -y mariadb-server >> "$LOGFILE" 2>&1 &
        runner $! "MariaDB Installation"
    else
        echo -e "${YELLOW}MariaDB already installed${NC}"
    fi
    systemctl enable --now mariadb >> "$LOGFILE" 2>&1 || true

    echo "Database configuration:"
    read -rp "Username: " DB_USER
    read -rsp "Password: " DB_PASS; echo
    read -rp "Database name: " DB_NAME

    mysql -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME};" || true
    mysql -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';" || true
    mysql -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';" || true
    mysql -e "FLUSH PRIVILEGES;" || true
    
    echo -e "${GREEN}[✓] Database configured!${NC}"
}

install_node_red() {
    echo -e "${GREEN}Installing Node-RED...${NC}"
    command -v curl >/dev/null || apt install -y curl >> "$LOGFILE" 2>&1
    curl -fsSL https://raw.githubusercontent.com/node-red/linux-installers/master/deb/update-nodejs-and-nodered | bash >> "$LOGFILE" 2>&1 &
    runner $! "Node-RED Installation"
    systemctl enable --now nodered.service >> "$LOGFILE" 2>&1 || true
}

install_phpmyadmin() {
    echo -e "${GREEN}Installing phpMyAdmin...${NC}"
    if ! is_installed phpmyadmin; then
        apt install -y phpmyadmin >> "$LOGFILE" 2>&1 &
        runner $! "phpMyAdmin Installation"
    else
        echo -e "${YELLOW}phpMyAdmin already installed${NC}"
    fi
}

install_docker() {
    echo -e "${GREEN}Installing Docker...${NC}"
    if ! is_installed docker.io; then
        apt install -y docker.io docker-compose >> "$LOGFILE" 2>&1 &
        runner $! "Docker Installation"
    else
        echo -e "${YELLOW}Docker already installed${NC}"
    fi
    systemctl enable --now docker >> "$LOGFILE" 2>&1 || true
}

install_security() {
    echo -e "${GREEN}Installing UFW + Fail2Ban...${NC}"
    apt install -y ufw fail2ban >> "$LOGFILE" 2>&1 &
    runner $! "Security Setup"

    # Check if ufw is installed
    if ! command -v ufw &> /dev/null; then
        echo -e "${RED}[✗] UFW installation failed - command not found${NC}"
        log "ERROR: UFW command not found after installation"
        return 1
    fi

    ufw default deny incoming || true
    ufw default allow outgoing || true
    ufw allow 22/tcp || true
    ufw allow 80/tcp || true
    ufw allow 1883/tcp || true
    ufw --force enable || true

    systemctl enable --now fail2ban >> "$LOGFILE" 2>&1 || true
    echo -e "${GREEN}[✓] Security configured!${NC}"
}

# ================= MAIN MENU LOOP =================

show_menu() {
    clear
    echo ""
    echo -e "${CYAN}════════════════════════════════════${NC}"
    echo -e "${CYAN}║${NC}    ${MAGENTA}DEBIAN INSTALLER MENU${NC}    ${CYAN}║${NC}"
    echo -e "${CYAN}════════════════════════════════════${NC}"
    echo ""
    echo -e "${YELLOW}1)${NC} Node-RED"
    echo -e "${YELLOW}2)${NC} Apache + PHP"
    echo -e "${YELLOW}3)${NC} Mosquitto MQTT"
    echo -e "${YELLOW}4)${NC} SSH"
    echo -e "${YELLOW}5)${NC} phpMyAdmin"
    echo -e "${YELLOW}6)${NC} Docker"
    echo -e "${YELLOW}7)${NC} Security (UFW + Fail2Ban)"
    echo -e "${YELLOW}8)${NC} System Update"
    echo -e "${YELLOW}9)${NC} Check Installation Status"
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
        case $choice in
            1) install_node_red ;;
            2) install_apache; install_php; ask_yes_no "Install MariaDB too?" && install_mariadb ;;
            3) install_mosquitto ;;
            4) install_ssh ;;
            5) install_apache; install_php; install_phpmyadmin ;;
            6) install_docker ;;
            7) install_security ;;
            8) echo -e "${BLUE}Updating system...${NC}"; apt update >> "$LOGFILE" 2>&1 & runner $! "System Update" ;;
            9) check_installed_packages ;;
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
echo ""
echo -e "${CYAN}════════════════════════════════════${NC}"
echo -e "${CYAN}║${NC}    ${GREEN}✓ INSTALLATION COMPLETE! ✓${NC}    ${CYAN}║${NC}"
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
