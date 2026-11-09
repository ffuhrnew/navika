#!/bin/bash
# LÄUFT LOKAL AUF DEM FRISCHEN NODE!
set -e

[ -f /etc/navika.env ] && source /etc/navika.env

DEPLOY_HOST_IP="${DEPLOY_HOST_IP:-<DEPLOY_HOST_IP>}"
DEPLOY_USER="${DEPLOY_USER:-pi}"
DEPLOY_REPO_PATH="${DEPLOY_REPO_PATH:-~/build/navika}"

if [ "$DEPLOY_HOST_IP" = "<DEPLOY_HOST_IP>" ]; then
    cat << 'MSG'
FEHLER: DEPLOY_HOST_IP ist nicht gesetzt.

Lege /etc/navika.env mit den Angaben zum Deploy-Host an, zum Beispiel so:

  sudo tee /etc/navika.env > /dev/null << 'EOF'
  DEPLOY_HOST_IP="192.168.1.10"
  DEPLOY_USER="pi"
  DEPLOY_REPO_PATH="~/build/navika"
  TARGET_NETWORKS=("MeinWLAN")
  EOF

DEPLOY_HOST_IP ist Pflicht. DEPLOY_USER und DEPLOY_REPO_PATH sind optional,
oben stehen ihre Standardwerte. TARGET_NETWORKS braucht spaeter wlan-creator.sh.
Danach dieses Skript erneut starten.
MSG
    exit 1
fi

# Erreichbarkeit des SSH-Ports pruefen (ohne Passwortabfrage)
if ! timeout 5 bash -c "</dev/tcp/${DEPLOY_HOST_IP}/22" 2>/dev/null; then
    echo "FEHLER: Deploy-Host ${DEPLOY_HOST_IP} ist auf Port 22 nicht erreichbar."
    echo "Bitte DEPLOY_HOST_IP in /etc/navika.env pruefen (Tippfehler? Host im selben Netz?)."
    exit 1
fi

echo "======================================================"
echo " PULL DEPLOYMENT: NODE <- DEPLOY HOST"
echo "======================================================"

mkdir -p ~/deploy/navika

rsync -avz \
    --exclude='.git/' \
    --exclude='.gitignore' \
    --exclude='README.md' \
    --exclude='docs/' \
    ${DEPLOY_USER}@${DEPLOY_HOST_IP}:${DEPLOY_REPO_PATH}/ ~/deploy/navika/

echo "======================================================"
echo " ERFOLG: Daten liegen sauber in ~/deploy/navika/"
echo "======================================================"
