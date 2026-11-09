#!/bin/bash
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}=== Aktuell aktiv auf wlan0 ===${NC}"
AKTIV=$(nmcli -t -f DEVICE,CONNECTION device status | grep "^wlan0:" | cut -d: -f2)
echo -e "${GREEN}${AKTIV:-Keines}${NC}\n"

echo -e "${BLUE}=== WLAN-Auswahl für den NÄCHSTEN REBOOT ===${NC}"
mapfile -t PROFILES < <(nmcli -t -f TYPE,NAME connection show | grep "^802-11-wireless:" | cut -d: -f2)

if [ ${#PROFILES[@]} -eq 0 ]; then
    echo "Keine Profile da."
    exit 1
fi

echo -e " [0] ${YELLOW}KEIN WLAN (Vollständig deaktivieren für nächsten Boot)${NC}"

for i in "${!PROFILES[@]}"; do
    NAME="${PROFILES[$i]}"
    INFO=$(nmcli -g connection.autoconnect,connection.autoconnect-priority connection show "$NAME" 2>/dev/null)
    echo -e "[$((i+1))] ${YELLOW}$NAME${NC} (Autostart: $(echo "$INFO" | sed -n '1p') | Prio: $(echo "$INFO" | sed -n '2p'))"
done
echo ""

read -p "Nummer wählen (0-${#PROFILES[@]}) oder 'q': " CHOICE

if [ "$CHOICE" = "0" ]; then
    echo "Konfiguriere Profile... Schalte alle WLAN-Autostarts AUS."
    for NAME in "${PROFILES[@]}"; do
        sudo nmcli connection modify "$NAME" connection.autoconnect no connection.autoconnect-priority 0 &>/dev/null
    done
    echo -e "\n${GREEN}[ERFOLG] Konfiguriert!${NC}"
    echo -e "${GREEN}Beim nächsten Boot wird sich wlan0 mit KEINEM Netzwerk verbinden.${NC}"
    echo "Deine aktuelle Verbindung bleibt JETZT stabil."

elif [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -ge 1 ] && [ "$CHOICE" -le "${#PROFILES[@]}" ]; then
    TARGET="${PROFILES[$((CHOICE-1))]}"
    
    echo "Konfiguriere Profile... Bitte warten."

    # Alle Profile lahmlegen, AUSSER dem ausgewählten Zielprofil
    for NAME in "${PROFILES[@]}"; do
        if [ "$NAME" != "$TARGET" ]; then
            sudo nmcli connection modify "$NAME" connection.autoconnect no connection.autoconnect-priority 0 &>/dev/null
        fi
    done
    
    # Nur das gewählte Zielprofil scharf schalten und auf Prio 100 zwingen
    sudo nmcli connection modify "$TARGET" connection.autoconnect yes connection.autoconnect-priority 100 &>/dev/null
    
    echo -e "\n${GREEN}[ERFOLG] Konfiguriert!${NC}"
    echo -e "Beim nächsten Boot startet: ${GREEN}$TARGET${NC}"
    echo "Deine aktuelle Verbindung bleibt JETZT stabil."
else
    echo "Abgebrochen."
fi
