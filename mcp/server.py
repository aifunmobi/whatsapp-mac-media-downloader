#!/usr/bin/env python3
"""MCP server for wa_download: lets an AI assistant count, start, watch and stop the downloader.

Standard library only. Speaks MCP over stdio (one JSON-RPC message per line).
Register it with your assistant as:  python3 /path/to/repo/mcp/server.py
"""
import json, os, signal, subprocess, sys, glob

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOGS = os.path.join(ROOT, "logs")
PIDFILE = os.path.join(LOGS, "run.pid")
TYPES = "Comma list of images, gifs, files, voice, stickers, video, or 'all'. Default: everything except video."

TOOLS = [
    {"name": "count_missing",
     "description": "Count the files WhatsApp for Mac has not downloaded yet, in total and by type. Reads WhatsApp's local database only; does not touch the app.",
     "inputSchema": {"type": "object", "properties": {
         "months": {"type": "integer", "minimum": 1, "description": "How many months back to look. Default 3."},
         "types": {"type": "string", "description": TYPES},
         "chat": {"type": "string", "description": "Only chats whose name contains this text."}}}},
    {"name": "start_download",
     "description": "Start the downloader in the background (unattended runner with time-stamped logs). Only one run at a time. "
                    "Without albums it does not use the mouse or keyboard, but the WhatsApp window must stay on the current desktop. "
                    "With albums=true it clicks with the REAL mouse and keeps WhatsApp in front, so the person cannot use the Mac meanwhile: "
                    "ask them first, and pass mouse_takeover_confirmed=true only after they agreed.",
     "inputSchema": {"type": "object", "properties": {
         "months": {"type": "integer", "minimum": 1, "description": "How many months back to go. Default 3."},
         "types": {"type": "string", "description": TYPES},
         "chat": {"type": "string", "description": "Only chats whose name contains this text."},
         "albums": {"type": "boolean", "description": "Also click multi-picture albums (needs the real mouse)."},
         "mouse_takeover_confirmed": {"type": "boolean", "description": "The person agreed to give up mouse and screen for this run."}}}},
    {"name": "status",
     "description": "Say whether a run is in progress and show the end of the progress log and of the newest run log.",
     "inputSchema": {"type": "object", "properties": {
         "lines": {"type": "integer", "minimum": 1, "maximum": 300, "description": "Log lines to return. Default 30."}}}},
    {"name": "stop_download",
     "description": "Stop the run in progress. Chats already finished in the current pass are remembered and skipped on the next start.",
     "inputSchema": {"type": "object", "properties": {}}},
]


def running_pid():
    try:
        pid = int(open(PIDFILE).read().strip())
        os.killpg(pid, 0)
        return pid
    except (OSError, ValueError):
        return None


def options(a, allow_albums=False):
    o = []
    if a.get("months"): o += ["--months", str(int(a["months"]))]
    if a.get("types"): o += ["--types", str(a["types"])]
    if a.get("chat"): o += ["--chat", str(a["chat"])]
    if allow_albums and a.get("albums"): o += ["--all"]
    return o


def tail(path, n):
    try:
        with open(path, errors="replace") as f:
            return "".join(f.readlines()[-n:])
    except OSError:
        return ""


def build():
    if not os.access(os.path.join(ROOT, "wa_download"), os.X_OK):
        r = subprocess.run(["make"], cwd=ROOT, capture_output=True, text=True)
        if r.returncode: raise RuntimeError("Could not build wa_download:\n" + r.stdout + r.stderr)


def call(name, a):
    if name == "count_missing":
        build()
        r = subprocess.run(["./wa_download", "--count"] + options(a), cwd=ROOT, capture_output=True, text=True, timeout=120)
        return (r.stdout + r.stderr).strip()
    if name == "start_download":
        if running_pid(): return "A run is already in progress. Use status to watch it or stop_download to end it."
        if a.get("albums") and not a.get("mouse_takeover_confirmed"):
            return ("Not started. Albums need real mouse clicks with WhatsApp in front, so the Mac cannot be used during the run. "
                    "Ask the person, then call again with mouse_takeover_confirmed=true.")
        build()
        os.makedirs(LOGS, exist_ok=True)
        out = open(os.path.join(LOGS, "runner.out"), "a")
        p = subprocess.Popen(["./run.sh"] + options(a, True), cwd=ROOT, stdin=subprocess.DEVNULL, stdout=out, stderr=out, start_new_session=True)
        open(PIDFILE, "w").write(str(p.pid))
        return "Started (process group %d). Logs are in %s. Use status to follow it." % (p.pid, LOGS)
    if name == "status":
        n = int(a.get("lines") or 30)
        pid = running_pid()
        logs = sorted(glob.glob(os.path.join(LOGS, "run-*.log")))
        text = "Run in progress (process group %d)." % pid if pid else "No run in progress."
        text += "\n\n== progress.log ==\n" + (tail(os.path.join(LOGS, "progress.log"), 10) or "(empty)\n")
        if logs: text += "\n== %s ==\n" % os.path.basename(logs[-1]) + tail(logs[-1], n)
        return text
    if name == "stop_download":
        pid = running_pid()
        if not pid: return "No run in progress."
        os.killpg(pid, signal.SIGTERM)
        try: os.remove(PIDFILE)
        except OSError: pass
        return "Stopped."
    raise ValueError("Unknown tool " + name)


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line: continue
        try: msg = json.loads(line)
        except ValueError: continue
        mid, method = msg.get("id"), msg.get("method")
        if mid is None: continue                      # notification: nothing to answer
        if method == "initialize":
            result = {"protocolVersion": msg.get("params", {}).get("protocolVersion", "2024-11-05"),
                      "capabilities": {"tools": {}}, "serverInfo": {"name": "whatsapp-mac-media-downloader", "version": "1.0.0"}}
        elif method == "ping":
            result = {}
        elif method == "tools/list":
            result = {"tools": TOOLS}
        elif method == "tools/call":
            p = msg.get("params", {})
            try: result = {"content": [{"type": "text", "text": call(p.get("name"), p.get("arguments") or {})}]}
            except Exception as e: result = {"content": [{"type": "text", "text": "Error: %s" % e}], "isError": True}
        else:
            sys.stdout.write(json.dumps({"jsonrpc": "2.0", "id": mid, "error": {"code": -32601, "message": "Method not found"}}) + "\n"); sys.stdout.flush(); continue
        sys.stdout.write(json.dumps({"jsonrpc": "2.0", "id": mid, "result": result}) + "\n"); sys.stdout.flush()


if __name__ == "__main__":
    main()
