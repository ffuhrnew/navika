#!/bin/bash
# Legt /etc/navika.env aus der Vorlage an und fragt die Pflichtwerte ab.
# Eine vorhandene /etc/navika.env wird nie ueberschrieben.
set -eu
ENVF=/etc/navika.env
SRC="$(cd "$(dirname "$0")/.." && pwd)/config-templates/navika.env.example"

if [ -f "$ENVF" ]; then
    echo "$ENVF existiert bereits - Wizard uebersprungen."
    exit 0
fi
[ -f "$SRC" ] || { echo "Vorlage fehlt: $SRC" >&2; exit 1; }

echo "=== NAVIKA KONFIGURATION ==="
while true; do
    read -r -p "Hostname des Nodes: " HN
    [[ "$HN" =~ ^[A-Za-z0-9][A-Za-z0-9-]*$ ]] && break
    echo "Ungueltig (Buchstaben, Ziffern, Bindestrich)."
done
while true; do
    read -r -p "IP des Deploy-Hosts: " IP
    [[ "$IP" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] && break
    echo "Ungueltige IPv4-Adresse."
done
NETS=""
echo "Client-WLANs (leer = fertig, mindestens eines):"
while true; do
    read -r -p "SSID: " S
    if [ -z "$S" ]; then
        [ -n "$NETS" ] && break
        echo "Mindestens ein WLAN."
        continue
    fi
    if [[ "$S" == WLAN_SSID_* || "$S" == *[\"\$\\\`]* ]]; then
        echo "Ungueltige SSID."
        continue
    fi
    NETS="${NETS:+$NETS }\"$S\""
done

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT
while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
        NODE_HOSTNAME=*)   echo "NODE_HOSTNAME=\"$HN\"" ;;
        DEPLOY_HOST_IP=*)  echo "DEPLOY_HOST_IP=\"$IP\"" ;;
        TARGET_NETWORKS=*) echo "TARGET_NETWORKS=($NETS)" ;;
        *)                 printf '%s\n' "$line" ;;
    esac
done < "$SRC" > "$TMP"
sudo install -m 644 -o root -g root "$TMP" "$ENVF"
echo "$ENVF angelegt."
