#!/bin/bash
# Scenario C — R-f is advisory: a no-op release merge does NOT block the deploy.
#
# Because `to` resets <target> to origin/<mainbranch> before merging, an
# "Already up to date." from the release merge means origin/main ALREADY
# contains the release tip — normal after a prior cycle's merge-back, or when
# redeploying an already-merged RC. An earlier version treated this as a hard
# "topology mismatch" failure, which blocked exactly the state a healthy
# merge-back produces. It now prints a NOTICE and the deploy proceeds.
#
# Setup:
#   1. prod-live at M0, pushed.
#   2. Feature branch off main; roll a release including it.
#   3. Merge the release into main and push — so origin/main contains the
#      release tip and the subsequent merge in `to` is a no-op.
#   4. Run `git release to prod-live`.
#
# Expected: rc=0, NOTICE emitted, and origin/prod-live is force-updated to
#           origin/main (which already carries the release).

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_lib.sh"

setup_sandbox

note "Setup: prod-live at M0, pushed to origin"
create_branch_from prod-live main
push_branch prod-live

note "Setup: add commit P1 to prod-live and push (must be discarded later)"
commit_on   prod-live    p1.txt   "p1"   "prod-live: P1"
push_branch prod-live

note "Setup: feature branch off main, init release, add feature, roll"
create_branch_from feature/derived main
commit_on   feature/derived   add.txt   "addition"   "feature: small addition"
push_branch feature/derived

run_release init v1.0.0 0
run_release add origin/feature/derived
run_release roll <<< "n"
RELEASE_BRANCH=$(cd "$REPO" && "$GIT_RELEASE_BIN" releasebranch | tr -d '\n')

note "Setup: merge release into main and push — origin/main now has release tip"
(
	cd "$REPO"
	git checkout --quiet main
	git pull --quiet origin main
	git merge --quiet --no-ff --no-edit "$RELEASE_BRANCH"
	git push --quiet origin main
)
ORIGIN_MAIN=$(origin_sha main)
RELEASE_TIP=$(cd "$REPO" && git rev-parse "$RELEASE_BRANCH")
note "origin/main = $ORIGIN_MAIN (contains release tip $RELEASE_TIP)"

note "Action: run 'git release to prod-live' — release merge will be a no-op"
run_release to prod-live
assert_rc 0 "no-op release merge does not block the deploy"
assert_output_contains "Already up to date" "notice quotes the git output"
assert_output_contains "NOTICE:" "emitted as a notice, not an error"
assert_output_not_contains "topology mismatch" "no longer framed as a topology mismatch"

note "Verify origin/prod-live was force-updated to origin/main"
assert_origin_sha_equals prod-live "$ORIGIN_MAIN" "origin/prod-live == origin/main"

note "Verify release tip is present in origin/prod-live"
if git --git-dir="$ORIGIN" merge-base --is-ancestor "$RELEASE_TIP" prod-live 2>/dev/null
	then ok  "origin/prod-live contains the release tip"
	else bad "origin/prod-live does NOT contain the release tip"
fi

summary
