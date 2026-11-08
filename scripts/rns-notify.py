#!/home/pi/.local/share/pipx/venvs/nomadnet/bin/python3
import RNS
import LXMF
import time
import os
import sys
import socket

if len(sys.argv) < 3:
    print("Usage: rns-notify.py <destination_hash_hex> <message>")
    sys.exit(1)

DEST_HASH_HEX = sys.argv[1]
MESSAGE = sys.argv[2]
DEST_HASH = bytes.fromhex(DEST_HASH_HEX)
STORAGE = "/home/pi/.reticulum/rns_notify"
hostname = socket.gethostname()

os.makedirs(STORAGE, exist_ok=True)
reticulum = RNS.Reticulum()

identity_path = STORAGE + "/identity"
if os.path.isfile(identity_path):
    identity = RNS.Identity.from_file(identity_path)
else:
    identity = RNS.Identity()
    identity.to_file(identity_path)

router = LXMF.LXMRouter(identity=identity, storagepath=STORAGE)
source = router.register_delivery_identity(identity, display_name=f"{hostname} Notify")

# ANNOUNCE
source.announce()
time.sleep(1)

STATE_NAMES = {0x00:"GENERATING", 0x01:"OUTBOUND", 0x02:"SENDING", 0x04:"SENT", 0x08:"DELIVERED", 0x10:"REJECTED", 0x20:"CANCELLED", 0xFF:"FAILED"}

def log(msg):
    print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] {msg}", flush=True)

log(f"Suche Pfad zu {DEST_HASH_HEX}...")

if not RNS.Transport.has_path(DEST_HASH):
    RNS.Transport.request_path(DEST_HASH)
    timeout = time.time() + 60
    while not RNS.Transport.has_path(DEST_HASH) and time.time() < timeout:
        time.sleep(1)

if not RNS.Transport.has_path(DEST_HASH):
    log("Kein Pfad gefunden, breche ab")
    sys.exit(1)

dest_identity = RNS.Identity.recall(DEST_HASH)
if dest_identity is None:
    timeout = time.time() + 20
    while dest_identity is None and time.time() < timeout:
        time.sleep(1)
        dest_identity = RNS.Identity.recall(DEST_HASH)

if dest_identity is None:
    log("Identity nicht bekannt, breche ab")
    sys.exit(1)

dest = RNS.Destination(dest_identity, RNS.Destination.OUT, RNS.Destination.SINGLE, "lxmf", "delivery")

lxm = LXMF.LXMessage(dest, source, MESSAGE, title=hostname, desired_method=LXMF.LXMessage.DIRECT)
router.handle_outbound(lxm)

timeout = time.time() + 90
while lxm.state not in (LXMF.LXMessage.DELIVERED, LXMF.LXMessage.FAILED) and time.time() < timeout:
    time.sleep(1)

state_name = STATE_NAMES.get(lxm.state, f"UNKNOWN({lxm.state})")
log(f"Status: {state_name}")
sys.exit(0 if lxm.state == LXMF.LXMessage.DELIVERED else 1)
