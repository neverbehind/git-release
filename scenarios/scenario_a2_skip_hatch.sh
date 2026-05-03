#!/bin/bash
# Scenario A2 — GIT_RELEASE_SKIP_ANCESTOR_CHECK escape hatch.
#
# Same setup as Scenario A — release tip is NOT in origin/main — but the
# operator runs with GIT_RELEASE_SKIP_ANCESTOR_CHECK=1.
#
# Expected: R-a is bypassed (warning logged), but R-e and R-f remain in force
#           (we deliberately do not exercise them here — they are happy-pathed).
#           Tool exits 0.

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_lib.sh"

setup_sandbox

note "Setup: prod-live at M0; hotfix branch with H1"
create_branch_from prod-live main
push_branch prod-live
create_branch_from feature/hotfix main
commit_on   feature/hotfix    fix.txt    "the fix"   "hotfix: critical"
push_branch feature/hotfix

note "Setup: init/add/roll a release"
run_release init v1.0.0 0
run_release add origin/feature/hotfix
run_release roll <<< "n"
RELEASE_BRANCH=$(cd "$REPO" && "$GIT_RELEASE_BIN" releasebranch | tr -d '\n')

note "Action: run with GIT_RELEASE_SKIP_ANCESTOR_CHECK=1 (release NOT in main)"
OUT_FILE="$SANDBOX/last-run.out"
(
	cd "$REPO"
	GIT_RELEASE_SKIP_ANCESTOR_CHECK=1 "$GIT_RELEASE_BIN" to prod-live
) >"$OUT_FILE" 2>&1
LAST_RC=$?
cat "$OUT_FILE"

assert_rc 0 "tool exits 0 when escape hatch is set"
assert_output_contains "GIT_RELEASE_SKIP_ANCESTOR_CHECK=1 set" "warning logged about bypass"
assert_output_contains "was not verified against origin/" "warning explains what was skipped"

# R-a fired silently — confirm the bypass was a real bypass, not a missed guard.
note "Confirm release tip is in origin/prod-live (push happened) but NOT in origin/main"
RELEASE_TIP=$(cd "$REPO" && git rev-parse "$RELEASE_BRANCH")
ORIGIN_PROD=$(origin_sha prod-live)
if [ -n "$ORIGIN_PROD" ]
	then ok "origin/prod-live exists (push went through)"
fi
if (cd "$REPO" && git fetch --quiet origin main && git merge-base --is-ancestor "$RELEASE_TIP" origin/main)
	then bad "release tip unexpectedly IS in origin/main — bypass test is invalid"
else ok "release tip is NOT in origin/main — bypass was real"
fi

summary
