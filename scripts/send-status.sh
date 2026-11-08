#!/bin/bash
[ -f /etc/navika.env ] && source /etc/navika.env

TARGET="${STATUS_DEST_HASH:-}"
NOTIFY_BIN="/usr/local/bin/rns-notify.py"
RNSTATUS_BIN="$HOME/.local/bin/rnstatus"
PATH="/usr/local/bin:/usr/bin:/bin:$HOME/.local/bin"

if [ -z "$TARGET" ]; then
    echo "HINWEIS: STATUS_DEST_HASH nicht in /etc/navika.env gesetzt."
    exit 0
fi

HOST=$(hostname)
RAM=$(free -h)
RNS=$($RNSTATUS_BIN)

MSG="Node: $HOST

--- RAM ---
$RAM

--- RNS ---
$RNS"

$NOTIFY_BIN "$TARGET" "$MSG"
