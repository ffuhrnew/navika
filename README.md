# navika

*Sanskrit: der Seemann / Steuermann — bringt neue Knoten sicher ins Reticulum-Netzwerk.*

Zentrale Codebasis für pipx-basierte, bare-metal Reticulum-Feldknoten
(Raspberry Pi OS Lite 64-bit) inklusive RNode-Watchdog, LXMF-Status- und
Alarm-Benachrichtigungen und Offline-WLAN-AP-Setup.

## Verzeichnisstruktur

- `bootstrap/` – Erstbetankung und Basis-Installation (pipx, rns, nomadnet, lxmf)
- `config-templates/` – Konfigurationsvorlage (`navika.env.example` -> `/etc/navika.env`)
- `finalize/` – Systemkonfiguration (machine-id, `.reticulum/config`, systemd-Units, udev, Cronjobs)
- `scripts/` – Wartungs- und Hilfsskripte (`rnode-watchdog.sh`, `rns-notify.py`, `send-status.sh`, `rns-announce-all.py`, `wlan-creator.sh`, `wlan-selector.sh`)
- `systemd-templates/` – Service-Units für `rnsd`, `nomadnet`, `rnsh`, `rncp`, `rnx`
- `udev-templates/` – Udev-Regel für RNode-Hardware (`/dev/ttyRNODE`)
- `docs/` – Technische Dokumentation

## Workflow für einen neuen Node

1. SD-Karte flashen: Raspberry Pi OS Lite 64-bit, offizieller Imager,
   Hostname/SSH-Key/User `pi` vorkonfigurieren.
2. Deployment-Skripte per `bootstrap/pull_from_host.sh` (oder `git clone`) auf den Node holen.
3. `config-templates/navika.env.example` nach `/etc/navika.env` kopieren und eigene Ziel-Hashes, `ALLOWED_IDENTITIES` (Admin-Identities für rnsh/rncp/rnx) sowie WLAN-SSIDs eintragen.
4. `bootstrap/bootstrap_new_node.sh` ausführen und neu starten (`sudo reboot`).
5. `finalize/setup_new_rns_node.sh` ausführen, Hostname vergeben, optional `wlan-creator.sh` starten und abschließend neu starten (`sudo reboot`).
6. Vor Produktivbetrieb: neue Identity-Hashes verifizieren.

## WLAN-Modi

| Modus | Wann | Beschreibung |
|---|---|---|
| Standalone AP (`wlan-creator.sh`) | Kein lokales WLAN am Standort | Node spannt eigenes WPA2-AP-Netz (`<HOSTNAME>-AP`) mit DHCP auf |
| Client-WLAN (`wlan-selector.sh`) | Stationäre WLAN-Infrastruktur vor Ort | Auswahl eines hinterlegten Client-WLANs mit Priorität 100 |

## Sicherheit

- **Fernzugriff:** `rnsh`, `rncp` und `rnx` starten nur, wenn `ALLOWED_IDENTITIES` in `/etc/navika.env` gesetzt ist, und erlauben nur diese Identitäten. Ohne Eintrag bleiben sie aus. Eine `rnsh`-Freigabe ist ein Shell-Zugang als Benutzer `pi`, der in der Standardkonfiguration von Raspberry Pi OS per `sudo` root werden kann.
- **`/etc/navika.env`** wird von Root-Cronjobs per `source` geladen und muss `root:root` gehören und darf für andere nicht schreibbar sein (das Setup setzt das).
- **TCP-Server** (Port 4242, alle Interfaces) ist standardmäßig aus; aktivieren mit `TCP_SERVER="yes"`.
- **SSH-Passwort-Login** wird nur auf ausdrückliche Rückfrage aktiviert; bevorzugt SSH-Schlüssel.
- **WLAN-AP:** Das Passwort (8 bis 63 Zeichen) wird interaktiv abgefragt und nie im Repo gespeichert.
- **Cronjobs:** `crontab <Datei>` im Setup ersetzt die bestehenden Crontabs von `root` und `pi`.
- **Funk:** Die Standardparameter (869,525 MHz, 125 kHz, SF9, 22 dBm) sind für EU868 ausgelegt; für die Einhaltung lokaler Vorschriften ist der Betreiber verantwortlich.

## Lizenz

Dieses Projekt steht unter denselben Bedingungen wie Reticulum: MIT-Lizenz mit zwei Zusatzbedingungen (kein Einsatz in Systemen, die gezielt Menschen schaden können; keine Verwendung für KI-/ML-Trainingsdatensätze). Siehe [LICENSE](LICENSE). Reticulum selbst steht unter der Reticulum License.
