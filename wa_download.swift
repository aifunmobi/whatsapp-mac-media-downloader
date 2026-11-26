// wa_download: presses the download arrow on every photo, GIF, voice message, document (and optionally video)
// that WhatsApp for Mac has not downloaded yet. Build: swiftc -O wa_download.swift -o wa_download
// Run ./wa_download --help for the options.
import Cocoa
import ApplicationServices

let usage = """
Usage: wa_download [options]

Presses the download arrow on media that WhatsApp for Mac has not downloaded yet.

  --types LIST   What to download: a comma list of images, gifs, files, voice, stickers, video
                 (files = documents and voice messages), or "all".
                 Default: images,gifs,files,voice,stickers
  --months N     How far back to go, in months. Default: 3
  --chat "Name"  Only chats whose name contains this text
  --albums       Album pass: click multi-picture albums with the REAL mouse. Takes over
                 the pointer and keeps WhatsApp in front; do not use the Mac meanwhile.
                 Single items are left for the default (mouse-free) pass.
  --all          Single items and albums in one pass (also uses the real mouse)
  --dry          Press nothing; only print what would be pressed
  --count        Print how many files are missing, in total and by type, and exit
                 (WhatsApp is not touched)
  --limit N      With --albums/--all: stop a chat after N album clicks (for testing)
  --no-video     Remove video from the list (older spelling, kept for compatibility)
  --help         Show this text

Without --albums or --all nothing touches the mouse or keyboard, but the WhatsApp window
must stay on the current desktop (Space), not minimised or closed.
"""
let typeCodes = ["images": 1, "video": 2, "voice": 3, "files": 8, "gifs": 11, "stickers": 15]   // WhatsApp's ZMESSAGETYPE numbers
func fail(_ m: String) -> Never { FileHandle.standardError.write((m + "\n").data(using: .utf8)!); exit(2) }
var dry = false, months = 3, onlyChat: String? = nil, albumMode = false, limit = Int.max, both = false, countOnly = false
var types: Set<String> = ["images", "gifs", "files", "voice", "stickers"]
var args = Array(CommandLine.arguments.dropFirst())
func value(_ flag: String) -> String { if args.isEmpty { fail("\(flag) needs a value. Try --help") }; return args.removeFirst() }
func number(_ flag: String) -> Int { guard let n = Int(value(flag)), n > 0 else { fail("\(flag) needs a whole number above 0") }; return n }
while !args.isEmpty {
  let a = args.removeFirst()
  switch a {
  case "--help", "-h": print(usage); exit(0)
  case "--dry": dry = true
  case "--count": countOnly = true
  case "--albums": albumMode = true
  case "--all": albumMode = true; both = true
  case "--no-video": types.remove("video")
  case "--limit": limit = number(a)
  case "--months": months = number(a)
  case "--chat": onlyChat = value(a)
  case "--types":
    let list = value(a).lowercased().split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    types = []
    for t in list {
      if t == "all" { types.formUnion(typeCodes.keys) } else if typeCodes[t] != nil { types.insert(t) }
      else { fail("Unknown type \"\(t)\". Use any of: images, gifs, files, voice, stickers, video, all") }
    }
    if types.isEmpty { fail("--types needs at least one of: images, gifs, files, voice, stickers, video, all") }
  default: fail("Unknown option \(a). Try --help")
  }
}
if types.contains("files") { types.insert("voice") }   // "files" covers documents and voice messages
let noVideo = !types.contains("video")
setvbuf(stdout, nil, _IOLBF, 0)
let db = NSHomeDirectory() + "/Library/Group Containers/group.net.whatsapp.WhatsApp.shared/ChatStorage.sqlite"
func sql(_ q: String) -> [[String]] {
  let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
  p.arguments = ["-separator", "\u{1F}", "file:\(db)?mode=ro", q]
  let pipe = Pipe(); p.standardOutput = pipe; try! p.run()
  let d = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
  return String(data: d, encoding: .utf8)!.split(separator: "\n").map { $0.components(separatedBy: "\u{1F}") }
}
let since = "(strftime('%s','now','-\(months) months')-978307200)"
let media = "m.ZMESSAGETYPE IN (" + types.map { String(typeCodes[$0]!) }.sorted().joined(separator: ",") + ")"   // 1 photo, 2 video, 3 audio, 8 document, 11 GIF, 15 sticker
let missing = "(mi.ZMEDIALOCALPATH IS NULL OR mi.ZMEDIALOCALPATH='')"
func pending(_ chat: String) -> [String: Int] {   // "yyyy-MM-dd HH:mm|fromMe|type" -> missing count
  var r: [String: Int] = [:]
  for row in sql("SELECT strftime('%Y-%m-%d %H:%M', m.ZMESSAGEDATE+978307200,'unixepoch','localtime'), m.ZISFROMME, m.ZMESSAGETYPE, COUNT(*) FROM ZWAMESSAGE m JOIN ZWAMEDIAITEM mi ON mi.ZMESSAGE=m.Z_PK WHERE m.ZCHATSESSION=\(chat) AND m.ZMESSAGEDATE>\(since) AND \(media) AND \(missing) GROUP BY 1,2,3") {
    r[row[0] + "|" + row[1] + "|" + row[2]] = Int(row[3])!
  }
  return r
}

