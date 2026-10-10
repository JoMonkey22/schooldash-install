#!/bin/bash
# Remove Silly Bus AI from this Mac so it can be installed fresh.
#
#   curl -fsSL https://jomonkey22.github.io/schooldash-install/uninstall.sh | bash
#
# Nothing is deleted. Everything is moved to the Trash, timestamped, so a
# mistake costs a drag back out rather than a re-login. That matters here: the
# data folder holds the signed-in browser session, and throwing it away means
# signing into Canvas and Veracross again.
#
# What a full install leaves behind, all of it handled below:
#   ~/Applications/Silly Bus AI.app                       the app (one-liner)
#   /Applications/Silly Bus AI.app                        the app (.dmg drag)
#   ~/Library/Application Support/Silly Bus AI            config, profiles,
#                                                       state.db, logs, the
#                                                       venv, browser session
#   ~/Library/LaunchAgents/com.sillybus.notify.plist  the 07:00/17:00 reminders
#   the Dock tile                                       cosmetic; see the end
#
# Paths are overridable so this can be tested without touching a real install.

set -uo pipefail

APP="${SILLYBUS_APP:-$HOME/Applications/Silly Bus AI.app}"
DATA="${SILLYBUS_DATA:-$HOME/Library/Application Support/Silly Bus AI}"
AGENT="${SILLYBUS_AGENT:-$HOME/Library/LaunchAgents/com.sillybus.notify.plist}"
TRASH="${SILLYBUS_TRASH:-$HOME/.Trash}"
# A test run (any path above overridden) never reaches for the real
# /Applications, Desktop or Downloads copies unless it names a stand-in for
# the system folder — the same lesson as SILLYBUS_PROC below. Before
# 2026-10-07 the loop over those copies ran even in a sandboxed rehearsal.
if [ -n "${SILLYBUS_APP:-}${SILLYBUS_DATA:-}${SILLYBUS_AGENT:-}" ]; then
  SANDBOXED=1
  SYSTEM_APPS="${SILLYBUS_SYSTEM_APPS:-}"
else
  SANDBOXED=
  SYSTEM_APPS="${SILLYBUS_SYSTEM_APPS:-/Applications}"
fi
STAMP="$(date +%Y%m%d-%H%M%S)"
moved=0

say() { printf '%s\n' "$*"; }

# Moving to the Trash, not deleting. A name collision would make `mv` nest one
# folder inside another, so every move gets the timestamp appended.
trash() {
  local path="$1" label="$2"
  if [ ! -e "$path" ]; then
    say "  $label: not present"
    return 0
  fi
  local dest="$TRASH/$(basename "$path").sillybus-$STAMP" n=2
  # Two copies with one name (~/Applications and /Applications) in the same
  # second: without this the second `mv` lands INSIDE the first.
  while [ -e "$dest" ]; do
    dest="$TRASH/$(basename "$path").sillybus-$STAMP-$n"; n=$((n + 1))
  done
  if mv "$path" "$dest" 2>/dev/null; then
    say "  $label: moved to the Trash"
    moved=$((moved + 1))
  else
    say "  $label: COULD NOT MOVE — remove it by hand:"
    say "      $path"
  fi
}

say ''
say 'Silly Bus AI — remove it from this Mac'
say '------------------------------------'

# Every copy this script is about to move. The updater's backup is one of
# them: an old window keeps running out of it after an update.
copies=("$APP" "$APP.previous")
if [ -z "$SANDBOXED" ]; then
  copies+=("$HOME/Desktop/Silly Bus AI.app" "$HOME/Downloads/Silly Bus AI.app")
fi
[ -n "$SYSTEM_APPS" ] && copies+=("$SYSTEM_APPS/Silly Bus AI.app")

# Stop it first, or the app is moved out from under a running server.
#
# Scoped to each copy's own path, never a bare name. [MEASURED] 2026-09-09: a
# pattern that matched every copy made a sandbox run kill the developer's own
# live dashboard, a rehearsal of the accident this script is supposed to
# avoid. SILLYBUS_PROC still replaces all of it with one pattern, for tests.
#
# What runs out of a copy (2026-10-07, the native shell):
#   Contents/MacOS/SillyBusAI           the Swift window, matched by its path
#   Contents/Resources/setup.sh         first-launch setup
#   Contents/Resources/app/run.py ...   the server, refresh, keep-alive
#   Contents/MacOS/sillybus             a pre-native copy's launcher
#   python "run.py app"                 a pre-native copy's window, which has
#                                       no path in its command line — found
#                                       by its working folder instead
stopped=0
stop_pattern() {
  if pkill -f "$1" 2>/dev/null; then stopped=1; fi
  return 0
}
if [ -n "${SILLYBUS_PROC:-}" ]; then
  stop_pattern "$SILLYBUS_PROC"
