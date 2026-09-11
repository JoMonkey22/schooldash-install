#!/bin/bash
# Why won't SchoolDash open on this Mac?
#
#   curl -fsSL https://jomonkey22.github.io/schooldash-install/diagnose.sh | bash
#
# Prints what is actually true about this machine and this install. Nothing is
# changed, nothing is uploaded — the output is for you to read or to paste to
# whoever is helping.
#
# It exists because "it won't open" has at least six different causes that look
# identical from the outside, and the person hitting it is never the person who
# can tell them apart.

set -uo pipefail

APP="$HOME/Applications/SchoolDash.app"
DATA="$HOME/Library/Application Support/SchoolDash"

line() { printf '%s\n' "------------------------------------------------------------"; }
row()  { printf '  %-34s %s\n' "$1" "$2"; }

printf '\nSchoolDash — what is wrong on this Mac\n'
line

# --- the Mac itself ---------------------------------------------------------
row "macOS" "$(sw_vers -productVersion 2>/dev/null) ($(uname -m))"
row "admin user" "$(id -Gn 2>/dev/null | grep -qw admin && echo yes || echo 'no — a managed/student account')"

# A school-managed Mac can forbid unsigned apps outright, with no "Open Anyway"
# button offered to the user. That looks exactly like a broken app and is not
# one, so it is worth naming before anything else.
gk="$(spctl --status 2>&1)"
row "Gatekeeper" "$gk"
profiles="$(profiles list -type enrollment 2>/dev/null | grep -ci "enrolled" || true)"
if [ "${profiles:-0}" -gt 0 ] || [ -d "/Library/Application Support/Mosyle" ]; then
  row "device management" "MANAGED — the school may block unsigned apps"
else
  row "device management" "none detected"
fi

line
# --- is it even installed? --------------------------------------------------
if [ ! -d "$APP" ]; then
  row "SchoolDash.app" "NOT INSTALLED at ~/Applications"
  printf '\n  The install did not finish. Run this and read what it says:\n'
  printf '    curl -fsSL https://jomonkey22.github.io/schooldash-install/install.sh | bash\n\n'
  exit 1
fi
row "SchoolDash.app" "installed"
row "  launcher is executable" "$([ -x "$APP/Contents/MacOS/schooldash" ] && echo yes || echo 'NO — this alone stops it opening')"
row "  Info.plist readable" "$(plutil -lint "$APP/Contents/Info.plist" >/dev/null 2>&1 && echo yes || echo NO)"

# --- the two things that actually block a launch ----------------------------
if xattr "$APP" 2>/dev/null | grep -q quarantine; then
  row "  quarantine flag" "PRESENT — macOS will refuse to open it"
else
  row "  quarantine flag" "absent (correct for a Terminal install)"
fi

sig="$(codesign --verify --deep "$APP" 2>&1)"
row "  code signature" "${sig:-valid}"

line
# --- has it ever run? -------------------------------------------------------
row "data folder" "$([ -d "$DATA" ] && echo exists || echo 'never created — it has not run once')"
row "python environment" "$([ -x "$DATA/venv/bin/python" ] && echo built || echo 'not built yet')"
if [ -f "$DATA/data/.first_run_complete" ]; then
  row "setup" "finished"
else
  done_steps="$(ls "$DATA/data/.setup" 2>/dev/null | tr '\n' ' ')"
  row "setup" "incomplete — done: ${done_steps:-nothing}"
fi

# --- can the launcher run at all? -------------------------------------------
# The dry run walks the whole sequence without dialogs or side effects. If this
# fails, the problem is the app; if it passes, the problem is around the app.
probe="$(SCHOOLDASH_LAUNCHER_DRY_RUN=1 \
         SCHOOLDASH_DATA_HOME="$(mktemp -d)" \
         "$APP/Contents/MacOS/schooldash" 2>&1)"
if [ $? -eq 0 ] && printf '%s' "$probe" | grep -q "first run complete"; then
  row "launcher self-test" "passes"
else
  row "launcher self-test" "FAILS — the app itself is broken"
  printf '%s\n' "$probe" | tail -6 | sed 's/^/      /'
fi

line
# --- what happened last time it tried ---------------------------------------
LOG="$DATA/logs/first_run.log"
if [ -f "$LOG" ]; then
  printf '  last few lines of the setup log:\n'
  grep -vE "^\s+File \"|^\s+[a-z_]+ = |^\s*\^+\s*$" "$LOG" | tail -8 | sed 's/^/      /'
else
  printf '  no setup log — the app has never started.\n'
fi

line
printf '\n  What to do:\n'
if xattr "$APP" 2>/dev/null | grep -q quarantine; then
  printf '  * The quarantine flag is set, which means this copy came from a\n'
  printf '    browser download rather than the Terminal command. Reinstall with:\n'
  printf '      curl -fsSL https://jomonkey22.github.io/schooldash-install/install.sh | bash\n'
elif [ "$gk" = "assessments enabled" ] && [ "${profiles:-0}" -gt 0 ]; then
  printf '  * This Mac is managed by the school and Gatekeeper is on. If the app\n'
  printf '    still will not open, the school policy is blocking unsigned apps and\n'
  printf '    no amount of reinstalling will help — that needs the IT office.\n'
else
  printf '  * Try opening it from Terminal, which prints the real reason instead\n'
  printf '    of a dialog that hides it:\n'
  printf '      "%s/Contents/MacOS/schooldash"\n' "$APP"
fi
printf '\n  Paste everything above to whoever is helping you.\n\n'
