#!/home/pi/.local/share/pipx/venvs/nomadnet/bin/python3
import RNS
import time
import os
reticulum = RNS.Reticulum()
IDENTITIES = [
    ("NomadNet LXMF-Delivery", "/home/pi/.nomadnetwork/storage/identity", "lxmf", "delivery"),
    ("NomadNet Node", "/home/pi/.nomadnetwork/storage/identity", "nomadnetwork", "node"),
    ("RNS-Notify", "/home/pi/.reticulum/rns_notify/identity", "lxmf", "delivery"),
]
def log(msg):
    print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] {msg}", flush=True)
for name, path, app_name, aspect in IDENTITIES:
    if os.path.isfile(path):
        identity = RNS.Identity.from_file(path)
        dest = RNS.Destination(identity, RNS.Destination.IN, RNS.Destination.SINGLE, app_name, aspect)
        dest.announce()
        log(f"{name} announced: {RNS.hexrep(dest.hash, delimit=False)}")
    else:
        log(f"{name}: Identity-Datei nicht gefunden unter {path}")
time.sleep(3)
