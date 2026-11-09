#!/usr/bin/env python3
# status.mu - Statusseite fuer NomadNet-Nodes.
# Zugriff nur fuer Identities aus status_allowed (neben dieser Datei): "identity-hash,NAME".

import glob
import os
import re
import shutil
import socket
import subprocess

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ALLOWED_FILE = os.path.join(SCRIPT_DIR, "status_allowed")


def load_users(path):
    users = {}
    try:
        with open(path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.split("#", 1)[0].strip()
                if not line:
                    continue
                parts = line.split(",", 1)
                if len(parts) == 2:
                    identity = parts[0].strip()
                    name = parts[1].strip()
                    if identity:
                        users[identity] = name
    except FileNotFoundError:
        pass
    return users


def node_title():
    # Titel aus der index.mu (">`!NAME-NODE`!"), sonst Hostname
    try:
        with open(os.path.join(SCRIPT_DIR, "index.mu"), "r", encoding="utf-8") as f:
            m = re.search(r"^>`!(.+?)`!", f.read(), re.M)
            if m:
                return m.group(1).strip()
    except Exception:
        pass
    return socket.gethostname().split(".")[0].upper() + "-NODE"


def find_tool(name):
    home = os.path.expanduser("~")
    dirs = [
        os.path.join(home, ".local", "bin"),
        "/usr/local/bin",
        "/usr/bin",
    ]
    dirs += glob.glob(os.path.join(home, ".local", "share", "pipx", "venvs", "*", "bin"))
    dirs += glob.glob(os.path.join(home, ".local", "pipx", "venvs", "*", "bin"))
    path = os.pathsep.join(dirs + [os.environ.get("PATH", "")])
    return shutil.which(name, path=path)


USERS = load_users(ALLOWED_FILE)
remote_id = os.environ.get("remote_identity", "")
name = USERS.get(remote_id)

print(">`!" + node_title() + " — STATUS`!")
print("")

if not name:
    print("`Fd00`✗ Zugriff verweigert.`f")
    print("")
    print("Diese Statusseite ist nur für autorisierte Identitäten verfügbar.")
    print("")
else:
    print(f"`F0d0`✓ Hallo {name}!`f")
    print("")
    print("Deine Reticulum-Identität wurde erfolgreich erkannt.")
    print("Du bist für diese Seite autorisiert.")
    print("")
    print("`!Lokaler Reticulum-Status`!")
    print("")

    rnstatus = find_tool("rnstatus")
    if not rnstatus:
        print("`Fd00`rnstatus wurde nicht gefunden.`f")
    else:
        try:
            result = subprocess.run(
                [rnstatus], capture_output=True, text=True, timeout=10
            )
            output = result.stdout.strip()
            if output:
                print("`=")
                print(output)
                print("`=")
            else:
                print("rnstatus lieferte keine Ausgabe.")
        except subprocess.TimeoutExpired:
            print("`Fd00`rnstatus Timeout.`f")
        except Exception as e:
            print(f"`Fd00`Fehler beim Aufruf von rnstatus: {e}`f")

def rnpath_output(tool):
    # Pfadtabelle, nur 0-1 Hops, ohne LocalInterface; Micron-Sonderzeichen entschaerfen
    try:
        r = subprocess.run([tool, "-t"], capture_output=True, text=True, timeout=10)
        lines = [
            l for l in r.stdout.splitlines()
            if "LocalInterface" not in l and re.search(r"\bis [01] hops?\b", l)
        ]
        return "\n".join(lines).strip()
    except Exception:
        return ""


if name:
    rnpath = find_tool("rnpath")
    if rnpath:
        print("")
        print("`!RNS-Pfadtabelle (0-1 Hops)`!")
        print("")
        paths = rnpath_output(rnpath)
        if paths:
            for line in paths.splitlines():
                line = (line.replace("[", "(").replace("]", ")")
                            .replace("<", "").replace(">", ""))
                print(line)
        else:
            print("keine Pfade vorhanden")

print("")
print("`[Zurück`:/page/index.mu]")
