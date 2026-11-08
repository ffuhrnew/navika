#!/bin/bash
# Startet rnsh/rncp/rnx als Listener, nur mit Allowlist (ALLOWED_IDENTITIES in /etc/navika.env).
set -eu
[ -f /etc/navika.env ] && source /etc/navika.env
BIN="${HOME}/.local/bin"
ARGS=()
for h in ${ALLOWED_IDENTITIES:-}; do
    [[ "$h" =~ ^[0-9a-fA-F]{32}$ ]] || { echo "Ungueltiger Hash in ALLOWED_IDENTITIES: $h" >&2; exit 1; }
    ARGS+=(-a "$h")
done
if [ "${#ARGS[@]}" -eq 0 ]; then
    echo "ALLOWED_IDENTITIES leer - Listener ${1:-?} startet nicht." >&2
    exit 0
fi
case "${1:-}" in
    rnsh) exec "$BIN/rnsh" -l "${ARGS[@]}" -b 900 -- /bin/bash ;;
    rncp) exec "$BIN/rncp" -l "${ARGS[@]}" -b 900 ;;
    rnx)  exec "$BIN/rnx" -l "${ARGS[@]}" ;;
    *)    echo "Usage: $0 rnsh|rncp|rnx" >&2; exit 2 ;;
esac