let chatQuery = "SELECT s.Z_PK, COALESCE(s.ZPARTNERNAME,s.ZCONTACTJID), COUNT(*) FROM ZWAMESSAGE m JOIN ZWAMEDIAITEM mi ON mi.ZMESSAGE=m.Z_PK JOIN ZWACHATSESSION s ON s.Z_PK=m.ZCHATSESSION WHERE m.ZMESSAGEDATE>\(since) AND \(media) AND \(missing) GROUP BY s.Z_PK ORDER BY COUNT(*) DESC"   // most open items first
guard FileManager.default.isReadableFile(atPath: db) else {
  fail("Cannot read WhatsApp's database at \(db).\nIs WhatsApp (App Store version) installed and set up? If it is, give your terminal app Full Disk Access in System Settings > Privacy & Security.")
}
if countOnly {
  let rows = sql(chatQuery).filter { onlyChat == nil || $0[1].contains(onlyChat!) }
  print("\(rows.count) chats, \(rows.reduce(0) { $0 + Int($1[2])! }) missing files")
  let names = Dictionary(uniqueKeysWithValues: typeCodes.map { (String($1), $0) })
  let ids = rows.map { $0[0] }.joined(separator: ",")
  for r in sql("SELECT m.ZMESSAGETYPE, COUNT(*) FROM ZWAMESSAGE m JOIN ZWAMEDIAITEM mi ON mi.ZMESSAGE=m.Z_PK WHERE m.ZCHATSESSION IN (\(ids)) AND m.ZMESSAGEDATE>\(since) AND \(media) AND \(missing) GROUP BY 1 ORDER BY 1") {
    print("  \(names[r[0]] ?? r[0]): \(r[1])")
  }
  exit(0)
}
guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "net.whatsapp.WhatsApp").first else {
  fail("WhatsApp is not running. Open it, wait until your chats show, then try again.")
}
guard AXIsProcessTrusted() else {
  fail("This terminal app is not allowed to control other apps yet.\nAllow it in System Settings > Privacy & Security > Accessibility, then quit and reopen the terminal and try again.")
}
let ax = AXUIElementCreateApplication(app.processIdentifier)
AXUIElementSetMessagingTimeout(ax, 8)   // never hang on an unresponsive WhatsApp
func attr(_ e: AXUIElement, _ a: String) -> AnyObject? { var v: AnyObject?; AXUIElementCopyAttributeValue(e, a as CFString, &v); return v }
func str(_ e: AXUIElement, _ a: String) -> String { (attr(e, a) as? String ?? "").replacingOccurrences(of: "\u{200E}", with: "") }
func kids(_ e: AXUIElement) -> [AXUIElement] { attr(e, "AXChildren") as? [AXUIElement] ?? [] }
func act(_ e: AXUIElement, _ a: String) { AXUIElementPerformAction(e, a as CFString) }
func first(_ e: AXUIElement, id: String) -> AXUIElement? {
  if str(e, "AXIdentifier") == id { return e }
  for c in kids(e) { if let f = first(c, id: id) { return f } }
  return nil
}
func frame(_ e: AXUIElement) -> CGRect {
  var pos = CGPoint.zero, size = CGSize.zero
  if let p = attr(e, "AXPosition") { AXValueGetValue(p as! AXValue, .cgPoint, &pos) }
  if let s = attr(e, "AXSize") { AXValueGetValue(s as! AXValue, .cgSize, &size) }
  return CGRect(origin: pos, size: size)
}
// Real mouse input (album mode only): WhatsApp must be frontmost and the pointer moves.
func realClick(_ p: CGPoint) {
  app.activate(); usleep(300000)
  for t in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
    CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: p, mouseButton: .left)!.post(tap: .cghidEventTap); usleep(120000)
  }
}
func realScrollUp(_ p: CGPoint, _ px: Int32) {
  app.activate()
  CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)!.post(tap: .cghidEventTap); usleep(80000)
  CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: px, wheel2: 0, wheel3: 0)!.post(tap: .cghidEventTap)
}
func nap(_ s: Double) { Thread.sleep(forTimeInterval: s) }
// A document that is already on the Mac opens in a separate Quick Look window; close any such extra window.
func closeExtraWindows() -> Bool {
  // Only close a window when the main one is positively identified and this one answered that it is not it.
  // (A busy WhatsApp can fail to answer; treating that as "not the main window" closed the main window.)
  var closed = false
  var others: [AXUIElement] = [], sawMain = false
  for w in (attr(ax, "AXWindows") as? [AXUIElement] ?? []) {
    var v: AnyObject?
    let err = AXUIElementCopyAttributeValue(w, "AXIdentifier" as CFString, &v)
    if (v as? String) == "SceneWindow" { sawMain = true }
    else if err == .success || err == .noValue || err == .attributeUnsupported { others.append(w) }
  }
  guard sawMain else { return false }
  for w in others {
    if let b = attr(w, "AXCloseButton") { act(b as! AXUIElement, "AXPress"); nap(0.6); closed = true }
  }
  return closed
}
func reopenMainWindowIfGone() {
  nap(1.0)
  guard (attr(ax, "AXWindows") as? [AXUIElement] ?? []).isEmpty else { return }
  nap(4.0)   // make sure it is really gone and not just slow to answer
  guard (attr(ax, "AXWindows") as? [AXUIElement] ?? []).isEmpty else { return }
  if !albumMode {   // mouse-free mode: the window is on another desktop; wait for it instead of skipping chats
    print("  WhatsApp is not on this desktop: waiting")
    while (attr(ax, "AXWindows") as? [AXUIElement] ?? []).isEmpty { nap(5.0) }
    print("  WhatsApp is back"); nap(2.0); return
  }
  print("  main window gone: reopening WhatsApp")
  let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/open"); p.arguments = albumMode ? ["-a", "WhatsApp"] : ["-g", "-a", "WhatsApp"]
  try? p.run(); p.waitUntilExit(); nap(6.0)
}
// Pressing a sticker that is already here opens a small popup (Add to Favorites, Edit sticker); cancel it.
func closePopovers() -> Bool {
  var closed = false
  for w in (attr(ax, "AXWindows") as? [AXUIElement] ?? []) {
    for c in kids(w) where (attr(c, "AXRole") as? String) == "AXPopover" { act(c, "AXCancel"); nap(0.4); closed = true }
  }
  return closed
}
func closeViewer() -> Bool {
  var closed = closePopovers()
  closed = closeExtraWindows() || closed
  for _ in 0..<6 {   // the viewer can take a moment to open, and one press sometimes is not enough
    guard let b = first(ax, id: "BackButton") else { break }
    act(b, "AXPress"); nap(0.7); closed = true
  }
  return closed
}
func firstDesc(_ e: AXUIElement, _ d: String) -> AXUIElement? {
  if str(e, "AXDescription") == d { return e }
  for c in kids(e) { if let f = firstDesc(c, d) { return f } }
  return nil
}
func firstOK(_ e: AXUIElement) -> AXUIElement? {
  if (attr(e, "AXRole") as? String) == "AXButton", ["OK", "Close", "Cancel", "Not now"].contains(str(e, "AXDescription")) || ["OK", "Close", "Cancel", "Not now"].contains(str(e, "AXTitle")) { return e }
  for c in kids(e) { if let f = firstOK(c) { return f } }
  return nil
}
// Get back to the Chats tab whatever a press opened (a channel, a dialog, the photo viewer).
func recover() {
  reopenMainWindowIfGone()
  for _ in 0..<4 {
    _ = closeExtraWindows()
    if first(ax, id: "ChatListView_TableView") != nil && first(ax, id: "BackButton") == nil { return }
    var sheet = false
    for w in (attr(ax, "AXWindows") as? [AXUIElement] ?? []) {
      for c in kids(w) where (attr(c, "AXRole") as? String) == "AXSheet" { if let b = firstOK(c) { act(b, "AXPress"); nap(1.0); sheet = true } }
    }
    if sheet { continue }
    _ = closeViewer()
    if let b = first(ax, id: "SidebarButton_Chats") { act(b, "AXPress"); nap(1.2) }
  }
}
let blockFile = "blocked.txt"   // bubbles that opened something else instead of downloading; never pressed again
let thereFile = "already-there.txt"   // bubbles whose file is already here (pressing opens the viewer): not pressed again
var there = Set((try? String(contentsOfFile: thereFile, encoding: .utf8))?.components(separatedBy: "\u{1E}") ?? [])
func markThere(_ d: String) { there.insert(d); try? there.joined(separator: "\u{1E}").write(toFile: thereFile, atomically: true, encoding: .utf8) }
var blocked = Set((try? String(contentsOfFile: blockFile, encoding: .utf8))?.components(separatedBy: "\u{1E}") ?? [])
func digits(_ s: String) -> String { s.filter { $0.isNumber } }
var rowByMouse = false
var lastStep = "start"
setvbuf(stdout, nil, _IOLBF, 0)
let debugRows = ProcessInfo.processInfo.environment["WA_DEBUG_ROWS"] != nil
func pressEscape() {
  app.activate(); usleep(300000)
  for down in [true, false] { CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: down)!.post(tap: .cghidEventTap); usleep(80000) }
}
func openChat(_ name: String) -> Bool {
  recover()
  guard let list = first(ax, id: "ChatListView_TableView") else { return false }
  let wantDigits = name.contains("+") ? digits(name) : ""
  if let t = first(ax, id: "ChatMessagesTableView") {   // already open (the selected row is not a button)
    let d = str(t, "AXDescription")
    if d.hasSuffix("with " + name) || (!wantDigits.isEmpty && digits(d) == wantDigits) {
      return true
    }
  }
  func page() -> [String] { kids(list).map { str($0, "AXDescription") } }
  var prev: [String] = []
  for _ in 0..<80 { act(list, "AXScrollUpByPage"); nap(0.3); let p = page(); if p == prev { break }; prev = p }
  prev = []
  var tops: [String] = []
  defer { if tops.count > 0 && debugRows { print("  top rows: \(tops)") } }
  for _ in 0..<80 {
    for b in kids(list) where (attr(b, "AXRole") as? String) == "AXButton" {
      let d = str(b, "AXDescription")
      if tops.count < 6 { tops.append(String(d.prefix(50))) }
      // A row with unread messages can carry extra text after the name, so accept "name," / "name " prefixes too.
      if d == name || d.hasPrefix(name + ",") || d.hasPrefix(name + " ") || d.hasPrefix(name + "\n") || (!wantDigits.isEmpty && (digits(d) == wantDigits || digits(d.components(separatedBy: "\n")[0].components(separatedBy: ", ")[0]) == wantDigits)) {
        if rowByMouse { let f = frame(b); realClick(CGPoint(x: f.midX, y: f.midY)) } else { act(b, "AXPress") }
        nap(1.2)
        return true
      }
    }
    act(list, "AXScrollDownByPage"); nap(0.3)
    let p = page(); if p == prev { break }; prev = p
  }
  return false
}
let cal = Calendar.current
let now = Date()
let inFmt = DateFormatter(); inFmt.locale = Locale(identifier: "en_US_POSIX"); inFmt.dateFormat = "MMMM d yyyy h:mm a"
let outFmt = DateFormatter(); outFmt.dateFormat = "yyyy-MM-dd HH:mm"
let re = try! NSRegularExpression(pattern: "(?:(?:([A-Z][a-z]+ \\d{1,2})(?:, (\\d{4}))?|(Today|Yesterday)),? at )?(\\d{1,2}:\\d{2})\\s*([AP]M)(?:,|\\.|$)", options: [.anchorsMatchLines])
func minuteKey(_ desc: String) -> (String, Date)? {
  let ns = desc as NSString
  guard let m = re.matches(in: desc, range: NSRange(location: 0, length: ns.length)).last else { return nil }
  func g(_ i: Int) -> String? { m.range(at: i).location == NSNotFound ? nil : ns.substring(with: m.range(at: i)) }
  let time = g(4)! + " " + g(5)!
  var date: Date?
  if let md = g(1) {
    let y = cal.component(.year, from: now)
    for yy in (g(2).map { [Int($0)!] } ?? [y, y - 1]) {   // older messages spell out the year
      if let d = inFmt.date(from: md + " \(yy) " + time), d <= now.addingTimeInterval(86400) { date = d; break }
    }
  } else {
    let base = g(3) == "Yesterday" ? cal.date(byAdding: .day, value: -1, to: now)! : now
    let f = DateFormatter(); f.locale = inFmt.locale; f.dateFormat = "MMMM d yyyy"
    date = inFmt.date(from: f.string(from: base) + " " + time)
  }
  guard let d = date else { return nil }
  return (outFmt.string(from: d), d)
}
let cutoff = cal.date(byAdding: .month, value: -months, to: now)!

