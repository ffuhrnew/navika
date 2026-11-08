# navika — Technische Dokumentation

Stand: 08.11.2026

## Zweck

Zentrale Codebasis fuer pipx-basierte, bare-metal Reticulum-Feldknoten
(Reticulum Network Stack auf Raspberry Pi OS). Bewusst ohne Docker-Abhaengigkeiten.

## Architektur-Ueberblick

Frischer Node (Setup-WLAN)
  -> bootstrap/pull_from_host.sh (rsync vom Deploy-Host)
~/deploy/navika/
  -> bootstrap/bootstrap_new_node.sh (System-Pakete, pipx-venvs)
  -> reboot
  -> finalize/setup_new_rns_node.sh (Identity, Config, Services)
  -> optional: scripts/wlan-creator.sh (AP + Client-Profile)
  -> reboot
  Produktiver Node

## Datei-fuer-Datei-Referenz

### bootstrap/bootstrap_new_node.sh
Laeuft einmalig auf frisch geflashter SD-Karte. Installiert:
- System-Update (apt full-upgrade)
- Basis-Pakete inkl. fake-hwclock (fuer zeitlose Boots ohne RTC)
- pipx-venvs: rns (+lxmf injiziert), nomadnet (+rns/lxmf injiziert),
  meshcore-cli, meshtastic (CLI-Tool),
  rnsh
- Bluetooth, NetworkManager, dialout/bluetooth-Gruppen
- Zeitzone Europe/Berlin
- IPv6 wird global deaktiviert (/etc/sysctl.d/99-disable-ipv6.conf,
  net.ipv6.conf.all.disable_ipv6 = 1) - bewusste Design-Entscheidung,
  vermeidet IPv6-Nebenwirkungen bei NetworkManager/RNS-Interfaces auf
  Feldknoten ohne IPv6-Konnektivitaet

### bootstrap/pull_from_host.sh
Laeuft LOKAL auf dem neuen Node (nicht auf dem Deploy-Host!). Holt per rsync den
Repo-Inhalt vom Deploy-Host (<DEPLOY_HOST_IP>), filtert .git/, .gitignore,
README.md, docs/ aktiv aus - auf dem Node landet
nur, was fuers Deployment gebraucht wird, keine Meta-Dateien.

### finalize/setup_new_rns_node.sh
Laeuft LOKAL auf dem Node nach dem Pull. Interaktiv - fragt Hostnamen
per read -p ab (kein Positionsparameter mehr, aeltere Doku-Versionen sind
hier veraltet). Ablauf:
1. Hostname abfragen
2. machine-id neu generieren
3. SSH-Host-Keys werden bewusst NICHT regeneriert (Block in setup_new_rns_node.sh ist auskommentiert)
4. SSH-Passwort-Auth optional aktivieren (Abfrage j/N, sed in sshd_config)
   Bekannter Fallstrick: cloud-init kann das ueber
   /etc/ssh/sshd_config.d/50-cloud-init.conf ueberschreiben
5. Identity-Backup (immer mv nach ~/identity_backups/, NIE rm -
   Verifikations-Prinzip: Dateien werden erst nach bestaetigtem Hash-Vergleich
   geloescht, nie aufgrund einer Vermutung)
6. .reticulum/config schreiben (Standard-LoRa-Parameter, siehe unten; eine bestehende
   Config wird vorher nach ~/identity_backups/ gesichert)
7. Alle 5 systemd-Services aus systemd-templates/ kopieren
8. udev-Regel kopieren, dann udevadm control --reload-rules und udevadm trigger
9. Alle Wartungs-Scripts nach /usr/local/bin/ kopieren und chmod +x
10. PATH-Erweiterung in ~/.bashrc: deploy/navika/scripts wird
    vorn an PATH gehaengt (idempotent)
11. Cronjobs aus den Templates einrichten
12. Hostname final setzen
13. Interaktive Abfrage: wlan-creator.sh jetzt ausfuehren? j/n

### Fleet-Standard .reticulum/config

RNode LoRa Relay: frequency 869525000, bandwidth 125000, txpower 22,
spreadingfactor 9, codingrate 5, mode full, announce_rate_target 3600,
announce_rate_grace 360.
TCP Server (nur bei TCP_SERVER=yes in /etc/navika.env): listen_ip 0.0.0.0, listen_port 4242.

### scripts/wlan-creator.sh (v2, RADIKALE FELDKONFIGURATION)

Vereinheitlichte Architektur, ersetzt fruehere ap-default/wlan-client-default
Unterscheidung. Jeder Node, der dieses Script durchlaeuft, wird AP-first:

1. Radikale Rasur: ALLE WLAN-Profile (Ethernet bleibt unberuehrt) werden auf
   autoconnect=no, priority=0 gesetzt
2. Vordefinierte Client-Profile aus TARGET_NETWORKS (z.B. stationaere
   WLAN-Router vor Ort, 2.4/5GHz-Baender) werden angelegt, aber
   autoconnect=no - nur manuell aktivierbar
3. Ein bereits vorkonfiguriertes Setup-WLAN wird bewusst NICHT ueberschrieben,
   gilt als Werkseinstellung
4. Eigener AP (hostname-AP) wird direkt als nmconnection-Datei geschrieben,
   autoconnect=true, priority=100 - der einzige aktive Eintrag danach

Fragt zwei separate Passwoerter ab: eins fuer Client-Netze, eins fuer AP.
Das AP-Passwort muss 8 bis 63 Zeichen lang sein (WPA2).

