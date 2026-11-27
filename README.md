# WhatsApp for Mac media downloader

After you restore WhatsApp or link your Mac again, the Mac app shows old photos, GIFs, voice messages and documents as blurred previews with a **download arrow**. Each one only loads when you click it, and there can be thousands. This tool clicks them for you, chat by chat.

> [!WARNING]
> **Use at your own risk.** This is a hobby tool that comes with **no warranty and no guarantee of any kind**. The author accepts **no responsibility for anything that goes wrong**, including lost data, a broken WhatsApp installation, or restrictions or bans on your WhatsApp account. Automating the WhatsApp app **may be against WhatsApp's Terms of Service**. This project is **not affiliated with, authorised by or endorsed by WhatsApp or Meta**. See [LICENSE](LICENSE).

**Status:** the pressing and scrolling logic was used on one Mac to fetch several thousand files. The `--types` choice, the `--count` option and the merged `run.sh` were added while preparing this public version and **have not yet been tried against a live WhatsApp**. Run with `--dry` first and please report problems.

## When you need this

The typical case: you restored WhatsApp on your iPhone from a backup, for example after reinstalling it or moving to a new phone. On the phone, all photos and files came back. The WhatsApp app on your Mac then synced the chat history again, but **only the messages**. Every photo, GIF, voice message and document in older chats shows as a blurred preview or placeholder with a download arrow, and each one has to be clicked by hand to fetch it.

WhatsApp has no "download all" button, and its auto-download setting only applies to newly arriving messages. So thousands of items across dozens of chats would each need a click. This tool does that clicking.

**It is not the right tool when:**

- the media is missing **on the phone too**,
- the **messages themselves** are missing on the Mac,
- the files are **no longer available from WhatsApp**, such as very old media that the sender's phone no longer has.

The tool can only press the download arrow. It cannot recover anything that WhatsApp itself cannot fetch.

> [!IMPORTANT]
> **Your real safeguard is a recent WhatsApp cloud backup on the phone**, not this tool: iCloud on iPhone, your Google account on Android (WhatsApp → Settings → Chats → Chat Backup). The Mac app is a **mirror of the phone, not a backup**. If chats are lost on the phone, the Mac re-syncs to match, and this tool can only re-download what WhatsApp can still fetch.

Once media is downloaded, it sits as ordinary files in WhatsApp's folder on the Mac, `~/Library/Group Containers/group.net.whatsapp.WhatsApp.shared/Message/Media/`. You can copy that folder somewhere else as an extra copy.

## How it works

1. It reads WhatsApp's own database on your Mac to learn which chats have files that were never downloaded, and at what minute each one was sent. The database is opened **read-only**; nothing in it is changed.
2. It opens each of those chats in the WhatsApp window, the same way you would, and scrolls up through the history.
3. For every message that matches a missing file, it "presses" the bubble through macOS's Accessibility feature (the system that screen readers use). WhatsApp then downloads the file as if you had clicked it.
4. It skips quickly over stretches where nothing is missing, and remembers what it has already handled so later runs are faster.

**Privacy:** everything happens on your Mac. The tool has no network code and sends nothing anywhere. The log and state files it writes (`logs/`, `blocked.txt`, `already-there.txt`, `done-chats.txt`) contain chat names and message descriptions, so keep them to yourself. They are excluded from git.

## What you need

- A Mac with a recent macOS.
- The **WhatsApp desktop app from the Mac App Store**, open and showing your chats.
- **Xcode Command Line Tools** (free, from Apple) to build the program. Install with:

  ```bash
  xcode-select --install
  ```

- **English** as the language of macOS and WhatsApp, with US-style dates ("March 5 at 2:15 PM"). The tool reads the English descriptions WhatsApp gives each message; in other languages it finds nothing to press.

## Permissions macOS will ask for

The tool runs inside a terminal app (Terminal, iTerm, …), so the permissions go to **that app**:

- **Accessibility** (required): System Settings → Privacy & Security → Accessibility → turn on your terminal app. Quit and reopen the terminal afterwards.
- **Access to data from other apps / Full Disk Access** (probably): reading WhatsApp's database may bring up a prompt such as "Terminal would like to access data from other apps". Allow it. If the tool reports that it cannot read the database or finds 0 chats, add your terminal app under System Settings → Privacy & Security → Full Disk Access.
- **Automation** (only with `run.sh`): the script may ask to be allowed to control WhatsApp so it can restart it when it gets stuck.

