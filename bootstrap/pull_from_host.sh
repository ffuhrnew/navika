#!/bin/bash
# LÄUFT LOKAL AUF DEM FRISCHEN NODE!
set -e

[ -f /etc/navika.env ] && source /etc/navika.env

DEPLOY_HOST_IP="${DEPLOY_HOST_IP:-<DEPLOY_HOST_IP>}"
DEPLOY_USER="${DEPLOY_USER:-pi}"
DEPLOY_REPO_PATH="${DEPLOY_REPO_PATH:-~/build/navika}"

if [ "$DEPLOY_HOST_IP" = "<DEPLOY_HOST_IP>" ]; then
    echo "FEHLER: Bitte DEPLOY_HOST_IP in /etc/navika.env oder direkt im Skript setzen."
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
