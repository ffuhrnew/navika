#!/bin/bash
# Richtet optional eine NomadNet-Node ein: [node] in der NomadNet-Config, Start- und Statusseite.
# Optionen aus /etc/navika.env (alle optional, fehlende Werte werden abgefragt):
#   NOMADNET_NODE=yes|no            Node einrichten (leer = fragen)
#   NOMADNET_NODE_NAME              Name der Node (Standard: <HOSTNAME>-NODE in Grossbuchstaben)
#   NOMADNET_STATUS_PAGE=yes|no     Start- und Statusseite bauen (leer = fragen)
#   NOMADNET_STATUS_ALLOWED_FILE    Datei mit "hash,name"-Zeilen fuer die Allow-Liste (leer = abfragen)
#   NOMADNET_OPERATOR_LXMF          LXMF-Adresse des Operators fuer die Startseite (leer = Zeile entfaellt)
#   NOMADNET_DISPLAY_NAME           Operatorname (leer = <Hostname>_OP)
# NomadNet schreibt seine Dateien selbst; deshalb wird der Dienst vor den Aenderungen gestoppt.
set -eu
[ "$(id -un)" = "pi" ] || { echo "Muss als pi laufen (sudo -u pi -H)." >&2; exit 1; }
ENVF="${NAVIKA_ENV:-/etc/navika.env}"
[ -f "$ENVF" ] && source "$ENVF"
HOME_DIR="${NOMADNET_HOME:-$HOME/.nomadnetwork}"
CFG="$HOME_DIR/config"
PAGES="$HOME_DIR/storage/pages"
TPL="${NAVIKA_TEMPLATES:-/home/pi/deploy/navika/nomadnet-templates}"
SC="${SYSTEMCTL:-sudo systemctl}"
TS=$(date +%Y%m%d-%H%M%S)
HOST=$(hostname)
OKNAME='^[A-Za-z0-9][A-Za-z0-9 ._-]*$'
OKLINE='^[0-9a-fA-F]{32},[A-Za-z0-9][A-Za-z0-9 ._-]*$'

ask_yn() { local a=""; read -r -p "$1 (j/N): " a || true; [[ "$a" =~ ^[jJyY]$ ]]; }

# --- 1. Abfragen und pruefen (noch nichts geaendert) ---
case "${NOMADNET_NODE:-}" in
    yes) ;;
    no)  echo "NomadNet-Node: aus."; exit 0 ;;
    *)   ask_yn "NomadNet-Node starten?" || { echo "NomadNet-Node uebersprungen."; exit 0; } ;;
esac

DEFNAME="$(echo "$HOST" | tr '[:lower:]' '[:upper:]')-NODE"
NAME="${NOMADNET_NODE_NAME:-}"
if [ -z "$NAME" ]; then
    read -r -p "Name der Node [$DEFNAME]: " NAME || NAME=""
    NAME="${NAME:-$DEFNAME}"
fi
[[ "$NAME" =~ $OKNAME ]] || { echo "Ungueltiger Node-Name: $NAME" >&2; exit 1; }

PAGE=no
case "${NOMADNET_STATUS_PAGE:-}" in
    yes) PAGE=yes ;;
    no)  ;;
    *)   if ask_yn "Start- und Statusseite mit Allow-Liste bauen?"; then PAGE=yes; fi ;;
esac