else
  for copy in "${copies[@]}"; do
    stop_pattern "$copy/Contents/MacOS/SillyBusAI"
    stop_pattern "$copy/Contents/Resources/setup.sh"
    stop_pattern "$copy/Contents/Resources/app/run.py"
    stop_pattern "$copy/Contents/MacOS/sillybus"
    for pid in $(pgrep -f 'run.py app' 2>/dev/null); do
      cwd="$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -1)"
      if [ "$cwd" = "$copy/Contents/Resources/app" ] && kill "$pid" 2>/dev/null; then
        stopped=1
      fi
    done
  done
fi
if [ "$stopped" = 1 ]; then
  say '  stopped the running app'
else
  say '  the app was not running'
fi

if [ -f "$AGENT" ]; then
  launchctl unload "$AGENT" 2>/dev/null && say '  reminders unscheduled' \
    || say '  reminders were not loaded'
fi
# Every agent, not only the reminders (round 5: auto-refresh, keep-alive and
# SillyBus Lock stayed loaded against a trashed app).
AGENTS_DIR="$(dirname "$AGENT")"
# Skipped when the paths are overridden for a test run, so a rehearsal never
# stops the real agents (the same lesson as SILLYBUS_PROC above).
if [ -z "${SILLYBUS_AGENT:-}" ]; then
  for label in com.sillybus.refresh com.sillybus.keepalive com.sillybus.lock; do
    launchctl bootout "gui/$(id -u)/$label" 2>/dev/null && say "  stopped $label"
  done
fi

trash "$APP"   'the app'
# The updater keeps the version before as a fallback (round 4: left behind).
[ -e "$APP.previous" ] && trash "$APP.previous" 'the previous version the updater kept'
# [MEASURED] 2026-09-02: this script, like the installer, only ever knew about
# ~/Applications — but the .dmg fallback tells people to drag the app wherever
# they like, and /Applications is the obvious place. An "uninstall" that
# leaves a second copy behind is not one, and the copy left behind is the old
# version, which is worse than either outcome on its own.
#
# 2026-10-07: the .dmg now says to drag it into /Applications, so that is
# where most copies will be. The list is the one built above, so a test run
# only ever sees its own stand-ins.
for other in "${copies[@]}"; do
  [ "$other" = "$APP" ] || [ "$other" = "$APP.previous" ] && continue
  [ -e "$other" ] && trash "$other" "another copy in $(dirname "$other")"
  [ -e "$other.previous" ] && trash "$other.previous" "the previous version kept in $(dirname "$other")"
done
trash "$DATA"  'settings, profiles and saved homework'
trash "$AGENT" 'the reminder schedule'
trash "$AGENTS_DIR/com.sillybus.refresh.plist"   'the auto-refresh schedule'
trash "$AGENTS_DIR/com.sillybus.keepalive.plist" 'the Veracross keep-alive'
trash "$AGENTS_DIR/com.sillybus.lock.plist"      'SillyBus Lock starting at login'
# A sandboxed run only touches a Lock it was pointed at (2026-10-07: it used
# to fall through to the real ~/Applications/SillyBus Lock.app).
if [ -n "${SILLYBUS_LOCK_APP:-}" ] || [ -z "$SANDBOXED" ]; then
  trash "${SILLYBUS_LOCK_APP:-$HOME/Applications/SillyBus Lock.app}" 'SillyBus Lock'
fi

# Before 0.19.0.0 this app was SchoolDash. A Mac that ran it then has the
# same four things under the old names; an uninstall that left them would
# leave two refresh schedules running against a trashed app.
if [ -z "${SILLYBUS_APP:-}${SILLYBUS_DATA:-}${SILLYBUS_AGENT:-}" ]; then
  pkill -f "SchoolDash.app/Contents/Resources/app/run.py" 2>/dev/null && say '  stopped the old SchoolDash dashboard'
  for label in com.schooldash.notify com.schooldash.refresh com.schooldash.keepalive; do
    old="$HOME/Library/LaunchAgents/$label.plist"
    [ -f "$old" ] || continue
    launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || launchctl unload "$old" 2>/dev/null || true
    trash "$old" "the old SchoolDash schedule ($label)"
  done
  trash "$HOME/Applications/SchoolDash.app" 'the old SchoolDash app'
  trash "$HOME/Library/Application Support/SchoolDash" 'old SchoolDash settings and saved homework'
fi

say ''
if [ "$moved" -eq 0 ]; then
  say '  Nothing was found to remove — this Mac has no Silly Bus AI install.'
else
  say "  Removed $moved item(s). They are in the Trash if you want them back."
fi
say ''
say '  A fresh install is one line:'
say '    curl -fsSL https://jomonkey22.github.io/schooldash-install/install.sh | bash'
say ''
say '  The old Dock tile may linger until you log out; drag it off if it does.'
say '  A fresh install signs into Canvas and Veracross again from scratch.'
say ''