### scripts/wlan-selector.sh
Separates, rein manuelles Interaktiv-Tool, nicht Teil des automatisierten
Setup-Flows. Zeigt alle WLAN-Profile mit Status, laesst ein Zielprofil
fuer den naechsten Boot auswaehlen.

### scripts/rnode-watchdog.sh
Laeuft alle 5 Minuten via Cron als root. Prueft ob rnsd, nomadnet, rnsh,
rncp, rnx (soweit aktiviert) laufen und ob das RNode-Interface laut rnstatus Up ist.
Bei 3 aufeinanderfolgenden Fehlschlaegen: Notify per rns-notify.py und
kompletter Reboot. 180 Sekunden Cooldown zwischen Checks.

Konfiguration: Ziel-Hashes und Host-Parameter werden zentral ueber /etc/navika.env geladen.
Zustandsdateien (Fehlerzaehler, Cooldown) liegen unter /run.

### scripts/navika-listener.sh
Wrapper fuer die Listener-Services rnsh, rncp und rnx (Aufruf: navika-listener.sh rnsh|rncp|rnx).
Liest ALLOWED_IDENTITIES (Identity-Hashes, je 32 Hex-Zeichen) aus /etc/navika.env und startet den
Listener mit je einem -a pro Hash. Ist die Liste leer, startet nichts (Absicht). Ungueltige Hashes
brechen den Start ab.

### scripts/send-status.sh
Laeuft alle 3 Stunden via Cron als User pi. Sendet Hostname, RAM-Status
und rnstatus-Output an das konfigurierte LXMF-Ziel (STATUS_DEST_HASH).

### scripts/rns-announce-all.py
Laeuft stuendlich via Cron als User pi (Log: ~/rns-announce.log).
Bereinigt am 15.08.26. Fruehere Versionen enthielten fehlerhafte
os.system Aufrufe mit dem Flag -A in der irrigen Annahme, das bedeute
announce. Tatsaechlich bedeutet -A remote-command-as-args bei rnsh und
rncp. Die aktuelle Version announced nur noch die drei dateibasierten
Identitaeten. rnsh und rncp haben eigenes natives Re-Announce ueber das
Flag -b 900 im jeweiligen systemd-Service, rnx announced nur einmalig
beim Start.

### systemd-templates: Announce-Verhalten je Tool

rnsh.service: native Re-Announce-Loop alle 900 Sekunden, Flag -b 900.
rncp.service: native Re-Announce-Loop alle 900 Sekunden in eigenem Thread,
Flag -b 900.
rnx.service: nur beim Start, kein Intervall moeglich, kein -b Flag mit Wert.
rnsd.service: Transport-Instanz, eigenes Announce-Verhalten.
nomadnet.service: Daemon-Modus.

rnx unterstuetzt kein periodisches Announce - bei rnx bedeutet -b
no-announce, ein reiner Ein-Aus-Schalter, kein Intervall in Sekunden
wie bei rnsh und rncp. Fuer periodisches Re-Announce braeuchte rnx einen
externen Workaround, zum Beispiel einen systemd-Timer - nicht implementiert.

### udev-templates/99-rnode.rules
idVendor 303a, idProduct 1001, SYMLINK ttyRNODE. Fleet-weit identisch:
idVendor 303a steht fuer Espressif, also ESP32-basierte RNode-Boards. Die Regel trifft jedes
Geraet mit dieser ID (auch andere ESP32-Boards); bei mehreren gleichzeitig angeschlossenen
Geraeten ist der Symlink nicht eindeutig.

## Bekannte Fallstricke aus realen Deployments

1. cloud-init kann sshd_config ueberschreiben. Bei Raspberry Pi OS Trixie
   generiert cloud-init eine Datei mit PasswordAuthentication no, die die
   Hauptconfig ueberschreibt, da Include-Dateien danach geladen werden.
   Fix: die Include-Datei ebenfalls patchen, plus cloud-init.disabled setzen.

2. Das Flag -A bei rnsh und rncp bedeutet nicht announce, sondern
   remote-command-as-args. Fuehrte zu einem realen Bug in einer frueheren
   Version von rns-announce-all.py.

3. Persistente Pfad-Caches ueberleben Service-Neustarts.
   Ein einfacher restart reicht nicht, um veraltete RNS-Pfade zu vergessen.
   Die Datei destination_table im Storage-Ordner muss explizit geloescht
   werden, danach erzwingt eine frische Pfadanfrage den korrekten Neuaufbau.

4. Pfad-Bekanntheit ist nicht gleich Link-Faehigkeit. Ein Pfad kann gefunden
   werden, waehrend interaktive Verbindungen trotzdem an einer schwachen
   Funkstrecke scheitern.

5. Die rnprobe Syntax braucht immer den vollen Namen in dotted notation
   und den Hash, niemals nur den Hash allein.

## Verifikations-Prinzip, fleet-weit gueltig

Nie eine Identity- oder Config-Datei aufgrund einer Vermutung loeschen
oder verschieben. Vor jeder destruktiven Aktion per Hash-Vergleich
verifizieren. Backup statt Loeschen ist der Standard in allen Scripts.

## Offene TODOs, Stand 08.11.26

- rnx: kein periodisches Re-Announce, externer Timer-Workaround nicht umgesetzt
- AP-Passwort-Handling in wlan-creator.sh: interaktive Eingabe, kein Default
