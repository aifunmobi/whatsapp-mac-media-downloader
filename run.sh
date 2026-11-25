#!/bin/zsh
# Unattended runner for wa_download: repeats passes while they keep helping, restarts WhatsApp
# when it gets stuck, keeps the Mac awake and writes time-stamped logs to logs/.
# Usage: ./run.sh [any wa_download options]     e.g.  ./run.sh --months 12 --types images,voice
cd "$(dirname "$0")" || exit 1
[ -x ./wa_download ] || make || exit 1

# Options that only print something need no loop.
for a in "$@"; do
  case $a in --help|-h|--count|--dry) exec ./wa_download "$@";; esac
done

mkdir -p logs
caffeinate -dims -w $$ &          # keep the Mac and its screen awake for as long as this script runs
progress=logs/progress.log
note() { echo "$(date '+%Y-%m-%d %H:%M') $1" | tee -a $progress; }
count() { ./wa_download "$@" --count | awk '{print $3}'; }   # files still missing

# One pass. If most chats could not be opened, WhatsApp is stuck: restart it and try again (3 tries).
pass() {
  local log
  for try in 1 2 3; do
    log=logs/run-$(date +%Y%m%d-%H%M%S).log      # time-stamped, so no log is ever overwritten
    pgrep -xq WhatsApp || { open -g -a WhatsApp; sleep 25; }
    ./wa_download "$@" > $log 2>&1
    local chats=$(awk 'NR==1 && $2=="chats," {print $1}' $log) skipped=$(grep -c '^SKIP' $log)
    [ "$skipped" -ge 10 ] && [ $((skipped * 2)) -gt "${chats:-0}" ] || return 0
    note "WhatsApp looked stuck ($skipped of $chats chats skipped, see $log): restarting it"
    osascript -e 'tell application "WhatsApp" to quit'; sleep 8; pkill -x WhatsApp; sleep 3
    open -g -a WhatsApp; sleep 30
  done
}

prev=$(count "$@"); note "start: $prev missing"
for round in 1 2 3 4 5 6; do
  pass "$@"
  sleep 60                                        # give the last downloads time to finish
  now=$(count "$@"); note "pass $round done: $now missing"
  [ $((prev - now)) -lt 20 ] && break             # another pass would not help much
  prev=$now
done
note "finished: $(count "$@") missing"
