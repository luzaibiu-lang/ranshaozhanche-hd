"""Exercise battle chat through two real Windows clients on private desktops."""
import argparse
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import secrets
from urllib.parse import urlparse

import requests
from private_desktop import run

root = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument("--endpoint", required=True)
parser.add_argument("--client", type=Path)
args = parser.parse_args()
if urlparse(args.endpoint).hostname != "127.0.0.1":
    parser.error("QA accounts must use a loopback test server")
suffix = secrets.token_hex(3)
out = root / ".tools/qa" / ("battle-chat-" + suffix)
out.mkdir()
names = ["qa_chat" + suffix + role for role in "ab"]
session = requests.Session()
session.trust_env = False


def post(path, payload, token=""):
    response = session.post(args.endpoint + path, json=payload,
                            headers={"Authorization": "Bearer " + token}, timeout=8)
    response.raise_for_status()
    return response.json()


tokens = [post("/api/register", {"name": name, "password": "qa-only-895432"})["token"]
          for name in names]
room = post("/api/command", {"action": "create", "name": "聊天验收", "map": 4}, tokens[0])["room"]["id"]
post("/api/command", {"action": "join", "room": room}, tokens[1])
post("/api/command", {"action": "ready", "ready": True}, tokens[1])
post("/api/command", {"action": "chat", "text": "开局前"}, tokens[0])
post("/api/command", {"action": "start"}, tokens[0])


def test(index):
    role = "ab"[index]
    exe = args.client.resolve() / "Game.exe" if args.client else next((root / ".tools/godot").glob("*win64.exe"))
    cmd = [exe, "--audio-driver", "Dummy", "--max-fps", "45"]
    if not args.client:
        cmd += ["--path", root / "源码/client"]
    cmd += ["--script", root / "源码/tools/battle_chat_acceptance.gd", "--",
            "--qa-endpoint=" + args.endpoint, "--name=" + names[index], "--role=" + role,
            "--output=" + str(out)]
    log = out / (role + ".log")
    result = run(cmd, log, 70)
    report = log.read_text("utf8", errors="replace")
    assert result["exit_code"] == 0 and "ERROR:" not in report and "BATTLE_CHAT_ACCEPTANCE " + role in report, (out, report[-2500:])


with ThreadPoolExecutor(max_workers=2) as pool:
    list(pool.map(test, (0, 1)))
print(out)