**More prompts may appear** the first time, depending on your macOS version. Nothing works until Accessibility is granted.

## Install

```bash
git clone https://github.com/aifunmobi/whatsapp-mac-media-downloader.git
```

```bash
cd whatsapp-mac-media-downloader
```

```bash
make
```

`make` runs the one build command, `swiftc -O wa_download.swift -o wa_download`. There is nothing else to install.

## Use

Open WhatsApp, wait until your chats show, and leave its window open on the desktop you are looking at.

First, see how much is missing (touches nothing):

```bash
./wa_download --count
```

Then try a dry run on one chat. It scrolls through the chat and prints what it would press, without pressing:

```bash
./wa_download --dry --chat "Jane Doe"
```

Then run it for real, the last 3 months, everything except videos:

```bash
./wa_download
```

### Options

| Option | What it does | Example |
|---|---|---|
| `--types LIST` | What to download: any of `images`, `gifs`, `files` (documents and voice messages), `voice` (voice messages only), `stickers`, `video`, separated by commas, or `all`. Default: everything except video. | `./wa_download --types images,gifs` |
| `--months N` | How far back to go. Default: 3. | `./wa_download --months 12` |
| `--chat "Name"` | Only chats whose name contains this text. | `./wa_download --chat "Jane Doe"` |
| `--albums` | Album pass. **Takes over the mouse and the screen**: albums (grid tiles of 2+ photos) only react to real clicks, so the pointer moves by itself and the Mac cannot be used meanwhile (see below). | `./wa_download --albums` |
| `--all` | Single items and albums in one pass. **Also takes over the mouse and the screen.** | `./wa_download --all --months 6` |
| `--dry` | Press nothing; print what would be pressed. | `./wa_download --dry` |
| `--count` | Print the number of missing files, in total and by type, and stop. | `./wa_download --count --months 12` |
| `--limit N` | With `--albums`/`--all`: stop a chat after N album clicks. For testing. | `./wa_download --albums --limit 2` |
| `--help` | Show the options. | `./wa_download --help` |

Videos are left out by default because they are large; add them with `--types all`. The older `--no-video` flag still works.

### Two modes

> [!IMPORTANT]
> **Multi-picture albums need the tool to take over your mouse and screen.** An album is the small grid tile WhatsApp makes from 2 or more photos sent together. Album tiles do not respond to background Accessibility presses, so the tool has to click them with the real mouse pointer. While that runs, WhatsApp must stay in front and visible, the pointer moves by itself, and **the Mac cannot be used for anything else**. Run it when you are away, for example overnight.

**Default: mouse-free.** This covers everything except albums: single photos, GIFs, stickers, voice messages, documents and single videos. Nothing touches your mouse or keyboard, so you can keep using the Mac. Conditions: the WhatsApp window must stay open **on the desktop (Space) you are currently on**, not minimised and not closed. It may be hidden behind other windows. If you switch to another desktop or a full-screen app the tool waits until the window is back. Albums are listed as "ALBUM not clicked".

**Album mode: `--albums` (or `--all`).** The tool brings WhatsApp to the front and clicks and scrolls with the real pointer. Do not touch the Mac while it runs; moving the mouse can send a click to the wrong place. `--albums` handles albums only; `--all` does single items and albums together. An album is clicked only when every kind in it (photos, videos) is in your `--types` list.

**Recommended order:** run the mouse-free pass first, while you work. Run the album pass later, when you are away from the Mac.

### Running unattended (overnight)

`run.sh` wraps the tool for long jobs. It takes the same options and:

- repeats the pass (up to 6 times) while each pass still brings in at least 20 more files,
- quits and reopens WhatsApp when most chats could not be opened (WhatsApp sometimes stops responding),
- keeps the Mac and its screen awake with `caffeinate`,
- writes a time-stamped log per pass plus `logs/progress.log`.

```bash
./run.sh --months 12
```

```bash
./run.sh --months 12 --types all --all
```

Stop it at any time with Ctrl-C. Chats already finished in the interrupted pass are remembered in `done-chats.txt` and skipped when you start again; a chat that was cut off mid-way is done again from its newest message, passing quickly over what is already fetched.

### How long it takes

It is slow. On the first real run, with roughly 7,900 missing items across about 50 chats, about 2,500 were fetched in the first 4 hours. Expect one or more nights for a large history. A second pass usually picks up what the first one missed.

