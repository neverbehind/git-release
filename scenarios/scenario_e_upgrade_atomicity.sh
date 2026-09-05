#!/bin/bash
# Scenario E — `upgrade` replaces the running script without corrupting it.
#
# `upgrade` used to be `curl -o ~/bin/git-release`, which truncates and rewrites
# the SAME inode. Bash reads a script incrementally, so overwriting the file a
# copy is currently executing makes that process resume at a stale byte offset
# in the new content. A real upgrade printed:
#
#   /Users/geoff/bin/git-release: line 1817: syntax error near unexpected token `)'
#
# The download had in fact succeeded — line 1817 is help text, not code. But the
# upgrade looked broken, and had the new file been shorter at that offset the
# running process could have executed a fragment of it.
#
# Downloading beside the target and `mv`-ing it into place is an atomic rename:
# the replacement gets a new inode, so the running process keeps reading the old
# one to completion.
#
# This scenario needs no network: `curl` handles file:// URLs, and
# GIT_RELEASE_UPGRADE_URL / GIT_RELEASE_INSTALL_PATH keep everything inside the
# sandbox. It must never touch the operator's real install.

set -u
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"

setup_sandbox

BIN_DIR="$SANDBOX/bin"
mkdir -p "$BIN_DIR"
INSTALLED="$BIN_DIR/git-release"
cp "$GIT_RELEASE_BIN" "$INSTALLED"
chmod +x "$INSTALLED"

# A "newer version" whose content is shifted NEAR THE TOP. This is the shape
# that reproduces the bug: bash is part-way through the file when the overwrite
# lands, so every later byte offset has to move for its saved position to point
# at different content. Padding appended at the END would leave the offset bash
# is reading identical in both files and quietly pass.
NEWVER="$SANDBOX/newversion"
{
	head -n 1 "$GIT_RELEASE_BIN"                 # keep the shebang first
	echo "# --- padding inserted near the top, shifting every later offset ---"
	i=1
	while [ "$i" -le 600 ]
	do
		echo "# pad line $i"
		i=$((i+1))
	done
	tail -n +2 "$GIT_RELEASE_BIN"
} > "$NEWVER"

ORIGINAL_SUM=$(shasum -a 256 < "$INSTALLED" | cut -d' ' -f1)
NEWVER_SUM=$(shasum -a 256 < "$NEWVER" | cut -d' ' -f1)

# Run the INSTALLED copy, upgrading itself. That self-replacement is the case
# that broke.
run_upgrade() {
	OUT_FILE="$SANDBOX/last-run.out"
	(
		cd "$REPO"
		GIT_RELEASE_UPGRADE_URL="$1" \
		GIT_RELEASE_INSTALL_PATH="$INSTALLED" \
		"$INSTALLED" upgrade
	) >"$OUT_FILE" 2>&1 </dev/null
	LAST_RC=$?
	cat "$OUT_FILE"
}

installed_sum() { shasum -a 256 < "$INSTALLED" | cut -d' ' -f1; }

# --- 1. The self-replacement is clean ---------------------------------------

note "1. A running copy upgrading itself must not corrupt its own execution"
run_upgrade "file://$NEWVER"
assert_rc 0 "upgrade succeeded"
assert_output_not_contains "syntax error" "no bogus syntax error from the self-overwrite"
assert_output_not_contains "unexpected token" "no stray parse diagnostics"

if [ "$(installed_sum)" = "$NEWVER_SUM" ]
	then ok "the new version is in place"
	else bad "installed copy does not match the downloaded version"
fi
if [ -x "$INSTALLED" ]
	then ok "the replacement is executable"
	else bad "the replacement lost its executable bit"
fi
if [ -z "$(find "$BIN_DIR" -name '.git-release.upgrade.*' 2>/dev/null)" ]
	then ok "no temp file left behind"
	else bad "a .git-release.upgrade.* temp file was left in $BIN_DIR"
fi

# --- 2. A failed download must not destroy the install ----------------------

note "2. A download that fails must leave the existing install untouched"
cp "$GIT_RELEASE_BIN" "$INSTALLED"
chmod +x "$INSTALLED"

run_upgrade "file://$SANDBOX/definitely-not-here"
assert_rc 1 "a missing source is an error"
assert_output_contains "untouched" "upgrade says the install was preserved"
if [ "$(installed_sum)" = "$ORIGINAL_SUM" ]
	then ok "the existing install is byte-for-byte intact"
	else bad "a failed download modified the install"
fi

note "2b. A download that is not valid bash must be rejected"
BROKEN="$SANDBOX/broken"
printf '#!/bin/bash\nfunction oops {\n' > "$BROKEN"   # unterminated function
run_upgrade "file://$BROKEN"
assert_rc 1 "invalid bash is refused"
assert_output_contains "not valid bash" "upgrade says why it refused"
if [ "$(installed_sum)" = "$ORIGINAL_SUM" ]
	then ok "the existing install is byte-for-byte intact"
	else bad "an invalid download replaced the install"
fi

note "2c. An empty download must be rejected"
: > "$SANDBOX/empty"
run_upgrade "file://$SANDBOX/empty"
assert_rc 1 "an empty file is refused"
if [ "$(installed_sum)" = "$ORIGINAL_SUM" ]
	then ok "the existing install is byte-for-byte intact"
	else bad "an empty download replaced the install"
fi

# --- 3. The upgraded copy actually runs -------------------------------------

note "3. The freshly installed copy must be usable"
run_upgrade "file://$NEWVER"
assert_rc 0 "upgraded again"
OUT_FILE="$SANDBOX/last-run.out"
(cd "$REPO" && "$INSTALLED" status) >"$OUT_FILE" 2>&1 </dev/null
LAST_RC=$?
if [ "$LAST_RC" -eq 0 ] || [ "$LAST_RC" -eq 1 ]
	then ok "the replaced binary executes (rc=$LAST_RC)"
	else bad "the replaced binary is broken (rc=$LAST_RC)"
fi
assert_output_not_contains "syntax error" "the replaced binary parses cleanly"

summary
