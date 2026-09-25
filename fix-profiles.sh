#!/bin/bash
# Repair an install that shows someone else's classes.
#
#   curl -fsSL https://jomonkey22.github.io/schooldash-install/fix-profiles.sh | bash
#
# Why this exists: until 2026-08-28 a new install copied in *every* shipped
# class profile instead of only the ones for courses you are in. Stage 3 of the
# pipeline is profile-driven, so those profiles did not just sit there — their
# course docs were fetched and their homework listed as yours. Grades were
# always your own; only the classes and assignments were wrong.
#
# The bad profiles live in your data folder, not inside the app, so reinstalling
# alone cannot clear them — and because they were written by the old code they
# carry no marker for the new code to recognise. Hence a script.
#
# Nothing is deleted: the old profiles are moved aside, timestamped.

set -uo pipefail

DATA="$HOME/Library/Application Support/Silly Bus AI/data"
SITE="${SILLYBUS_INSTALL_BASE:-https://jomonkey22.github.io/schooldash-install}"

say()  { printf '%s\n' "$*"; }
fail() { printf '\n  %s\n\n' "$*" >&2; exit 1; }

say ''
say 'Silly Bus AI — rebuild the class list for your own courses'
say '-------------------------------------------------------'

[ -d "$DATA" ] || fail "Silly Bus AI has never run on this Mac ($DATA is missing).
  Install it first:  curl -fsSL $SITE/install.sh | bash"

if [ -d "$DATA/profiles" ]; then
  count=$(ls -1 "$DATA/profiles"/*.json 2>/dev/null | wc -l | tr -d ' ')
  aside="$DATA/profiles-old-$(date +%Y%m%d-%H%M%S)"
  mv "$DATA/profiles" "$aside" || fail "could not move $DATA/profiles aside."
  say "  moved $count profile(s) aside, kept at:"
  say "    $aside"
else
  say '  no profiles folder — nothing to move aside'
fi

# Without this the launcher considers profiling already done and skips it.
# setup_profiles has no precondition check, so it never redoes itself.
if [ -f "$DATA/.setup/setup_profiles" ]; then
  rm -f "$DATA/.setup/setup_profiles" \
    || fail "could not clear $DATA/.setup/setup_profiles"
  say '  cleared the "profiles already done" marker'
fi

say ''
say '  updating Silly Bus AI and rebuilding from your own courses…'
say ''
curl -fsSL --connect-timeout 20 --max-time 300 "$SITE/install.sh" | bash \
  || fail "the reinstall did not finish. Run it on its own and read what it says:
  curl -fsSL $SITE/install.sh | bash"

say ''
say '  Done. Silly Bus AI should now list only your classes.'
say '  If it still shows classes that are not yours, send this back:'
say "    curl -fsSL $SITE/diagnose.sh | bash"
say ''
