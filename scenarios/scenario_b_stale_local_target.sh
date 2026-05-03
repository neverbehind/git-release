#!/bin/bash
# Scenario B — R-e (refuse stale local target) is the live guard.
#
# Setup:
#   1. main, prod-live both at M0.
#   2. Push commit X to origin/prod-live (so origin is one ahead of local
#      because we'll then rewind local).
#   3. Locally rewind prod-live to M0 (one commit behind origin/prod-live).
#   4. Cut a release branch with a hotfix.
#   5. Operator runs `git release to prod-live`.
#
# Expected: R-e fires BEFORE the reset/merge/push. Tool exits non-zero.
#           origin/prod-live is unchanged from its pre-action state.

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_lib.sh"

setup_sandbox

note "Setup: prod-live at M0 in origin"
create_branch_from prod-live main
push_branch prod-live

note "Setup: push commit X to origin/prod-live"
commit_on   prod-live    extra.txt   "extra"   "prod-live: extra commit X"
push_branch prod-live

note "Setup: rewind LOCAL prod-live to M0 (one commit behind origin)"
(
	cd "$REPO"
	git checkout --quiet prod-live
	git reset --hard --quiet HEAD~1
)
ORIGIN_PROD_BEFORE=$(origin_sha prod-live)
note "origin/prod-live is at: $ORIGIN_PROD_BEFORE"

note "Setup: hotfix branch + release"
create_branch_from feature/hotfix main
commit_on   feature/hotfix   fix.txt   "fix"   "hotfix"
push_branch feature/hotfix
run_release init v1.0.0 0
run_release add origin/feature/hotfix
run_release roll <<< "n"

note "Action: run 'git release to prod-live' with stale local prod-live"
run_release to prod-live
assert_rc 1 "R-e guard fires when local target is behind origin"
assert_output_contains "is 1 commit(s) behind origin/prod-live" "error names the count"
assert_output_contains "would regress origin/prod-live" "error explains the harm"
assert_output_contains "git reset --hard origin/prod-live" "error provides recovery command"

note "Verify origin/prod-live is unchanged"
assert_origin_sha_equals prod-live "$ORIGIN_PROD_BEFORE" "origin/prod-live unchanged after R-e abort"

summary
