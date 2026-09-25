#!/bin/bash
# Silly Bus AI installer — fetched and run straight from the website:
#
#   curl -fsSL https://jomonkey22.github.io/schooldash-install/install.sh | bash
#
# Why this exists instead of a disk image you double-click:
#
# Silly Bus AI is not signed with a paid Apple Developer ID, so anything a
# *browser* downloads gets tagged com.apple.quarantine and Gatekeeper refuses
# to open it — "Apple could not verify Silly Bus AI is free of malware". There is
# no way around that from inside the app. The old advice, right-click → Open,
# was removed by Apple in macOS 15, so on 15 and later the only escape is a trip
# through System Settings > Privacy & Security > Open Anyway, for every single
# person who installs it.
#
# curl does not set the quarantine attribute — only LaunchServices-aware apps
# like browsers do. So a copy fetched this way is never quarantined, Gatekeeper
# is never invoked, and the app simply opens. Same bits, no warning, no
# System Settings detour.
#
# Everything lands in the user's own home folder. No administrator password is
# asked for at any point, which matters on a school-managed Mac where students
# are not admins.

set -euo pipefail

BASE="${SILLYBUS_INSTALL_BASE:-https://jomonkey22.github.io/schooldash-install}"
ARCHIVE="SillyBusAI.tar.gz"
# Overridable so the whole installer can be exercised for real — download,
# unpack, replace, verify — without touching the Applications folder, the Dock
# or launching anything. [MEASURED] 2026-09-02: this script runs on other
# people's Macs and had never once been RUN by a test; check-classmate.sh
# inspects the payload it downloads and stops there. Two of the bugs found
# this evening were in here.
APPS="${SILLYBUS_APPS:-$HOME/Applications}"
APP="$APPS/Silly Bus AI.app"
DRY_RUN="${SILLYBUS_INSTALL_DRY_RUN:-}"

say()  { printf '%s\n' "$*"; }
step() { printf '\n==> %s\n' "$*"; }
fail() { printf '\nInstall stopped: %s\n' "$*" >&2; exit 1; }

say "Silly Bus AI installer"
say "===================="

[ "$(uname -s)" = "Darwin" ] || fail "Silly Bus AI is a Mac app, and this is not a Mac."

# ---------------------------------------------------------------------------
step "Downloading Silly Bus AI"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

curl -fsSL --connect-timeout 20 --max-time 300 \
     -o "$WORK/$ARCHIVE" "$BASE/$ARCHIVE" \
  || fail "could not download from $BASE — check your internet connection and try again."

# A Netlify 404 is a valid HTML page, and curl -f mostly catches that, but a
# redirect to an error page would still leave a file here that is not an
# archive. Checking the content beats trusting the exit status.
tar -tzf "$WORK/$ARCHIVE" >/dev/null 2>&1 \
  || fail "the download was not a valid archive. The site may be mid-deploy — try again in a minute."

tar -tzf "$WORK/$ARCHIVE" | grep -q '^Silly Bus AI.app/' \
  || fail "the archive does not contain Silly Bus AI.app. Please report this."

say "    ok"

# ---------------------------------------------------------------------------
step "Installing to $APPS"

