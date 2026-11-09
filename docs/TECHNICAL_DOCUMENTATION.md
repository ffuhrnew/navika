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
7. Alle 5 systemd-Services aus systemd-templates/ kopieren; rnsh, rncp und rnx werden nur
   aktiviert, wenn ihre eigene Allow-Liste (ALLOWED_IDENTITIES_<DIENST>) in /etc/navika.env gesetzt ist
8. udev-Regel kopieren, dann udevadm control --reload-rules und udevadm trigger
9. Alle Wartungs-Scripts nach /usr/local/bin/ kopieren und chmod +x
10. PATH-Erweiterung in ~/.bashrc: deploy/navika/scripts wird
    vorn an PATH gehaengt (idempotent)
11. Cronjobs aus den Templates einrichten
12. Hostname final setzen (zuerst /etc/hosts, dann hostnamectl, sonst warnt sudo)
13. NomadNet-Anzeigename setzen (navika-set-nomadnet-name.sh)
14. Optional: NomadNet-Node mit Start- und Statusseite (navika-nomadnet-node.sh, fragt nach)
15. Optional (SAMAYA_ENABLE=yes): samaya per pipx aus dem Tag installieren, samaya-sync.service
    und .timer einrichten
16. Interaktive Abfrage: wlan-creator.sh jetzt ausfuehren? j/n

### Fleet-Standard .reticulum/config

RNode LoRa Relay: frequency 869525000, bandwidth 125000, txpower 22,
spreadingfactor 8, codingrate 5, mode full, announce_rate_target 3600,
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
Liest die Allow-Liste des Dienstes (ALLOWED_IDENTITIES_RNSH, _RNCP bzw. _RNX; Identity-Hashes, je 32
Hex-Zeichen) aus /etc/navika.env und startet den Listener mit je einem -a pro Hash. Jedes Programm hat
eine eigene Identity, die Listen sind bewusst getrennt, eine gemeinsame Liste gibt es nicht. Ist die
Liste leer, startet der Dienst nicht (Absicht). Ungueltige Hashes brechen den Start ab.
rncp speichert empfangene Dateien in RNCP_SAVE_PATH (Standard ~/rncp-inbox, wird angelegt).

### scripts/navika-set-nomadnet-name.sh
Setzt den NomadNet-Anzeigenamen (display_name in ~/.nomadnetwork/storage/peersettings, msgpack).
Name: NOMADNET_DISPLAY_NAME aus /etc/navika.env, leer = <Hostname>_OP. NomadNet haelt die
Einstellungen im Speicher und schreibt die Datei bei jedem Speichern neu; deshalb wird der Dienst
vor der Aenderung gestoppt und danach gestartet. Fehlt peersettings noch (frischer Node), startet
das Skript NomadNet einmal, wartet bis zu 60 Sekunden auf die Datei und aendert sie dann.
Vorher wird peersettings.bak angelegt.

### scripts/navika-nomadnet-node.sh
Richtet optional eine NomadNet-Node ein (Setup-Schritt 10, einzeln auch auf einem
laufenden Node nutzbar). Zuerst werden alle Eingaben abgefragt und geprueft, erst
danach wird NomadNet gestoppt und etwas geaendert; bei einem Fehler bleibt die Config
unberuehrt. Ablauf: Abfrage ob eine Node laufen soll, Node-Name (Standard
<HOSTNAME>-NODE in Grossbuchstaben), Abfrage ob eine Start- und Statusseite gebaut
werden soll. Aenderungen: enable_node und node_name im Abschnitt [node] von
~/.nomadnetwork/config (Sicherung als config.bak.<Zeitstempel>), Seiten aus
nomadnet-templates/ nach ~/.nomadnetwork/storage/pages (bestehende Dateien werden als
.bak.<Zeitstempel> gesichert, nie ueberschrieben). Optionen in /etc/navika.env:
NOMADNET_NODE, NOMADNET_NODE_NAME, NOMADNET_STATUS_PAGE,
NOMADNET_STATUS_ALLOWED_FILE, NOMADNET_OPERATOR_LXMF, NOMADNET_DISPLAY_NAME; fehlende
Werte werden abgefragt.

### nomadnet-templates/
index.mu (Startseite, Platzhalter @NODE_NAME@, @OPERATOR_NAME@, @OPERATOR_LXMF@; ohne
LXMF-Adresse entfaellt die Zeile) und status.mu (dynamische Seite, Python, muss
ausfuehrbar sein). status.mu zeigt rnstatus und die Pfadtabelle (0 bis 1 Hops) nur
Identities aus status_allowed neben der Seite (Format hash,name, Kommentare mit #).
Alle anderen sehen "Zugriff verweigert". Die Allow-Liste liegt nie im Repo: Das Setup
fragt Hash und Name ab oder uebernimmt eine Datei (NOMADNET_STATUS_ALLOWED_FILE).
Eine leere Liste ergibt eine Statusseite, die niemand sehen kann.

### scripts/navika-samaya-sync.sh
Wrapper fuer samaya-sync.service (laeuft als root, nur root darf die Systemuhr stellen). Liest
SAMAYA_ENABLE, SAMAYA_TIME_SERVER_KEY (128 Hex-Zeichen) und RNS_USER aus /etc/navika.env und ruft
samaya sync --rns-config /home/<RNS_USER>/.reticulum <Schluessel> auf. Ist SAMAYA_ENABLE nicht yes,
endet das Skript mit 0; ein fehlender oder ungueltiger Schluessel ergibt Exit 1. Der Schluessel
steht bewusst nicht in der Unit-Datei und nie im Repo. Exit-Code 2 von samaya (Uhr geht vor, nicht
zurueckgestellt) ist kein Fehler.

### systemd-templates/samaya/
samaya-sync.service (oneshot, After/Wants rnsd.service) und samaya-sync.timer (OnBootSec=30s,
OnUnitInactiveSec=30min, RandomizedDelaySec=20s). Die Units liegen in einem Unterordner, damit der
Kopierbefehl fuer systemd-templates/*.service sie nicht auf jeden Node legt; das Setup installiert
sie nur bei SAMAYA_ENABLE=yes. samaya wird per pipx aus dem oeffentlichen Repo installiert,
festgelegt auf SAMAYA_REF (Standard: Tag v0.1.0).

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

### Startreihenfolge der Services
rnsd.service wartet per ExecStartPost bis zu 60 Sekunden, bis rnsd selbst den Socket @rns/default/rpc
haelt; erst dann gilt die Unit als gestartet. rnsh, rncp und rnx haben After= und Requires=rnsd.service.
Grund: Ein Client, der vor rnsd bereitsteht, wird selbst zur Shared Instance und haelt den RNode mit
der alten Konfiguration (Fehlerbild: rnsd meldet "connected to another shared local instance").

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