if [ "$PAGE" = yes ]; then
    OPNAME="${NOMADNET_DISPLAY_NAME:-${HOST}_OP}"
    [[ "$OPNAME" =~ $OKNAME ]] || { echo "Ungueltiger Operatorname: $OPNAME" >&2; exit 1; }
    OPLXMF="${NOMADNET_OPERATOR_LXMF:-}"
    if [ -n "$OPLXMF" ] && ! [[ "$OPLXMF" =~ ^[0-9a-fA-F]{32}$ ]]; then
        echo "Ungueltige NOMADNET_OPERATOR_LXMF (32 Hex-Zeichen)." >&2; exit 1
    fi
    for f in index.mu status.mu; do
        [ -f "$TPL/$f" ] || { echo "Vorlage fehlt: $TPL/$f" >&2; exit 1; }
    done
    ALLOWTMP=$(mktemp)
    trap 'rm -f "$ALLOWTMP"' EXIT
    echo "# status_allowed - Format: hash,name (Kommentare mit #)" > "$ALLOWTMP"
    if [ -n "${NOMADNET_STATUS_ALLOWED_FILE:-}" ]; then
        case "$NOMADNET_STATUS_ALLOWED_FILE" in
            /*) ;;
            *) echo "NOMADNET_STATUS_ALLOWED_FILE muss ein absoluter Pfad sein (z. B. /home/pi/status-allowed.txt), steht aber: $NOMADNET_STATUS_ALLOWED_FILE" >&2; exit 1 ;;
        esac
        [ -f "$NOMADNET_STATUS_ALLOWED_FILE" ] || { echo "Allow-Datei nicht gefunden: $NOMADNET_STATUS_ALLOWED_FILE" >&2; echo "Inhalt je Zeile: <32 Hex-Zeichen Identity-Hash>,<Name>. Ohne NOMADNET_STATUS_ALLOWED_FILE fragt das Skript die Liste interaktiv ab." >&2; exit 1; }
        n=0
        while IFS= read -r line || [ -n "$line" ]; do
            n=$((n+1))
            l="${line%%#*}"
            l="${l#"${l%%[![:space:]]*}"}"; l="${l%"${l##*[![:space:]]}"}"
            [ -z "$l" ] && continue
            [[ "$l" =~ $OKLINE ]] || { echo "Ungueltige Zeile $n in der Allow-Datei." >&2; exit 1; }
            echo "$l" >> "$ALLOWTMP"
        done < "$NOMADNET_STATUS_ALLOWED_FILE"
    else
        echo "Allow-Liste der Statusseite: Identity-Hash und Name eintragen (leerer Hash = fertig)."
        while true; do
            read -r -p "Identity-Hash (leer = fertig): " H || H=""
            [ -n "$H" ] || break
            [[ "$H" =~ ^[0-9a-fA-F]{32}$ ]] || { echo "Ungueltiger Hash (32 Hex-Zeichen), nochmal."; continue; }
            read -r -p "Name: " N || N=""
            [[ "$N" =~ $OKNAME ]] || { echo "Ungueltiger Name, nochmal."; continue; }
            echo "$H,$N" >> "$ALLOWTMP"
        done
    fi
    CNT=$(grep -vc '^#' "$ALLOWTMP" || true)
    [ "$CNT" -gt 0 ] || echo "WARNUNG: Allow-Liste ist leer - niemand kann die Statusseite sehen."
fi

if [ ! -f "$CFG" ]; then
    echo "NomadNet-Config fehlt - starte nomadnet einmal, damit sie angelegt wird."
    $SC start nomadnet
    for _ in $(seq 1 60); do [ -f "$CFG" ] && break; sleep 1; done
    sleep 2
fi
[ -f "$CFG" ] || { echo "NomadNet-Config fehlt ($CFG) - nomadnet konnte die Config nicht anlegen." >&2; exit 1; }

# --- 2. Anwenden ---
$SC stop nomadnet
trap 'rc=$?; rm -f "${ALLOWTMP:-}"; [ "$rc" -eq 0 ] || $SC start nomadnet' EXIT
cp -a "$CFG" "$CFG.bak.$TS"
awk -v name="$NAME" '
    /^\[/ { sec = $0 }
    sec ~ /^\[node\]/ && /^[ \t]*enable_node[ \t]*=/ { print "enable_node = yes"; next }
    sec ~ /^\[node\]/ && /^[ \t]*node_name[ \t]*=/   { print "node_name = " name; next }
    { print }' "$CFG.bak.$TS" > "$CFG"
if ! { grep -q '^enable_node = yes' "$CFG" && grep -q "^node_name = $NAME\$" "$CFG"; }; then
    echo "Config-Aenderung fehlgeschlagen, stelle die Sicherung wieder her." >&2
    cp -a "$CFG.bak.$TS" "$CFG"; $SC start nomadnet; exit 1
fi

if [ "$PAGE" = yes ]; then
    mkdir -p "$PAGES"
    for f in index.mu status.mu status_allowed; do
        if [ -e "$PAGES/$f" ]; then mv "$PAGES/$f" "$PAGES/$f.bak.$TS"; fi
    done
    sed -e "s/@NODE_NAME@/$NAME/" -e "s/@OPERATOR_NAME@/$OPNAME/" "$TPL/index.mu" > "$PAGES/index.mu"
    if [ -n "$OPLXMF" ]; then
        sed -i "s/@OPERATOR_LXMF@/$OPLXMF/" "$PAGES/index.mu"
    else
        sed -i '/^LXMF: @OPERATOR_LXMF@$/d' "$PAGES/index.mu"
    fi
    cp "$TPL/status.mu" "$PAGES/status.mu"
    cp "$ALLOWTMP" "$PAGES/status_allowed"
    chmod 755 "$PAGES/status.mu"; chmod 644 "$PAGES/index.mu" "$PAGES/status_allowed"
fi

$SC start nomadnet
echo "NomadNet-Node eingerichtet: $NAME"