# A running copy holds its own files open, and replacing them underneath it
# leaves a half-old, half-new bundle.
#
# [MEASURED] 2026-09-09: this had NEVER ONCE fired. The pattern was
# "Silly Bus AI.app/Contents/MacOS/sillybus", the launcher's own path — but the
# last thing the launcher does is `exec "$VENV/bin/python" run.py app`, and exec
# REPLACES the process image, so from that moment the command line is
# ".../venv/bin/python .../Contents/Resources/app/run.py app" and the launcher
# path is nowhere in it. With the app running and serving on 5055, `pgrep -f`
# on the old pattern matched nothing at all. Found by installing the new .pkg
# over a live server and watching the same pid keep answering afterwards.
#
# So match the PAYLOAD path, which is in the command line of anything the
# bundle runs — run.py serve, app, refresh, keepalive — and keep the launcher
# pattern too, for the sliver of time before it execs.
#
# `pkill -f` matches ANY process whose command line contains the pattern, which
# includes a shell that merely mentions the path: it killed the very terminal
# command being used to verify this, mid-run. Harmless in production (this
# script's own command line is "bash install.sh"), but do not go wrapping the
# pattern in something a person is likely to type.
# Scoped to "$APP" — the copy about to be replaced — and NOT to a bare
# "Silly Bus AI.app/..." pattern. [MEASURED] 2026-09-09, minutes after the fix
# above: the unscoped version matched every copy on the Mac, so
# test_the_installer_installs — which points SILLYBUS_APPS at a temp folder
# — killed the REAL server running out of ~/Applications. Running the test
# suite took the student's dashboard offline. An installer may only stop the
# thing it is replacing.
running() {
  pgrep -f "$APP/Contents/Resources/app/run.py" >/dev/null 2>&1 ||
  pgrep -f "$APP/Contents/MacOS/sillybus" >/dev/null 2>&1
}
if running; then
  say "    closing the running copy first"
  pkill -f "$APP/Contents/Resources/app/run.py" 2>/dev/null || true
  pkill -f "$APP/Contents/MacOS/sillybus" 2>/dev/null || true
  sleep 1
  # SIGTERM is enough for a Flask server; say so rather than pretending if it
  # is not, because a survivor is the half-old/half-new case above.
  running && say "    (something is still running — it may keep serving old code)"
fi

mkdir -p "$APPS"

tar -xzf "$WORK/$ARCHIVE" -C "$WORK" || fail "could not unpack the download."

# Replace by moving the old one aside first, so a failure part-way leaves the
# previous install intact rather than a directory with nothing in it.
if [ -d "$APP" ]; then
  rm -rf "$APP.replacing"
  mv "$APP" "$APP.replacing"
fi
if mv "$WORK/Silly Bus AI.app" "$APP"; then
  rm -rf "$APP.replacing"
else
  [ -d "$APP.replacing" ] && mv "$APP.replacing" "$APP"
  fail "could not write to $APPS."
fi

# Belt and braces. Nothing here should carry quarantine — that is the entire
# point of installing this way — but if a future version of this script ever
# fetches through something that does set it, this keeps the promise.
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

# Ad-hoc signature: gives the bundle a stable code identity so macOS's record
# of it survives an upgrade. Not required, and not what makes it open.
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

say "    installed"

# ---------------------------------------------------------------------------
# [MEASURED] 2026-09-02: a classmate was running 0.11 and said the new tabs
# were missing. Two separate causes, and this step is the second one.
#
# This script has always installed to ~/Applications, but the .dmg fallback
# tells people to drag the app "onto your Desktop (or anywhere you like)", and
# /Applications is where most people put an app. So a second, older copy sits
# somewhere else, their Dock still points at THAT one, and every reinstall
# looks like it did nothing. Upgrading only the copy we happen to own is not
# an upgrade — the one they actually click is the one that matters.
#
# Trash, not rm: it is someone else's Mac. Recoverable, and the Trash is a
# place they already understand.
step "Clearing out other copies"

version_of() {
  cat "$1/Contents/Resources/app/VERSION" 2>/dev/null || echo "unknown"
}

trash_it() {
  osascript -e "tell application \"Finder\" to delete POSIX file \"$1\"" \
    >/dev/null 2>&1
}

NEW_VERSION="$(version_of "$APP")"
found_other=0
# The last three are the app under its pre-0.19.0.0 name, SchoolDash. Its data
# folder is picked up by the launcher on first open, so nothing is lost by
# retiring the bundle here.
for other in "/Applications/Silly Bus AI.app" \
             "$HOME/Desktop/Silly Bus AI.app" \
             "$HOME/Downloads/Silly Bus AI.app" \
             "$APPS/SchoolDash.app" \
             "/Applications/SchoolDash.app" \
             "$HOME/Desktop/SchoolDash.app"; do
  [ -d "$other" ] || continue
  found_other=1
  # Deliberately not a version comparison: the copy just installed is the one
  # that should be opened, and a stray bundle elsewhere is what breaks that.
  # (A pre-0.8 bundle has no VERSION file at all — hence "unknown".)
  say "    found another copy in $(dirname "$other") (version $(version_of "$other"))"
  # Anything still running from that path would keep serving the old code.
  # Both patterns, for the reason spelled out above: after the launcher execs,
  # only the payload path appears in the command line.
  pkill -f "$other/Contents/Resources/app/run.py" 2>/dev/null || true
  pkill -f "$other/Contents/MacOS/sillybus" 2>/dev/null || true
  pkill -f "$other/Contents/MacOS/schooldash" 2>/dev/null || true
  if trash_it "$other"; then
    say "        moved to the Trash"
  else
    say "        could not remove it — drag it to the Trash yourself,"
    say "        or it will keep opening instead of the new one"
  fi