var chats = sql(chatQuery)
if let o = onlyChat { chats = chats.filter { $0[1].contains(o) } }
print("\(chats.count) chats, \(chats.reduce(0) { $0 + Int($1[2])! }) missing files")
var totalPressed = 0, albums = 0
// Resume: chats finished in an interrupted pass are listed in done-chats.txt and skipped; the list is cleared when a pass completes.
let doneFile = "done-chats.txt"
let keepDone = onlyChat == nil && !dry
var doneChats = keepDone ? Set((try? String(contentsOfFile: doneFile, encoding: .utf8))?.split(separator: "\n").map(String.init) ?? []) : []
if !doneChats.isEmpty { print("resuming: \(doneChats.count) chats already finished in this pass") }
// Chats where the next item is a long scroll away are put off and finished after all the others.
var later: [[String]] = []
// Chats where a whole mouse-free run fetched almost nothing are not reopened mouse-free (left for the album run).
let staleFile = "no-progress-chats.txt"
var staleChats = albumMode || dry ? Set<String>() : Set((try? String(contentsOfFile: staleFile, encoding: .utf8))?.split(separator: "\n").map(String.init) ?? [])
func missingIn(_ pk: String) -> Int { Int(sql("SELECT COUNT(*) FROM ZWAMESSAGE m JOIN ZWAMEDIAITEM mi ON mi.ZMESSAGE=m.Z_PK WHERE m.ZCHATSESSION=\(pk) AND m.ZMESSAGEDATE>\(since) AND \(media) AND \(missing)").first?.first ?? "0") ?? 0 }
for round in 0..<2 {
let patient = round == 1
if patient && !later.isEmpty { print("-- now the \(later.count) chats that were put off") }
for c in (patient ? later : chats) {
  if doneChats.contains(c[0]) { continue }
  if staleChats.contains(c[0]) { print("== skipping \(c[1]): an earlier mouse-free run got almost nothing here"); continue }
  let missingBefore = missingIn(c[0])
  var gaveUp = false, putOff = false
  let name = c[1].replacingOccurrences(of: "\u{202A}", with: "").replacingOccurrences(of: "\u{202C}", with: "").replacingOccurrences(of: "\u{200E}", with: "")
  var pend = pending(c[0])
  _ = closeViewer()
  // Open the chat and wait for it to really show; WhatsApp is sometimes slow or ignores the first press.
  func shown() -> AXUIElement? {
    guard let t = first(ax, id: "ChatMessagesTableView") else { return nil }
    let d = str(t, "AXDescription")
    return d.hasSuffix("with " + name) || (name.contains("+") && digits(d) == digits(name)) ? t : nil
  }
  var opened: AXUIElement? = nil, found = false
  for attempt in 0..<4 where opened == nil {
    if attempt > 0 { if albumMode { print("  retrying to open \(name) (Escape + mouse click)"); pressEscape(); nap(1.0); rowByMouse = true } else { print("  retrying to open \(name)"); nap(2.0) } }
    guard openChat(name) else { continue }
    found = true
    for _ in 0..<16 where opened == nil { opened = shown(); if opened == nil { nap(0.5) } }
  }
  rowByMouse = false
  guard var table = opened else { print(found ? "SKIP \(name): chat did not open" : "SKIP \(name): not found in chat list (\(c[2]) missing)"); continue }
  if let b = firstDesc(ax, "Go to most recent message") { act(b, "AXPress"); nap(1.5) }
  print("== \(name): \(c[2]) missing")
  var seen = Set<String>(), stale = 0, pressed = 0, oldest = now, deferred: [String: Int] = [:]
  var pages = 0, lastPressed = "", losses = 0, interruptions = 0, fastBanned = "", lostOnce = Set<String>()
  func chatStillOpen() -> Bool {
    guard first(ax, id: "ChatListView_TableView") != nil, let t = first(ax, id: "ChatMessagesTableView") else { return false }
    let d = str(t, "AXDescription")
    return d.hasSuffix("with " + name) || (name.contains("+") && digits(d) == digits(name))
  }
  while stale < 10 && oldest > cutoff {
    _ = closeViewer()
    if !albumMode && (attr(ax, "AXWindows") as? [AXUIElement] ?? []).isEmpty {   // window moved to another desktop: wait, then carry on where we were
      nap(2.0)
      if (attr(ax, "AXWindows") as? [AXUIElement] ?? []).isEmpty {
        print("  WhatsApp is not on this desktop: waiting")
        while (attr(ax, "AXWindows") as? [AXUIElement] ?? []).isEmpty { nap(3.0) }
        print("  WhatsApp is back"); nap(2.0)
        if let t = first(ax, id: "ChatMessagesTableView") { table = t }
      }
    }
    // Window just came back (desktop switch) and is not readable yet: give it up to 20 s before calling the chat lost.
    if first(ax, id: "ChatListView_TableView") == nil { for _ in 0..<20 where !chatStillOpen() { nap(1.0) }; if let t = first(ax, id: "ChatMessagesTableView") { table = t } }
    if !chatStillOpen() {   // a press took us somewhere else: block that bubble, come back, and scroll to where we were
      let repeatLoss = !lastPressed.isEmpty && lostOnce.contains(lastPressed)
      if repeatLoss { losses += 1 } else { interruptions += 1 }   // first time is treated as an interruption (incoming message, a click by the user), not the bubble's fault
      print("  LOST the chat after pressing: \(lastPressed.prefix(120)) | now showing: [\(first(ax, id: "ChatMessagesTableView").map { str($0, "AXDescription") } ?? "no chat")] list: \(first(ax, id: "ChatListView_TableView") != nil) step: \(lastStep)")
      if !lastPressed.isEmpty && !lostOnce.insert(lastPressed).inserted { blocked.insert(lastPressed); try? blocked.joined(separator: "\u{1E}").write(toFile: blockFile, atomically: true, encoding: .utf8) }
      if !repeatLoss { print("  treating it as an interruption: waiting 30 s, then going back"); nap(30.0) }
      if losses > 25 || interruptions > 200 || !openChat(name) || !chatStillOpen() { print("  giving up on this chat"); gaveUp = true; break }
      table = first(ax, id: "ChatMessagesTableView")!
      if let b = firstDesc(ax, "Go to most recent message") { act(b, "AXPress"); nap(1.5) }
      // Start this chat again from the newest message; what is already fetched is no longer pending, so the fast-forward skips it.
      seen.removeAll(); deferred.removeAll(); oldest = now; pages = 0; stale = 0; fastBanned = ""
    }
    lastPressed = ""   // the chat survived the last presses: a later loss is not their fault
    pages += 1
    var fresh = false
    var dup: [String: Int] = [:]
    var lastMinute = ""
    let cells = kids(table).filter { str($0, "AXIdentifier") == "WAMessageBubbleTableViewCell" }
    for cell in cells.reversed() {   // newest first, so an album takes the time of the message after it
      let rawDesc = str(cell, "AXDescription")
      // A forwarded album is labelled "Forwarded.\nAlbum with ..."; drop that first line so it is treated as an album.
      var albumDesc = rawDesc
      for pre in ["Forwarded many times.", "Forwarded."] where albumDesc.hasPrefix(pre) { albumDesc = String(albumDesc.dropFirst(pre.count)).trimmingCharacters(in: .whitespacesAndNewlines) }
      let isAlbum = albumDesc.hasPrefix("Album with") || albumDesc.hasPrefix("Your album")
      let desc = isAlbum ? albumDesc : rawDesc
      if isAlbum {
        let mine = desc.hasPrefix("Your ") ? "1" : "0"
        let day = String(lastMinute.prefix(10))
        let key = desc + "@" + lastMinute
        guard !lastMinute.isEmpty, seen.insert(key).inserted else { continue }
        fresh = true
        guard pend.contains(where: { $0.key.hasPrefix(day) && ($0.key.hasSuffix("|" + mine + "|1") || $0.key.hasSuffix("|" + mine + "|2")) && $0.value > 0 }) else { continue }
        if dry { print("  would press: \(desc.prefix(110)) (~\(lastMinute))"); continue }
        if noVideo && desc.lowercased().contains("video") { continue }
        if !types.contains("images") && desc.lowercased().contains("photo") { continue }
        if there.contains(key) { continue }
        if !albumMode { albums += 1; print("  ALBUM not clicked (needs a real mouse click): \(desc.prefix(60)) ~\(lastMinute)"); continue }
        let f = frame(cell), tf = frame(table)
        let pt = CGPoint(x: f.midX, y: f.midY)
        if pt.y < tf.minY + 70 || pt.y > tf.maxY - 90 {   // button not safely on screen yet: retry after the next scroll
          deferred[key, default: 0] += 1
          if deferred[key]! < 10 { seen.remove(key) }
          continue
        }
        lastStep = "album click"; realClick(pt); nap(0.7)
        if closeViewer() { print("  already there: \(desc.prefix(80))"); markThere(key) } else { pressed += 1; print("  album clicked: \(desc.prefix(60)) ~\(lastMinute)"); nap(2.0) }
        if !chatStillOpen() { lastPressed = desc; break }
        if pressed >= limit { stale = 99; break }
        continue
      }
      guard let (minute, date) = minuteKey(desc) else { if seen.insert(desc).inserted { print("  ?date: \(desc.prefix(120))") }; continue }
      lastMinute = minute
      oldest = min(oldest, date)
      if seen.insert("any:" + desc).inserted { fresh = true }   // any new bubble means we are still moving up
      if desc.hasPrefix("message") || desc.hasPrefix("Your message") || desc.contains(" call, ") { continue }
      if noVideo && (desc.hasPrefix("Video") || desc.hasPrefix("Your video")) { continue }
      if albumMode && !both { continue }   // albums-only pass
      dup[desc, default: 0] += 1
      let key = desc + "#\(dup[desc]!)"
      guard seen.insert(key).inserted else { continue }
      fresh = true
      var kind = desc.lowercased()
      for pre in ["forwarded many times.", "forwarded."] { kind = kind.trimmingCharacters(in: .whitespacesAndNewlines); if kind.hasPrefix(pre) { kind = String(kind.dropFirst(pre.count)) } }
      kind = kind.trimmingCharacters(in: .whitespacesAndNewlines)
      if kind.hasPrefix("replying to"), let nl = kind.firstIndex(of: "\n") { kind = String(kind[kind.index(after: nl)...]).trimmingCharacters(in: .whitespacesAndNewlines) }
      if kind.hasPrefix("your ") { kind = String(kind.dropFirst(5)) }
      guard ["photo", "hd photo", "video", "hd video", "voice message", "audio", "gif", "document", "file", "sticker"].contains(where: { kind.hasPrefix($0) }) else {
        print("  unknown kind, not pressed: \(desc.prefix(110))"); continue
      }
      // Only press the kinds asked for with --types.
      let want = kind.hasPrefix("gif") ? "gifs" : kind.hasPrefix("sticker") ? "stickers" : kind.contains("photo") ? "images" : kind.contains("video") ? "video" : (kind.hasPrefix("document") || kind.hasPrefix("file")) ? "files" : "voice"
      guard types.contains(want) else { continue }
      // Match on type as well as minute: pressing a voice message that is already here plays it aloud.
      let code = kind.hasPrefix("gif") ? "11" : kind.hasPrefix("sticker") ? "15" : kind.contains("photo") ? "1" : kind.contains("video") ? "2" : (kind.hasPrefix("document") || kind.hasPrefix("file")) ? "8" : "3"
      // Whose message it is is not always stated (voice messages), so accept a match on either side.
      let guess = (desc.contains("Sent to ") || desc.hasPrefix("Your ")) ? "1" : "0"
      let pk = [guess, guess == "1" ? "0" : "1"].map { minute + "|" + $0 + "|" + code }.first { (pend[$0] ?? 0) > 0 } ?? ""
      guard let n = pend[pk], n > 0 else { if dry && desc.lowercased().contains("gif") { print("  gif not on the missing list: \(desc.prefix(100))") }; continue }
      if blocked.contains(desc) { continue }
      if there.contains(desc) { pend[pk] = n - 1; continue }   // known to be here already: no longer pending
      if dry { print("  would press: \(desc.prefix(110))"); continue }
      lastPressed = desc
      lastStep = "press"; act(cell, "AXPress"); nap(0.8)
      if closeViewer() { print("  already there: \(desc.prefix(80))"); markThere(desc) } else { pend[pk] = n - 1; pressed += 1; nap(0.7) }
    }
    stale = fresh ? 0 : stale + 1
    if stale > 2 { nap(1.5) }   // older history can take a moment to load
    // Fast-forward: when the next thing still to fetch is days older than what is on screen, scroll several pages without reading them.
    let oldestStr = outFmt.string(from: oldest)
    if !patient, !dry, let next = pend.filter({ $0.value > 0 }).keys.map({ String($0.prefix(16)) }).filter({ $0 < oldestStr }).max(),
       let nd = outFmt.date(from: next), oldest.timeIntervalSince(nd) > 7 * 86400 {
      let gap = Int(sql("SELECT COUNT(*) FROM ZWAMESSAGE WHERE ZCHATSESSION=\(c[0]) AND ZMESSAGEDATE BETWEEN \(nd.timeIntervalSinceReferenceDate) AND \(oldest.timeIntervalSinceReferenceDate)").first?.first ?? "0") ?? 0
      if gap > 1500 { print("  next item (\(next)) is \(gap) messages further back: putting the rest of this chat off until the others are done"); putOff = true; later.append(c); break }
    }
    if !dry, fresh, let next = pend.filter({ $0.value > 0 }).keys.map({ String($0.prefix(16)) }).filter({ $0 < oldestStr }).max(),
       next != fastBanned, let nd = outFmt.date(from: next), oldest.timeIntervalSince(nd) > 3 * 86400 {
      let jump = albumMode ? 9 : 3
      lastStep = "fast-forward"
      let tf = frame(table)
      for _ in 0..<jump { if albumMode { realScrollUp(CGPoint(x: tf.midX, y: tf.midY), 260); nap(0.15) } else { act(table, "AXScrollUpByPage"); nap(0.2) } }
      nap(0.5); pages += jump
      // If that went past the target, step back and read this stretch normally.
      let dates = kids(table).filter { str($0, "AXIdentifier") == "WAMessageBubbleTableViewCell" }.compactMap { minuteKey(str($0, "AXDescription"))?.1 }
      if let top = dates.min(), top < nd {
        fastBanned = next
        for _ in 0..<jump { if albumMode { realScrollUp(CGPoint(x: tf.midX, y: tf.midY), -260); nap(0.15) } else { act(table, "AXScrollDownByPage"); nap(0.2) } }
        nap(0.5); pages -= jump
      }
      continue
    }
    lastStep = "scroll"
    if albumMode { let tf = frame(table); realScrollUp(CGPoint(x: tf.midX, y: tf.midY), 260); nap(0.6) } else { act(table, "AXScrollUpByPage"); nap(0.8) }
  }
  totalPressed += pressed
  if !albumMode && !dry && !gaveUp && !putOff && missingBefore - missingIn(c[0]) < 3 && missingBefore > 0 {
    staleChats.insert(c[0]); try? staleChats.joined(separator: "\n").write(toFile: staleFile, atomically: true, encoding: .utf8)
    print("   fetched fewer than 3 here: not reopening this chat mouse-free") }
  if keepDone && !gaveUp && !putOff { doneChats.insert(c[0]); try? doneChats.joined(separator: "\n").write(toFile: doneFile, atomically: true, encoding: .utf8) }
  print("   pressed \(pressed); reached \(outFmt.string(from: oldest))")
}
}
if keepDone { try? FileManager.default.removeItem(atPath: doneFile) }
print("DONE pressed \(totalPressed), albums skipped \(albums)")
