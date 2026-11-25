# Instructions for AI assistants

This repository holds `wa_download`, a macOS tool that presses the download arrow on media WhatsApp for Mac has not downloaded yet. Read `README.md` for the full picture. This file is the short version for an assistant that runs it for someone.

## Rules

1. **Never start album mode (`--albums` or `--all`) without asking.** It clicks with the real mouse and keeps WhatsApp in front, so the person cannot use the Mac. Get a clear yes for each run.
2. **One run at a time.** Check with `pgrep -x wa_download` first. Do not start a second copy, not even with `--dry`: both would steer the same WhatsApp window. `--count` is always safe.
3. **Do not edit WhatsApp's database.** The tool opens it read-only; keep it that way.
4. **Logs and state files are private.** `logs/`, `blocked.txt`, `already-there.txt` and `done-chats.txt` contain chat names and message descriptions. Never commit or upload them.
5. **Report honestly.** Measure progress by the missing count, not by presses. The count never reaches zero (see below).

## Commands

Build once (needs Xcode Command Line Tools):

```bash
make
```

How much is missing, in total and by type (touches nothing):

```bash
./wa_download --count --months 12
```

Start a long run in the background, mouse-free, everything except video. It keeps the Mac awake, repeats passes while they help, and restarts WhatsApp if it gets stuck:

```bash
mkdir -p logs && nohup ./run.sh --months 12 > logs/runner.out 2>&1 &
```

Stop it:

```bash
pkill -f run.sh; pkill -x wa_download
```

Other options: `--types images,gifs,files,voice,stickers,video` (or `all`), `--chat "Name"`, `--dry` (prints what it would press; still opens and scrolls chats). `./wa_download --help` lists everything.

## Where to look

- `logs/progress.log`: one line per pass with the missing count.
- `logs/run-<date>-<time>.log`: the newest one is the pass in progress.
- `done-chats.txt`: chats finished in the current pass; they are skipped after a stop and restart. Removed when a pass completes.
- `blocked.txt`: items that opened something else twice and are never pressed again. If it holds ordinary photos or voice messages, something went wrong; tell the person before deleting entries.
- `already-there.txt`: items found to be downloaded already.

## Reading a run log

| Line | Meaning |
|---|---|
| `51 chats, 2739 missing files` | What this pass set out to do. |
| `resuming: 3 chats already finished in this pass` | Continuing after a stop. |
| `== Name: 415 missing` | Started this chat. |
| `   pressed 62; reached 2025-11-25 08:47` | Finished this chat; how far back it got. |
| `already there: …` | The item was on the Mac already (often the HD copy of a sent photo). Normal. |
| `ALBUM not clicked (needs a real mouse click)` | Mouse-free mode met an album. Needs an album run. |
| `WhatsApp is not on this desktop: waiting` / `WhatsApp is back` | The window went to another desktop; the tool paused. Normal. |
| `LOST the chat after pressing: …` then `treating it as an interruption` | WhatsApp jumped to another chat (incoming message, a click). The tool waits 30 s and goes back. A few are normal; dozens in a row are a problem. |
| `next item (…) is N messages further back: putting the rest of this chat off` | Long scroll postponed until the other chats are done. |
| `SKIP Name: not found in chat list` | Archived chat, or shown under another name. |
| `SKIP Name: chat did not open` | WhatsApp ignored the press. Many of these mean it is stuck; `run.sh` restarts it. |
| `giving up on this chat` | Too many losses in one chat. Tell the person. |
| `unknown kind, not pressed: …` | A bubble the tool does not recognise. Harmless for text replies; report it if it names a photo, file or voice message. |
| `DONE pressed N, albums skipped M` | The pass ended. |

## What to tell the person

- The window must stay open on the desktop they are looking at; hidden behind other windows is fine.
- They should not click around in WhatsApp on the Mac during a run.
- Photos in albums only come down in an album run, which needs their mouse and screen.
- Some items never leave the missing list: HD copies of sent photos, and files no longer on WhatsApp's servers.

## MCP

`mcp/server.py` offers the same operations as tools (`count_missing`, `start_download`, `status`, `stop_download`) for assistants without a shell. Setup is in the README.
