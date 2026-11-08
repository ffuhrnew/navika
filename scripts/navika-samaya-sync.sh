#!/bin/bash
# Stellt die Systemuhr per Samaya (Reticulum-Zeitserver). Aufruf durch samaya-sync.service als root.
# Optionen aus /etc/navika.env: SAMAYA_ENABLE, SAMAYA_TIME_SERVER_KEY (128 Hex-Zeichen), RNS_USER.
set -eu
ENVF="${NAVIKA_ENV:-/etc/navika.env}"
[ -f "$ENVF" ] && source "$ENVF"
if [ "${SAMAYA_ENABLE:-no}" != "yes" ]; then
    echo "SAMAYA_ENABLE nicht yes - nichts zu tun."
    exit 0
fi
KEY="${SAMAYA_TIME_SERVER_KEY:-}"
[[ "$KEY" =~ ^[0-9a-fA-F]{128}$ ]] || { echo "SAMAYA_TIME_SERVER_KEY fehlt oder ist ungueltig (128 Hex-Zeichen)." >&2; exit 1; }
USR="${RNS_USER:-pi}"
BIN="${SAMAYA_BIN:-/home/${USR}/.local/bin/samaya}"
exec "$BIN" sync --rns-config "/home/${USR}/.reticulum" "$KEY"