## Use with an AI assistant

You can let an AI assistant run the tool for you: start it, read the logs, tell you how far it is, and stop it.

**Assistants that can run shell commands** (Claude Code, Codex and similar): open the repository folder with the assistant. [`AGENTS.md`](AGENTS.md) tells it which commands to use, what the log lines mean and what it must not do.

**Assistants that use MCP servers** (Claude Desktop and others): the repository includes a small MCP server, [`mcp/server.py`](mcp/server.py). It needs only the Python that comes with the Xcode Command Line Tools. Add it to your assistant's MCP configuration, with the real path to your copy:

```json
{
  "mcpServers": {
    "whatsapp-media-downloader": {
      "command": "/usr/bin/python3",
      "args": ["/path/to/whatsapp-mac-media-downloader/mcp/server.py"]
    }
  }
}
```

It offers four tools:

| Tool | What it does |
|---|---|
| `count_missing` | Counts the missing files, in total and by type. Touches nothing. |
| `start_download` | Starts `run.sh` in the background. Refuses album mode until you have agreed to give up mouse and screen. |
| `status` | Says whether a run is in progress and shows the end of the logs. |
| `stop_download` | Stops the run. |

The permissions go to the app that starts the server (your assistant's app) instead of the terminal: Accessibility, and access to WhatsApp's data. The logs the assistant reads contain chat names and message descriptions, so they are sent to whichever AI service you use. The MCP server is new: counting and status were tested, starting and stopping a real run through it were not.

## Caveats from real use

These come from the one long run this tool has had.

1. **It is slow** (see the numbers above). Long stretches of scrolling with no downloads are normal: it is passing parts that are already done.
2. **Mouse-free mode only works while the WhatsApp window is on the desktop (Space) currently showing.** Switch to another Space or a full-screen app and the tool cannot see WhatsApp; it pauses and carries on from the same place when the window is back. Do not close or minimise the window. Earlier versions misread a desktop switch as a press gone wrong: they re-scrolled the chat from the newest message and could wrongly put the last pressed item on the block list.
3. **WhatsApp sometimes stops responding to presses in the chat list**, and every chat is reported as "chat did not open" or "not found". The cause was never pinned down; it seemed to follow opening the viewer on items that were already downloaded. `run.sh` notices it (many skipped chats) and quits and reopens WhatsApp, which costs time.
4. **Flicker.** Pressing an item that is already downloaded opens it in the viewer, a Quick Look window or, for a sticker, an enlarged sticker popup; the tool closes it again. (Before the sticker popup was handled, it covered the chat, the tool took it for a lost chat and gave up on that chat.) Such items are remembered in `already-there.txt` so they are not pressed twice.
5. **The missing count never reaches zero.** A sent photo's HD copy stays "missing" in the database even when the standard copy is there.
6. **Some bubbles open another screen instead of downloading** (channel forwards, some GIFs and links). The tool backs out and puts them on a block list, `blocked.txt`. If that file contains ordinary photos or voice messages (left by an earlier version, see point 2), delete the file; the tool builds it up again.
7. **Chats not in the main chat list are skipped:** archived chats, and sometimes the chat with yourself or groups shown under a different name.
8. **Two chats with the same display name** cannot be told apart reliably.
9. **Voice messages are matched by time only**, because their Accessibility label does not state the sender.
10. **Matching depends on WhatsApp's exact wording.** Messages from a previous year carry the year in their label, and today's and yesterday's carry only a time; this is handled. Any change in WhatsApp's wording, or a system language other than English, breaks matching.
11. **Link previews are not downloaded.** Stickers are, since the second day of use.
12. **The approach is fragile.** An early version closed WhatsApp's main window by mistake when the app was too busy to answer. That is fixed, but check on a long run now and then.
13. **Measure progress by the missing count, not by presses.** Compare `./wa_download --count` before and after.
14. **Do not use WhatsApp on the Mac while it runs.** In album mode, do not use the Mac at all.
15. **An incoming message, or you clicking another chat, can pull WhatsApp away from the chat being worked on.** The tool treats the first such jump as an interruption: it waits 30 seconds, goes back and starts that chat again from the newest message. Only when the same item loses the chat twice is that item put on the block list. An earlier version went straight back, was pulled away again 26 times in a row and gave up on the chat.
16. **Chats with the most open items are done first, and long scrolls are put off.** When the next item to fetch in a chat is more than 1,500 messages further back, the tool leaves that chat and finishes it after all the others. Albums that cannot be clicked in mouse-free mode stay on the list, so chats with many albums are still read through slowly. This rule is new and has had little use.
17. **Do not start a second copy, not even with `--dry`, while a run is in progress.** Both would steer the same WhatsApp window and knock each other out of place. `--count` is safe at any time.
18. **A locked screen stops everything.** When the display sleeps, macOS usually locks the screen, and the tool can no longer see WhatsApp. `run.sh` keeps the display on; if you start `wa_download` yourself for a long run, use `caffeinate -di ./wa_download …`. `caffeinate -i` alone lets the display sleep and the screen lock.
19. **Keep the Mac awake and the phone online.** `run.sh` keeps the Mac awake with `caffeinate`; the phone should stay connected so WhatsApp can fetch the files.
20. **A chat that gives almost nothing in a mouse-free run is not reopened mouse-free.** If a whole mouse-free pass through a chat fetches fewer than 3 items (usually because what is left is albums), the chat is listed in `no-progress-chats.txt` and later mouse-free runs skip it. Album (`--all`) runs still visit it. Delete the file to clear the list.
21. **Hidden HD copies are not counted.** When someone sends a photo in HD, WhatsApp stores a normal copy and a full-quality copy. The full-quality copy is never shown in the chat and is not downloaded, but the database lists it as missing. A photo is therefore skipped when the same sender has an already-downloaded photo in the 3 minutes before it. This rule is approximate and can skip a real photo sent right after another.
22. **Chats can be ignored.** Put chat numbers (`Z_PK` from `ZWACHATSESSION`), one per line, in `ignore-chats.txt`, for example archived chats that are not in the chat list.
23. **Album clicks are checked first.** Before a real click, the tool asks macOS what is under the pointer and clicks only if it is the album, so a moving chat does not make it click (and play) a voice message instead. Voice messages have still been heard playing during album runs without any logged press; the cause is not known yet.
24. **Your own chat** ("You" in the database) is found by your number in the chat list.

## Limitations

- **Archived chats are not reached.** Only chats in the main chat list are opened. Unarchive a chat first if you want it done.
- **HD duplicates stay "missing".** When a photo was sent in both standard and HD quality, the database keeps counting one copy as missing even after the picture shows. The count never reaches zero.
- **Files gone from WhatsApp's servers cannot be fetched.** Old media that no longer exists on the server, or on the phone it was sent from, will not download however often it is pressed.
- **English only**, with US-style dates (see above).
- **It breaks when WhatsApp changes its interface.** The tool depends on the internal names of WhatsApp's windows and lists and on its database layout, both of which can change with any update.
- Now and then a press opens something other than a download (a link, a contact card). The tool closes it, notes the message in `blocked.txt` and does not press it again.
- A document that is already on the Mac opens in a preview window when pressed; the tool closes it and notes it in `already-there.txt`.

## Troubleshooting

| What you see | What to do |
|---|---|
| "This terminal app is not allowed to control other apps yet" | Grant Accessibility (see above), then quit and reopen the terminal. |
| "Cannot read WhatsApp's database" or "0 chats, 0 missing files" although media is missing | Give the terminal app Full Disk Access. Check that you use the App Store version of WhatsApp. |
| "WhatsApp is not running" | Open WhatsApp and wait for the chats to load. |
| Many lines starting with `SKIP … not found in chat list` | The chat is archived, or WhatsApp is stuck. Quit and reopen WhatsApp, or use `run.sh`, which does that for you. |
| "WhatsApp is not on this desktop: waiting" | Switch back to the desktop that holds the WhatsApp window, or run with `--all`. |
| Lines with `?date:` or "unknown kind, not pressed" for most messages | macOS or WhatsApp is not in English, or WhatsApp changed its wording. |
| It runs but nothing gets pressed | Try `--dry --chat "Name"` on one chat and read the output; increase `--months`; check `--types`. |
| A message keeps being skipped that should download | Delete `blocked.txt` and `already-there.txt` to make the tool forget what it learned. |
| `xcrun: error` or `swiftc: command not found` when building | Run `xcode-select --install`. |

## Mini-rant

Shame on WhatsApp for making switching between phones and restoring unnecessarily difficult and buggy!

## License

[MIT](LICENSE). Provided "as is", without warranty of any kind.
