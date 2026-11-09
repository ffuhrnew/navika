#!/bin/bash
# Setzt den NomadNet-Anzeigenamen (display_name in ~/.nomadnetwork/storage/peersettings).
# Name: NOMADNET_DISPLAY_NAME aus /etc/navika.env, leer = <Hostname>_OP.
# NomadNet schreibt peersettings bei jedem Speichern neu, deshalb wird nur bei gestopptem Dienst geaendert.
set -eu
[ "$(id -un)" = "pi" ] || { echo "Muss als pi laufen (sudo -u pi -H)." >&2; exit 1; }
[ -f /etc/navika.env ] && source /etc/navika.env
NAME="${NOMADNET_DISPLAY_NAME:-$(hostname)_OP}"
PY="${HOME}/.local/share/pipx/venvs/nomadnet/bin/python3"
PS="${PEERSETTINGS:-$HOME/.nomadnetwork/storage/peersettings}"
SC="${SYSTEMCTL:-sudo systemctl}"

if [ ! -f "$PS" ]; then
    echo "peersettings fehlt - starte nomadnet einmal, damit es angelegt wird."
    $SC start nomadnet
    for _ in $(seq 1 60); do [ -f "$PS" ] && break; sleep 1; done
    [ -f "$PS" ] || { echo "peersettings wurde nicht angelegt." >&2; exit 1; }
    sleep 2
fi

$SC stop nomadnet
trap 'rc=$?; [ "$rc" -eq 0 ] || $SC start nomadnet' EXIT
cp -a "$PS" "$PS.bak"
NAME="$NAME" PS="$PS" "$PY" -c '
import RNS.vendor.umsgpack as m, os
p = os.environ["PS"]
d = m.unpack(open(p, "rb"))
d["display_name"] = os.environ["NAME"]
m.pack(d, open(p, "wb"))
print("display_name:", d["display_name"])'
$SC start nomadnet
