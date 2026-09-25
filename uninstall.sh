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
#   ~/Applications/Silly Bus AI.app                       the app
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
  local dest="$TRASH/$(basename "$path").sillybus-$STAMP"
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

# Stop it first, or the app is moved out from under a running server.
# The pattern is overridable purely so this script can be tested: with it
# hardcoded, a sandbox run killed the developer's own live dashboard, which is
# a rehearsal of the accident this script is supposed to avoid.
PROC="${SILLYBUS_PROC:-Silly Bus AI.app/Contents/Resources/app/run.py}"
if pkill -f "$PROC" 2>/dev/null; then
  say '  stopped the running dashboard'
else
  say '  dashboard was not running'
fi

if [ -f "$AGENT" ]; then
  launchctl unload "$AGENT" 2>/dev/null && say '  reminders unscheduled' \
    || say '  reminders were not loaded'
fi

trash "$APP"   'the app'
# [MEASURED] 2026-09-02: this script, like the installer, only ever knew about
# ~/Applications — but the .dmg fallback tells people to drag the app wherever
# they like, and /Applications is the obvious place. An "uninstall" that
# leaves a second copy behind is not one, and the copy left behind is the old
# version, which is worse than either outcome on its own.
for other in "/Applications/Silly Bus AI.app" \
             "$HOME/Desktop/Silly Bus AI.app" \
             "$HOME/Downloads/Silly Bus AI.app"; do
  [ -e "$other" ] && trash "$other" "another copy in $(dirname "$other")"
done
trash "$DATA"  'settings, profiles and saved homework'
trash "$AGENT" 'the reminder schedule'

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
