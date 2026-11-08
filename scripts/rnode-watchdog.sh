#!/bin/bash
[ -f /etc/navika.env ] && source /etc/navika.env

LOGFILE="/var/log/rnode-watchdog.log"
FAILCOUNT_FILE="/run/rnode-watchdog-failcount"
LASTRESTART_FILE="/run/rnode-watchdog-lastrestart"
COOLDOWN=180
RNS_USER="${RNS_USER:-pi}"
RNS_HOME="/home/${RNS_USER}"
RNSCONFIG="${RNS_HOME}/.reticulum"
NOTIFY_DEST_HASH="${NOTIFY_DEST_HASH:-}"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOGFILE"
}

NOW=$(date +%s)
LASTRESTART=$(cat "$LASTRESTART_FILE" 2>/dev/null || echo 0)
SINCE_RESTART=$((NOW - LASTRESTART))

if [ "$SINCE_RESTART" -lt "$COOLDOWN" ]; then
  log "Cooldown aktiv (${SINCE_RESTART}s seit letztem Neustart) - ueberspringe Check"
  exit 0
fi

for SVC in rnsd nomadnet rnsh rncp rnx; do
  systemctl is-enabled --quiet "$SVC" || continue
  if ! systemctl is-active --quiet "$SVC"; then
    log "$SVC Prozess nicht aktiv - starte neu"
    systemctl restart "$SVC"
    [ "$SVC" = "rnsd" ] && echo "$NOW" > "$LASTRESTART_FILE" && exit 0
  fi
done

STATUS=$(sudo -u "$RNS_USER" "${RNS_HOME}/.local/bin/rnstatus" --config "$RNSCONFIG" 2>&1)
RNODE_BLOCK=$(echo "$STATUS" | awk '/RNodeInterface/{f=1} f{print; if (/Status/) exit}')
INTERFACE_UP=$(echo "$RNODE_BLOCK" | grep -c "Status.*: Up")

if [ "$INTERFACE_UP" -eq 0 ]; then
  FAILCOUNT=$(cat "$FAILCOUNT_FILE" 2>/dev/null || echo 0)
  FAILCOUNT=$((FAILCOUNT + 1))
  echo "$FAILCOUNT" > "$FAILCOUNT_FILE"
  log "RNode-Interface nicht Up (Versuch $FAILCOUNT). Rohdaten: $(echo "$STATUS" | tr '\n' ' ' | head -c 300)"

  if [ "$FAILCOUNT" -ge 3 ]; then
    log "RNode-Interface seit 3 Checks down - fuehre vollstaendigen Reboot durch"
    if [ -n "$NOTIFY_DEST_HASH" ]; then
      sudo -u "$RNS_USER" /usr/local/bin/rns-notify.py "$NOTIFY_DEST_HASH" "$(hostname): Watchdog loest Reboot aus wegen RNode-Ausfall" &
      sleep 15
    fi
    echo "0" > "$FAILCOUNT_FILE"
    reboot
  else
    log "Starte rnsd neu (Versuch $FAILCOUNT von 3 vor Reboot)"
    systemctl restart rnsd
    echo "$NOW" > "$LASTRESTART_FILE"
  fi
else
  echo "0" > "$FAILCOUNT_FILE"
  log "Check OK - Interface Up"
fi
