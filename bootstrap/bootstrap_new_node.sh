#!/bin/bash
# Läuft EINMALIG auf frisch geflashter SD-Karte (Raspberry Pi OS Lite 64-bit, Trixie).
set -e
bash "$(dirname "$0")/../scripts/navika-config-wizard.sh"
echo "--- apt update/upgrade ---"
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get -y full-upgrade
sudo apt-get -y autoremove

echo "--- Basis-Pakete ---"
sudo apt-get install -y fake-hwclock \
    git curl nano jq wget \
    python3 python3-pip python3-venv python3-dev \
    build-essential gcc \
    libusb-1.0-0 libusb-1.0-0-dev libudev-dev \
    pipx network-manager bluez bluez-tools \
    iproute2 iputils-ping netcat-openbsd dnsutils procps ssh

echo "--- Bluetooth ---"
sudo systemctl enable bluetooth.service
sudo systemctl start bluetooth.service
sudo rfkill unblock bluetooth || true

echo "--- NetworkManager ---"
sudo systemctl enable NetworkManager
sudo systemctl start NetworkManager

echo "--- pipx ---"
python3 -m pipx ensurepath
export PATH="$PATH:/home/pi/.local/bin"

echo "--- pipx venv: rns ---"
pipx install rns
pipx inject rns lxmf

echo "--- pipx venv: nomadnet ---"
pipx install nomadnet

echo "--- pipx venv: meshcore-cli ---"
pipx install meshcore-cli || echo "WARNUNG: meshcore-cli fehlgeschlagen, ggf. später nachholen."

echo "--- pipx venv: meshtastic ---"
pipx install meshtastic

echo "--- Gruppen ---"
sudo usermod -aG dialout pi
sudo usermod -aG bluetooth pi

echo "--- Zeitzone ---"
sudo timedatectl set-timezone Europe/Berlin

echo "--- SSH ---"
sudo systemctl enable ssh
sudo systemctl start ssh

echo "--- IPv6 global deaktivieren ---"
echo "net.ipv6.conf.all.disable_ipv6 = 1" | sudo tee /etc/sysctl.d/99-disable-ipv6.conf > /dev/null


echo ""
echo "Bootstrap fertig. Installierte pipx venvs:"
pipx list

echo "Nächster Schritt: sudo reboot, danach per SSH:"
echo "  ~/deploy/navika/finalize/setup_new_rns_node.sh"
