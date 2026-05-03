#!/bin/bash
# Scenario A — R-a (merge-back ancestor verification) is the live guard.
#
# Setup:
#   1. main and prod-live both at commit M0 in origin.
#   2. Build a hotfix release branch off main (release tip = H1, NOT in main).
#   3. Operator runs `git release to prod-live` BEFORE merging release back to main.
#
# Expected on first run: R-a fires after the push succeeds, because origin/main
#           does not contain the release tip. Tool exits non-zero. origin/prod-live
#           HAS been updated (the push went through) — the deploy is "done from
#           the prod-live perspective" but the merge-back is missing.
#
# Recovery: operator merges the release branch back to main and pushes main.
#           No re-run of `to` is required (and would now correctly trip R-f
#           because prod-live already contains the release tip — the work is
#           done). We assert that origin/main now contains the release tip.
#
# Happy-path control case: with the merge-back done UP-FRONT (before the first
#           `to`), `to` exits 0 and R-a logs the OK message.

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_lib.sh"

setup_sandbox

note "Setup: create prod-live at M0 in origin"
create_branch_from prod-live main
push_branch prod-live

note "Setup: create hotfix branch with one commit (H1)"
create_branch_from feature/hotfix main
commit_on   feature/hotfix    fix.txt    "the fix"   "hotfix: critical patch"
push_branch feature/hotfix

note "Setup: initialize release v1.0.0 rc0, add hotfix, roll"
run_release init v1.0.0 0
assert_rc 0 "init succeeded"
run_release add origin/feature/hotfix
assert_rc 0 "add succeeded"
run_release roll <<< "n"
# `roll` may prompt for things in some configurations; if it returns nonzero,
# treat as setup failure rather than a guard finding. We tolerate a non-zero
# rc here only if the release branch was nevertheless created.
RELEASE_BRANCH=$(cd "$REPO" && "$GIT_RELEASE_BIN" releasebranch | tr -d '\n')
note "Release branch is: $RELEASE_BRANCH"
if [ -z "$(cd "$REPO" && git rev-parse --verify "$RELEASE_BRANCH" 2>/dev/null)" ]
	then bad "release branch $RELEASE_BRANCH does not exist after roll"
		summary
fi

note "Action: run 'git release to prod-live' WITHOUT merging release back to main"
run_release to prod-live
assert_rc 1 "R-a guard fires when release tip is not in origin/main"
assert_output_contains "release tip" "error mentions release tip"
assert_output_contains "NOT reachable from origin/" "error explains the gap"
assert_output_contains "silent fix-drop" "error names the failure mode"

note "Recovery: merge release back to main and push"
(
	cd "$REPO"
	git checkout --quiet main
	git pull --quiet origin main
	git merge --quiet --no-ff --no-edit "$RELEASE_BRANCH"
	git push --quiet origin main
)

note "Verify recovery: release tip is now reachable from origin/main"
RELEASE_TIP=$(cd "$REPO" && git rev-parse "$RELEASE_BRANCH")
if (cd "$REPO" && git fetch --quiet origin main && git merge-base --is-ancestor "$RELEASE_TIP" origin/main)
	then ok "release tip is now in origin/main"
else bad "release tip is NOT in origin/main after recovery — recovery is broken"
fi

# --- Happy-path control case: do the WHOLE flow with merge-back FIRST ----
note "Control: build a fresh sandbox to exercise the happy path"
trap - EXIT
rm -rf "$SANDBOX"
setup_sandbox
create_branch_from prod-live main
push_branch prod-live
create_branch_from feature/hotfix2 main
commit_on   feature/hotfix2   fix2.txt   "fix2"   "hotfix: another"
push_branch feature/hotfix2
run_release init v1.0.0 0
run_release add origin/feature/hotfix2
run_release roll <<< "n"
HAPPY_RELEASE=$(cd "$REPO" && "$GIT_RELEASE_BIN" releasebranch | tr -d '\n')

note "Control: merge release back to main FIRST (the right order)"
(
	cd "$REPO"
	git checkout --quiet main
	git pull --quiet origin main
	git merge --quiet --no-ff --no-edit "$HAPPY_RELEASE"
	git push --quiet origin main
)

note "Control action: now run 'git release to prod-live' — happy path"
run_release to prod-live
assert_rc 0 "happy path: tool exits 0 when merge-back is done first"
assert_output_contains "OK: release tip" "happy path: R-a OK message printed"
assert_output_not_contains "Already up to date" "happy path: no R-f trip"

summary
