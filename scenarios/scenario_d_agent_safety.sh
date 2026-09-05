#!/bin/bash
# Scenario D — unattended (agent / CI) safety guards.
#
# Covers the failure modes that appear only when stdin is not a terminal:
#
#   1. A prompting command must NOT proceed with an empty answer. Before the
#      guard, `init` wrote releases.current=release-v and `deploy` hard-reset
#      whatever branch the operator was standing on.
#   2. `deploy` must resolve its environment to a real branch before touching
#      the working tree.
#   3. Dispatch must not hand an unrecognised word to the shell.
#   4. `add` must reject an empty ref instead of storing one.
#   5. `cleanupmergedremotebranches` must skip branches in the current release.
#   6. The whole unattended happy path (roll -> to -> merge -> tag) must exit 0.
#
# Every git-release call here redirects stdin from /dev/null so the script
# behaves identically whether a human runs it in a terminal or CI does.

set -u
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"

INTERACTIVE_RC=78   # git-release: "needs an interactive answer"
USAGE_RC=64         # git-release: "not a git release command"

# Like run_release, but with stdin explicitly detached.
run_unattended() {
	OUT_FILE="$SANDBOX/last-run.out"
	(
		cd "$REPO"
		"$GIT_RELEASE_BIN" "$@"
	) >"$OUT_FILE" 2>&1 </dev/null
	LAST_RC=$?
	cat "$OUT_FILE"
}

setup_sandbox

note "Preparing a release with one feature branch"
(
	cd "$REPO"
	git checkout --quiet -b dev main && git push --quiet -u origin dev
	git checkout --quiet main
)
create_branch_from "feature/a" "main"
commit_on "feature/a" "a.txt" "a" "feature a"
push_branch "feature/a"
(cd "$REPO" && git checkout --quiet main)

# --- 1. Value prompts refuse to run unattended ------------------------------

note "1. 'init' with no arguments must refuse, not invent an empty version"
(cd "$REPO" && git config --local --remove-section releases 2>/dev/null)
run_unattended init > /dev/null
assert_rc "$INTERACTIVE_RC" "init without args aborts"
assert_output_contains "stdin is not a terminal" "init explains why it stopped"
STORED=$(cd "$REPO" && git config --local --get releases.current || true)
if [ -z "$STORED" ]
	then ok "no releases.current was written"
	else bad "releases.current was written as '$STORED'"
fi

note "Initializing properly for the rest of the scenario"
run_unattended init 1.0.0 0 > /dev/null
assert_rc 0 "init with both args is non-interactive"

note "1b. 'dump' must not act on an empty confirmation"
run_unattended dump > /dev/null
assert_rc "$INTERACTIVE_RC" "dump aborts rather than reading an empty answer"

# --- 2. deploy resolves its environment before touching the tree ------------

note "2. 'deploy' with an unknown environment must not reset the current branch"
run_unattended add "origin/feature/a" > /dev/null
run_unattended roll > /dev/null
assert_rc 0 "roll succeeded"

(
	cd "$REPO"
	git checkout --quiet -b precious "origin/main"
	echo "work I care about" > precious.txt
	git add precious.txt
	git commit --quiet -m "local work"
)
BEFORE_SHA=$(cd "$REPO" && git rev-parse HEAD)

run_unattended deploy nonsense > /dev/null
assert_rc 1 "deploy rejects an unknown environment"
assert_output_contains "unknown deploy environment" "deploy says which environments exist"

AFTER_SHA=$(cd "$REPO" && git rev-parse HEAD)
if [ "$BEFORE_SHA" = "$AFTER_SHA" ]
	then ok "the branch we were standing on is untouched"
	else bad "current branch was rewritten ($BEFORE_SHA -> $AFTER_SHA)"
fi
if (cd "$REPO" && [ -f precious.txt ])
	then ok "uncommitted-adjacent local work survived"
	else bad "local work was destroyed by deploy"
fi

note "2b. 'deploy' with no environment must refuse rather than prompt-and-continue"
run_unattended deploy > /dev/null
assert_rc "$INTERACTIVE_RC" "deploy without an environment aborts"

(cd "$REPO" && git checkout --quiet main)

# --- 3. Dispatch does not run arbitrary shell commands ----------------------

note "3. Dispatch must reject anything that is not a git-release function"
run_unattended echo INJECTED > /dev/null
assert_rc "$USAGE_RC" "'git release echo' is refused"
assert_output_not_contains "INJECTED" "the shell command did not run"

run_unattended statuss > /dev/null
assert_rc "$USAGE_RC" "a typo gets a usage error, not 'command not found'"

# --- 4. add rejects an empty ref -------------------------------------------

note "4. 'add' with no ref must not store an empty branch entry"
BEFORE_COUNT=$(cd "$REPO" && git config --local --get-all releases.branches | wc -l | tr -d ' ')
run_unattended add > /dev/null
assert_rc 1 "bare 'add' fails"
AFTER_COUNT=$(cd "$REPO" && git config --local --get-all releases.branches | wc -l | tr -d ' ')
if [ "$BEFORE_COUNT" = "$AFTER_COUNT" ]
	then ok "branch list unchanged ($AFTER_COUNT entries)"
	else bad "branch list grew from $BEFORE_COUNT to $AFTER_COUNT"
fi

# --- 5. Remote cleanup protects branches in the current release -------------

note "5. 'cleanupmergedremotebranches' must skip branches in the current release"
(
	cd "$REPO"
	git checkout --quiet main
	git merge --quiet --no-ff --no-edit "origin/feature/a" -m "merge feature/a"
	git push --quiet origin main
)
# GIT_RELEASE_ASSUME_TTY is required to reach the loop at all; that is the point
# of the guard. Answer the confirmation, then 'auto' for the rest.
OUT_FILE="$SANDBOX/last-run.out"
(
	cd "$REPO"
	printf 'y\nauto\n' | GIT_RELEASE_ASSUME_TTY=1 "$GIT_RELEASE_BIN" cleanupmergedremotebranches
) >"$OUT_FILE" 2>&1
LAST_RC=$?
cat "$OUT_FILE"
assert_output_contains "Skipping feature/a" "the release's own branch is protected"
if origin_sha "feature/a" > /dev/null
	then ok "origin/feature/a still exists"
	else bad "origin/feature/a was deleted while it is in the current release"
fi

# --- 6. The unattended happy path ------------------------------------------

note "6. roll -> to -> merge -> tag must all complete with stdin detached"
for STEP in "to dev" "merge main" "tag"
do
	# shellcheck disable=SC2086
	run_unattended $STEP > /dev/null
	assert_rc 0 "'git release $STEP' exits 0 unattended"
done

REL=$(cd "$REPO" && "$GIT_RELEASE_BIN" releasebranch)
(cd "$REPO" && git fetch --quiet --all)
if (cd "$REPO" && git merge-base --is-ancestor "$REL" origin/dev)
	then ok "origin/dev carries the release"
	else bad "origin/dev does not carry the release"
fi
if (cd "$REPO" && git merge-base --is-ancestor "$REL" origin/main)
	then ok "the release merged back to main"
	else bad "the release did not merge back to main"
fi

summary
