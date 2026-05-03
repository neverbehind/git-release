#!/bin/bash
# Scenario C — R-f (Already-up-to-date is a topology mismatch) is the live guard.
#
# Setup designed so R-e and R-a do NOT fire first, isolating R-f:
#   1. main and prod-live at M0; prod-live pushed to origin (local == origin).
#   2. Add commit P1 directly to prod-live, push (local == origin).
#   3. Build a "feature" branch from prod-live (so feature already contains P1
#      and therefore contains all of prod-live's history).
#   4. Roll a release that includes that feature.
#   5. Pre-merge the release back into main and push, so R-a will be happy.
#   6. Run `git release to prod-live`. The merge will report
#      "Already up to date." because prod-live already contains the release tip.
#
# Expected: R-f fires after the merge, before the push. Tool exits non-zero.
#           origin/prod-live unchanged.

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_lib.sh"

setup_sandbox

note "Setup: prod-live at M0, pushed to origin"
create_branch_from prod-live main
push_branch prod-live

note "Setup: add commit P1 to prod-live and push"
commit_on   prod-live    p1.txt   "p1"   "prod-live: P1 (already deployed)"
push_branch prod-live

note "Setup: feature branch derived from prod-live (so feature contains P1)"
create_branch_from feature/derived prod-live
commit_on   feature/derived   add.txt   "addition"   "feature: small addition"
push_branch feature/derived

note "Setup: init release, add feature, roll"
run_release init v1.0.0 0
run_release add origin/feature/derived
run_release roll <<< "n"
RELEASE_BRANCH=$(cd "$REPO" && "$GIT_RELEASE_BIN" releasebranch | tr -d '\n')

note "Setup: pre-merge release into main and push (so R-a passes)"
(
	cd "$REPO"
	git checkout --quiet main
	git pull --quiet origin main
	git merge --quiet --no-ff --no-edit "$RELEASE_BRANCH"
	git push --quiet origin main
)

note "Setup: prod-live is fast-forwardable to release tip — but we want R-f."
# At this point: release tip = (P1 + addition + roll commits). prod-live is at
# (M0 + P1). When the tool resets local prod-live to origin/prod-live and
# merges the release in, it will be a fast-forward / new-merge — not "Already
# up to date." — UNLESS prod-live already contains the release tip.
#
# So: fast-forward prod-live to include the release tip first, push it, so
# that prod-live now contains everything in the release. Then `to prod-live`
# will see "Already up to date." against the release.
(
	cd "$REPO"
	git checkout --quiet prod-live
	git pull --quiet origin prod-live
	git merge --quiet --no-ff --no-edit "$RELEASE_BRANCH"
	git push --quiet origin prod-live
)
ORIGIN_PROD_BEFORE=$(origin_sha prod-live)
note "origin/prod-live now contains release tip; sha=$ORIGIN_PROD_BEFORE"

note "Action: run 'git release to prod-live' — release is already an ancestor"
run_release to prod-live
assert_rc 1 "R-f guard fires when merge reports Already up to date."
assert_output_contains "Already up to date" "error quotes the git output"
assert_output_contains "topology mismatch" "error names the failure mode"
assert_output_contains "git reset --hard origin/prod-live" "error provides recovery command"

note "Verify origin/prod-live unchanged after R-f abort"
assert_origin_sha_equals prod-live "$ORIGIN_PROD_BEFORE" "origin/prod-live unchanged"

summary
