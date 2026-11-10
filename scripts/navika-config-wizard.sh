#!/bin/bash
# Legt /etc/navika.env aus der Vorlage an und fragt alle Werte ab.
# Eine vorhandene /etc/navika.env wird nie ueberschrieben.
set -eu
ENVF=/etc/navika.env
SRC="$(cd "$(dirname "$0")/.." && pwd)/config-templates/navika.env.example"

if [ -f "$ENVF" ]; then
    echo "$ENVF existiert bereits - Wizard uebersprungen."
    exit 0
fi
[ -f "$SRC" ] || { echo "Vorlage fehlt: $SRC" >&2; exit 1; }

RE_HOST='^[A-Za-z0-9][A-Za-z0-9-]*$'
RE_IP='^[0-9]{1,3}(\.[0-9]{1,3}){3}$'
RE_NAME='^[A-Za-z0-9][A-Za-z0-9 ._-]*$'
RE_HEX32='^[0-9a-fA-F]{32}$'
RE_HEX128='^[0-9a-fA-F]{128}$'

# ask_one PROMPT REGEX PFLICHT(1/0) -> REPLY
ask_one() {
    local v
    while true; do
        read -r -p "$1" v || v=""
        if [ -z "$v" ]; then
            [ "$3" = 0 ] && { REPLY=""; return; }
            echo "Pflichtangabe."
            continue
        fi
        [[ "$v" =~ $2 ]] && { REPLY="$v"; return; }
        echo "Ungueltige Eingabe."
    done
}

# ask_ids PROMPT -> REPLY (Liste aus 32-stelligen Hashes, leer erlaubt)
ask_ids() {
    local v h ok arr
    while true; do
        read -r -p "$1" v || v=""
        read -ra arr <<< "$v"
        ok=1
        for h in "${arr[@]}"; do
            [[ "$h" =~ $RE_HEX32 ]] || ok=0
        done
        [ "$ok" = 1 ] && { REPLY="${arr[*]}"; return; }
        echo "Ungueltig: je 32 Hex-Zeichen, durch Leerzeichen getrennt."
    done
}

# ask_yn PROMPT -> REPLY (yes/no)
ask_yn() {
    local v
    while true; do
        read -r -p "$1 (j/N): " v || v=""
        case "$v" in
            [jJyY])  REPLY=yes; return ;;
            ""|[nN]) REPLY=no; return ;;
        esac
    done
}

echo "=== NAVIKA KONFIGURATION ==="
ask_one "Hostname des Nodes: " "$RE_HOST" 1;  HN="$REPLY"
ask_one "IP des Deploy-Hosts (leer = nicht gesetzt, nur fuer den rsync-Weg noetig): " "$RE_IP" 0; IP="$REPLY"

NETS=""
echo "Client-WLANs (leer = fertig, mindestens eines):"
while true; do
    read -r -p "SSID: " S || S=""
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

ask_one "Ziel-Hash fuer Benachrichtigungen (leer = keiner): " "$RE_HEX32" 0; NOTIFY="$REPLY"
ask_one "Ziel-Hash fuer Statusmeldungen (leer = keiner): " "$RE_HEX32" 0;    STATUS="$REPLY"

echo "Listener-Freigaben: Identity-Hashes (je 32 Hex-Zeichen, durch Leerzeichen getrennt)."
echo "Leer = dieser Listener startet nicht."
ask_ids "Erlaubte Identities fuer rnsh: "; A_RNSH="$REPLY"
ask_ids "Erlaubte Identities fuer rncp: "; A_RNCP="$REPLY"
ask_ids "Erlaubte Identities fuer rnx: ";  A_RNX="$REPLY"

ask_yn "Zeitsynchronisation per Samaya einrichten?"; SAM="$REPLY"
SKEY=""
if [ "$SAM" = yes ]; then
    ask_one "Oeffentlicher Schluessel des Zeitservers (128 Hex-Zeichen): " "$RE_HEX128" 1; SKEY="$REPLY"
fi

ask_one "Anzeigename in NomadNet (leer = <Hostname>_OP): " "$RE_NAME" 0; DN="$REPLY"
ask_yn "Reticulum-TCP-Server (Port 4242) aktivieren?"; TCP="$REPLY"

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT
while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
        NODE_HOSTNAME=*)            echo "NODE_HOSTNAME=\"$HN\"" ;;
        DEPLOY_HOST_IP=*)           if [ -n "$IP" ]; then echo "DEPLOY_HOST_IP=\"$IP\""; else printf '%s\n' "$line"; fi ;;
        TARGET_NETWORKS=*)          echo "TARGET_NETWORKS=($NETS)" ;;
        NOTIFY_DEST_HASH=*)         echo "NOTIFY_DEST_HASH=\"$NOTIFY\"" ;;
        STATUS_DEST_HASH=*)         echo "STATUS_DEST_HASH=\"$STATUS\"" ;;
        ALLOWED_IDENTITIES_RNSH=*)  echo "ALLOWED_IDENTITIES_RNSH=\"$A_RNSH\"" ;;
        ALLOWED_IDENTITIES_RNCP=*)  echo "ALLOWED_IDENTITIES_RNCP=\"$A_RNCP\"" ;;
        ALLOWED_IDENTITIES_RNX=*)   echo "ALLOWED_IDENTITIES_RNX=\"$A_RNX\"" ;;
        SAMAYA_ENABLE=*)            echo "SAMAYA_ENABLE=\"$SAM\"" ;;
        SAMAYA_TIME_SERVER_KEY=*)   echo "SAMAYA_TIME_SERVER_KEY=\"$SKEY\"" ;;
        NOMADNET_DISPLAY_NAME=*)    echo "NOMADNET_DISPLAY_NAME=\"$DN\"" ;;
        TCP_SERVER=*)               echo "TCP_SERVER=\"$TCP\"" ;;
        *)                          printf '%s\n' "$line" ;;
    esac
done < "$SRC" > "$TMP"
sudo install -m 644 -o root -g root "$TMP" "$ENVF"
echo "$ENVF angelegt."