done
[ "$found_other" = 1 ] || say "    none — the only copy is the one just installed"

# A Dock tile pointing at a copy we just trashed is a question mark on their
# Dock, and the tile is how they open the app every day.
#
# Every tool used here ships with macOS. Nothing in this script may reach for
# python3: the /usr/bin/python3 shim opens the "install developer tools"
# dialog on a Mac that has never had Xcode, which is most classmates' Macs,
# and a GUI dialog cannot be silenced with 2>/dev/null. That is also why the
# launcher installs uv and lets it fetch its own Python rather than using the
# system one. osascript's JavaScript mode is part of the OS and needs nothing.
if [ -n "$DRY_RUN" ]; then
  say "    [dry run] the Dock is left alone"
elif defaults read com.apple.dock persistent-apps 2>/dev/null \
     | grep -qE "Silly Bus AI.app|SchoolDash.app"; then
  say "    pointing your Dock icon at the new copy"
  /usr/bin/osascript -l JavaScript <<JXA >/dev/null 2>&1 || true
ObjC.import('Foundation');
var wanted = \$.NSString.stringWithUTF8String('$APP');
var defs = \$.NSUserDefaults.alloc.initWithSuiteName('com.apple.dock');
var apps = defs.arrayForKey('persistent-apps');
if (apps) {
  var kept = \$.NSMutableArray.alloc.init;
  for (var i = 0; i < apps.count; i++) {
    var tile = apps.objectAtIndex(i);
    var url = '';
    try {
      url = ObjC.unwrap(
        tile.objectForKey('tile-data').objectForKey('file-data')
            .objectForKey('_CFURLString')) || '';
    } catch (e) { url = ''; }
    // Every Silly Bus AI tile goes, wherever it pointed. One is then added
    // back, so this also cleans up duplicates from earlier installs.
    if (String(url).indexOf('Silly Bus AI.app') === -1 &&
        String(url).indexOf('SchoolDash.app') === -1) kept.addObject(tile);
  }
  var fresh = \$.NSMutableDictionary.alloc.init;
  var fileData = \$.NSMutableDictionary.alloc.init;
  fileData.setObjectForKey(wanted, '_CFURLString');
  fileData.setObjectForKey(0, '_CFURLStringType');
  var tileData = \$.NSMutableDictionary.alloc.init;
  tileData.setObjectForKey(fileData, 'file-data');
  fresh.setObjectForKey(tileData, 'tile-data');
  kept.addObject(fresh);
  defs.setObjectForKey(kept, 'persistent-apps');
  defs.synchronize;
}
JXA
  killall Dock 2>/dev/null || true
else
  defaults write com.apple.dock persistent-apps -array-add \
    "<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>$APP</string><key>_CFURLStringType</key><integer>0</integer></dict></dict></dict>" \
    2>/dev/null && killall Dock 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
step "Starting Silly Bus AI"

if [ -n "$DRY_RUN" ]; then
  say "    [dry run] not started"
else
  open "$APP" || fail "installed, but could not start it. Open it from your Dock."
fi

cat <<DONE

    Done. Silly Bus AI $NEW_VERSION is installed in $APPS.
DONE

cat <<'DONE'

    Silly Bus AI is starting now. The first launch downloads what it needs —
    a few minutes, with a notification when it is done — then opens its
    window on the Setup screen. Save your school Google sign-in there and
    press Connect; Silly Bus AI signs in to Canvas and Veracross for you.

    After that, open it from the Dock any time.

    Nothing was uploaded anywhere.

DONE
