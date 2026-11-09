#!/bin/bash
set -e

# Ziel-WLANs aus /etc/navika.env laden oder Fallback nutzen
[ -f /etc/navika.env ] && source /etc/navika.env

# Ohne eigene Ziel-WLANs (oder mit den Platzhaltern der Vorlage) nicht weitermachen
if [ "${#TARGET_NETWORKS[@]}" -eq 0 ] || [[ " ${TARGET_NETWORKS[*]} " == *" WLAN_SSID_"* ]]; then
    echo "FEHLER: TARGET_NETWORKS fehlt oder enthaelt noch die Platzhalter (WLAN_SSID_1 ...)."
    echo "Bitte in /etc/navika.env die echten WLAN-Namen eintragen, z. B.:"
    echo "  TARGET_NETWORKS=(\"MeinWLAN\")"
    echo "Danach erneut starten: /home/pi/deploy/navika/scripts/wlan-creator.sh"
    exit 1
fi

echo "======================================================"
echo " WLAN CREATOR: RADIKALE FELDKONFIGURATION"
echo "======================================================"

read -s -p "1. BITTE WLAN-PASSWORT FÜR DIE CLIENT-NETZE EINGEBEN: " WIFI_PASS
echo ""
if [ -z "$WIFI_PASS" ]; then
    echo "FEHLER: Client-Passwort darf nicht leer sein!"
    exit 1
fi

read -s -p "2. BITTE WLAN-PASSWORT FÜR DEN EIGENEN AP EINGEBEN: " AP_PASS
echo ""
if [ "${#AP_PASS}" -lt 8 ] || [ "${#AP_PASS}" -gt 63 ]; then
    echo "FEHLER: AP-Passwort muss 8 bis 63 Zeichen lang sein (WPA2)!"
    exit 1
fi

NODE_NAME=$(hostname)
AP_SSID="${NODE_NAME}-AP"

echo "------------------------------------------------------"
echo "=== 1. RADIKALE RASUR: Schalte ALLE WLAN-Profile stumm ==="
# Holt jedes WLAN-Profil (Ethernet u.a. bleiben unangetastet)
mapfile -t ALL_EXISTING < <(nmcli -t -f TYPE,NAME connection show | grep '^802-11-wireless:' | cut -d: -f2-)
for PROFILE in "${ALL_EXISTING[@]}"; do
    if [ -n "$PROFILE" ]; then
        sudo nmcli connection modify "$PROFILE" connection.autoconnect no connection.autoconnect-priority 0 &>/dev/null || true
        echo "[Befriedet] Autostart deaktiviert für: $PROFILE"
    fi
done

echo "------------------------------------------------------"
echo "=== 2. Client-WLAN-Profile passiv anlegen ==="
for SSID in "${TARGET_NETWORKS[@]}"; do
    if ! nmcli connection show "$SSID" &>/dev/null; then
        sudo nmcli connection add type wifi ifname wlan0 con-name "$SSID" ssid "$SSID" autoconnect no &>/dev/null
        echo "[OK] Profil für $SSID wurde neu angelegt."
    else
        echo "[INFO] Profil für $SSID existiert bereits."
    fi
    
    # IPv6 aus und strikt auf autoconnect=no zwingen
    sudo nmcli connection modify "$SSID" ipv6.method ignore &>/dev/null
    sudo nmcli connection modify "$SSID" connection.autoconnect no connection.autoconnect-priority 0 wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$WIFI_PASS" &>/dev/null
done

echo "------------------------------------------------------"
echo "=== 3. Echten Wald-AP anlegen & als EINZIGEN erzwingen ==="
sudo mkdir -p /etc/NetworkManager/system-connections
sudo rm -f "/etc/NetworkManager/system-connections/${AP_SSID}.nmconnection"
sudo install -m 600 -o root -g root /dev/null "/etc/NetworkManager/system-connections/${AP_SSID}.nmconnection"

sudo tee "/etc/NetworkManager/system-connections/${AP_SSID}.nmconnection" > /dev/null << NMEOF
[connection]
id=${AP_SSID}
type=wifi
interface-name=wlan0
autoconnect=true
autoconnect-priority=100

[wifi]
mode=ap
ssid=${AP_SSID}

[wifi-security]
group=ccmp;
key-mgmt=wpa-psk
pairwise=ccmp;
proto=rsn;
psk=${AP_PASS}

[ipv4]
method=shared

[ipv6]
method=ignore
NMEOF

sudo chmod 600 "/etc/NetworkManager/system-connections/${AP_SSID}.nmconnection"
echo "[OK] AP-Profil für ${AP_SSID} wurde passiv hinterlegt."

# Zwingt den NetworkManager, die Änderungen sofort aktiv zu fressen
sudo nmcli connection reload

# Erzwinge den AP-Start im Live-System
sudo nmcli connection modify "${AP_SSID}" connection.autoconnect yes connection.autoconnect-priority 100 &>/dev/null || true

echo "------------------------------------------------------"
echo "FELD-SETUP FERTIG! AP hat die absolute Macht, alle anderen schlafen."
echo "======================================================"
