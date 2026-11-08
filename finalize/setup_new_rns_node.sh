#!/bin/bash
# setup_node.sh
# Läuft LOKAL auf dem Node, aufgerufen nach dem Pull-Bootstrap aus dem Repo-Ordner.
set -e

TS=$(date +%Y%m%d_%H%M)
[ -f /etc/navika.env ] && source /etc/navika.env
# Wird von Root-Cronjobs per source geladen: root-eigen, nicht fuer andere schreibbar
[ -f /etc/navika.env ] && sudo chown root:root /etc/navika.env && sudo chmod 644 /etc/navika.env

echo "======================================================"
echo " CORE SETUP: FINALIZE NODE (SERVICES & IDENTITY)"
echo "======================================================"

# 1. Hostname abfragen
read -p "WIE SOLL DER HOST HEISSEN: " NODE_NAME
if [ -z "$NODE_NAME" ]; then
    echo "FEHLER: Hostname darf nicht leer sein!"
    exit 1
fi
echo "======================================================"

echo "--- 1. machine-id & SSH Host Keys ---"
sudo rm -f /etc/machine-id
sudo systemd-machine-id-setup
sudo rm -f /var/lib/dbus/machine-id
sudo ln -sf /etc/machine-id /var/lib/dbus/machine-id

# Host-Keys werden bewusst nicht regeneriert (Block deaktiviert)
#sudo mkdir -p /etc/ssh/old_keys_${TS}
#sudo mv /etc/ssh/ssh_host_* /etc/ssh/old_keys_${TS}/ 2>/dev/null || true
#sudo ssh-keygen -A

echo "--- 1b. SSH-Passwort-Authentifizierung (optional) ---"
# Optional: Passwort-Login erlauben (schwaecht die Absicherung)
read -p "SSH-Passwort-Login aktivieren? Das schwaecht die Absicherung (j/N): " SSH_PW
if [[ "$SSH_PW" =~ ^[Jj]$ ]]; then
    sudo sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
    sudo sed -i 's/^PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
    sudo systemctl reload ssh
fi

echo "--- 2. Identity-Backup ---"
mkdir -p ~/identity_backups
[ -d ~/.reticulum/storage ] && mv ~/.reticulum/storage ~/identity_backups/reticulum_storage_${TS} 2>/dev/null || true
[ -f ~/.nomadnetwork/storage/identity ] && mv ~/.nomadnetwork/storage/identity ~/identity_backups/nomadnet_identity_${TS} 2>/dev/null || true
[ -d ~/.reticulum/rns_notify ] && mv ~/.reticulum/rns_notify ~/identity_backups/rns_notify_${TS} 2>/dev/null || true

echo "--- 3. .reticulum/config ---"
mkdir -p ~/.reticulum
[ -f ~/.reticulum/config ] && cp ~/.reticulum/config ~/identity_backups/reticulum_config_${TS} || true
cat > ~/.reticulum/config << 'CFGEOF'
[reticulum]
  enable_transport = True
  share_instance = Yes
  respond_to_probes = Yes
  panic_on_interface_error = No

[logging]
  loglevel = 4

[interfaces]
  [[RNode LoRa Relay]]
    type = RNodeInterface
    port = /dev/ttyRNODE
    frequency = 869525000
    bandwidth = 125000
    txpower = 22
    spreadingfactor = 8
    codingrate = 5
    mode = full
    interface_enabled = true
    name = RNode LoRa Relay
    announce_rate_target = 3600
    announce_rate_grace = 360
CFGEOF

if [ "${TCP_SERVER:-no}" = "yes" ]; then
cat >> ~/.reticulum/config << 'TCPEOF'

  [[TCP Server]]
    type = TCPServerInterface
    interface_enabled = yes
    listen_ip = 0.0.0.0
    listen_port = 4242
TCPEOF
fi

echo "--- 4. Kopiere systemd Services aus systemd-templates ---"
sudo cp /home/pi/deploy/navika/systemd-templates/*.service /etc/systemd/system/

echo "--- 4b. Kopiere udev-Regel für das RNode-Interface ---"
sudo cp /home/pi/deploy/navika/udev-templates/99-rnode.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules && sudo udevadm trigger

echo "--- 5. systemd neu laden & aktivieren ---"
sudo systemctl daemon-reload
[ -d ~/.rnsh ] && mv ~/.rnsh ~/identity_backups/rnsh_dir_${TS} 2>/dev/null || true
sudo systemctl enable rnsd nomadnet &>/dev/null || true
# Listener nur mit Allowlist (ALLOWED_IDENTITIES in /etc/navika.env)
if grep -Eqs '^ALLOWED_IDENTITIES="[^"]+"' /etc/navika.env; then
    sudo systemctl enable rnsh rncp rnx &>/dev/null || true
else
    echo "HINWEIS: ALLOWED_IDENTITIES nicht gesetzt - rnsh/rncp/rnx bleiben deaktiviert."
fi

echo "--- 6. Kopiere und berechtige alle Wartungs-Skripte ---"
# Kopiert alle Skripte stumm nach /usr/local/bin/
sudo cp /home/pi/deploy/navika/scripts/{rnode-watchdog.sh,rns-announce-all.py,rns-notify.py,send-status.sh,navika-listener.sh} /usr/local/bin/
# Macht die Skripte erst auf dem Ziel-Dateisystem ausführbar
sudo chmod +x /usr/local/bin/{rnode-watchdog.sh,rns-announce-all.py,rns-notify.py,send-status.sh,navika-listener.sh}

# --- PATH-Erweiterung fuer Benutzer 'pi' (Permanent & Idempotent) ---
BASHRC="/home/pi/.bashrc"
PATH_LINE='export PATH="$HOME/deploy/navika/scripts:$PATH"'
if ! grep -Fq "$PATH_LINE" "$BASHRC"; then
    echo "" >> "$BASHRC"
    echo "# Navika Field Networks Script Path" >> "$BASHRC"
    echo "$PATH_LINE" >> "$BASHRC"
fi

echo "--- 7. Richte Cronjobs ein (Idempotent) ---"
sudo crontab /home/pi/deploy/navika/finalize/crontab_root.template
crontab /home/pi/deploy/navika/finalize/crontab_pi.template
echo "--- 8. Hostname finalisieren ---"
sudo sed -i "/127.0.1.1/d;\$a 127.0.1.1 ${NODE_NAME}" /etc/hosts
sudo hostnamectl set-hostname "${NODE_NAME}"

echo ""
echo "======================================================"
echo " SETUP ERFOLGREICH BEENDET."
echo " Skripte, Services und Cronjobs wurden exakt registriert."
echo "======================================================"
echo ""

chmod +x /home/pi/deploy/navika/scripts/*.sh /home/pi/deploy/navika/scripts/*.py 2>/dev/null || true

# INTERAKTIVE ABFRAGE FÜR DEN WLAN-CREATOR
read -p "Soll der wlan-creator JETZT ausgeführt werden? (j/n): " RUN_CREATOR
if [[ "$RUN_CREATOR" =~ ^[Jj]$ ]]; then
    echo -e "\n--- Starte wlan-creator.sh ---"
    /home/pi/deploy/navika/scripts/wlan-creator.sh
else
    echo -e "\nwlan-creator übersprungen."
fi

echo ""
echo "======================================================"
echo " Alles erledigt! SSH-Verbindung steht noch stabil."
echo " Bitte führe jetzt manuell 'sudo reboot' aus!"
echo "======================================================"
