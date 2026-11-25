# WhatsApp for Mac media downloader

After you restore WhatsApp or link your Mac again, the Mac app shows old photos, GIFs, voice messages and documents as blurred previews with a **download arrow**. Each one only loads when you click it, and there can be thousands. This tool clicks them for you, chat by chat.

> [!WARNING]
> **Use at your own risk.** This is a hobby tool that comes with **no warranty and no guarantee of any kind**. The author accepts **no responsibility for anything that goes wrong**, including lost data, a broken WhatsApp installation, or restrictions or bans on your WhatsApp account. Automating the WhatsApp app **may be against WhatsApp's Terms of Service**. This project is **not affiliated with, authorised by or endorsed by WhatsApp or Meta**. See [LICENSE](LICENSE).

**Status:** the pressing and scrolling logic was used on one Mac to fetch several thousand files. The `--types` choice, the `--count` option and the merged `run.sh` were added while preparing this public version and **have not yet been tried against a live WhatsApp**. Run with `--dry` first and please report problems.

## How it works

1. It reads WhatsApp's own database on your Mac to learn which chats have files that were never downloaded, and at what minute each one was sent. The database is opened **read-only**; nothing in it is changed.
2. It opens each of those chats in the WhatsApp window, the same way you would, and scrolls up through the history.
3. For every message that matches a missing file, it "presses" the bubble through macOS's Accessibility feature (the system that screen readers use). WhatsApp then downloads the file as if you had clicked it.
4. It skips quickly over stretches where nothing is missing, and remembers what it has already handled so later runs are faster.

**Privacy:** everything happens on your Mac. The tool has no network code and sends nothing anywhere. The log and state files it writes (`logs/`, `blocked.txt`, `already-there.txt`) contain chat names and message descriptions, so keep them to yourself. They are excluded from git.

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
| `--types LIST` | What to download: any of `images`, `gifs`, `files` (documents), `voice`, `video`, separated by commas, or `all`. Default: everything except video. | `./wa_download --types images,gifs` |
| `--months N` | How far back to go. Default: 3. | `./wa_download --months 12` |
| `--chat "Name"` | Only chats whose name contains this text. | `./wa_download --chat "Jane Doe"` |
| `--albums` | Album pass with the real mouse (see below). | `./wa_download --albums` |
| `--all` | Single items and albums in one pass, with the real mouse. | `./wa_download --all --months 6` |
| `--dry` | Press nothing; print what would be pressed. | `./wa_download --dry` |
| `--count` | Print the number of missing files and stop. | `./wa_download --count --months 12` |
| `--limit N` | With `--albums`/`--all`: stop a chat after N album clicks. For testing. | `./wa_download --albums --limit 2` |
| `--help` | Show the options. | `./wa_download --help` |

Videos are left out by default because they are large; add them with `--types all`. The older `--no-video` flag still works.

### Two modes

**Default: mouse-free.** Nothing touches your mouse or keyboard, so you can keep working in other apps. Conditions: the WhatsApp window must stay **on the desktop (Space) you are currently on**, not minimised and not closed. It may be hidden behind other windows. If you switch to another desktop the tool waits until you come back. This mode cannot open multi-picture **albums**; it lists them as "ALBUM not clicked".

**`--albums` (or `--all`): real mouse clicks.** Albums ignore the Accessibility press and need a true click. In this mode the tool **takes over the pointer**, brings WhatsApp to the front and clicks and scrolls for real. Do not use the Mac while it runs; moving the mouse can send a click to the wrong place. `--albums` handles albums only; `--all` does single items and albums together. An album is clicked only when every kind in it (photos, videos) is in your `--types` list.

A good routine: a default run first, then `--albums` when you can leave the Mac alone.

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

Stop it at any time with Ctrl-C.

### How long it takes

It works at roughly the speed of a patient person: about a second per file, plus scrolling. A few hundred files take minutes; several thousand files across a year of busy chats take **many hours**, so run it overnight. The downloads themselves continue in WhatsApp after a press, and a second pass usually picks up what the first one missed.

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

## License

[MIT](LICENSE). Provided "as is", without warranty of any kind.
