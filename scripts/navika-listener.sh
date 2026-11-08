#!/bin/bash
# Startet rnsh/rncp/rnx als Listener, nur mit Allowlist je Dienst (ALLOWED_IDENTITIES_<DIENST> in /etc/navika.env).
set -eu
[ -f /etc/navika.env ] && source /etc/navika.env
BIN="${HOME}/.local/bin"
SVC="${1:-}"
case "$SVC" in rnsh|rncp|rnx) ;; *) echo "Usage: $0 rnsh|rncp|rnx" >&2; exit 2 ;; esac
VAR="ALLOWED_IDENTITIES_${SVC^^}"
ARGS=()
for h in ${!VAR:-}; do
    [[ "$h" =~ ^[0-9a-fA-F]{32}$ ]] || { echo "Ungueltiger Hash in $VAR: $h" >&2; exit 1; }
    ARGS+=(-a "$h")
done
if [ "${#ARGS[@]}" -eq 0 ]; then
    echo "$VAR leer - Listener $SVC startet nicht." >&2
    exit 0
fi
case "$SVC" in
    rnsh) exec "$BIN/rnsh" -l "${ARGS[@]}" -b 900 -- /bin/bash ;;
    rncp) exec "$BIN/rncp" -l "${ARGS[@]}" -b 900 ;;
    rnx)  exec "$BIN/rnx" -l "${ARGS[@]}" ;;
esac
