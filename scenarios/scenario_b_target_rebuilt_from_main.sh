#!/bin/bash
# Scenario B — `to <target>` rebuilds <target> from origin/<mainbranch>.
#
# This is the core contract of `function to`: the deploy-trigger branch is
# disposable and is re-derived as (origin/main + release) on every deploy.
# Two things must hold, and they pull in opposite directions:
#
#   1. Anything sitting on <target> that is not in main and not in the release
#      MUST be discarded. (Regression guard: a previous version reset to
#      origin/<target>, which preserved that history and defeated the rebuild.)
#   2. The rebuild MUST use origin/main, not the operator's LOCAL main. A stale
#      local main must not silently deploy old code.
#
# Setup:
#   1. prod-live gets a commit that exists nowhere else, pushed to origin.
#   2. Cut a release with a hotfix.
#   3. THEN advance origin/main with a commit that is NOT in the release, and
#      rewind LOCAL main behind it. The ordering matters: if the main-only
#      commit were created before the roll it would also be inside the release
#      branch, and would arrive via the merge even if a stale local main had
#      been used — the assertion would pass vacuously.
#   4. Run `git release to prod-live`.
#
# Expected: rc=0; origin/prod-live contains the release tip and the main-only
#           commit, and does NOT contain the discarded prod-live commit.

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_lib.sh"

setup_sandbox

note "Setup: prod-live at M0 in origin"
create_branch_from prod-live main
push_branch prod-live

note "Setup: commit a throwaway change directly on prod-live and push"
commit_on   prod-live    extra.txt   "extra"   "prod-live: throwaway commit X"
push_branch prod-live
DISCARD_SHA=$(cd "$REPO" && git rev-parse prod-live)
note "commit that must be discarded: $DISCARD_SHA"

note "Setup: hotfix branch + release"
create_branch_from feature/hotfix main
commit_on   feature/hotfix   fix.txt   "fix"   "hotfix"
push_branch feature/hotfix
run_release init v1.0.0 0
run_release add origin/feature/hotfix
run_release roll <<< "n"
RELEASE_BRANCH=$(cd "$REPO" && "$GIT_RELEASE_BIN" releasebranch | tr -d '\n')
RELEASE_TIP=$(cd "$REPO" && git rev-parse "$RELEASE_BRANCH")
note "release branch = $RELEASE_BRANCH @ $RELEASE_TIP"

note "Setup: AFTER the roll, advance origin/main with a commit not in the release"
commit_on   main   important.txt   "important"   "main: important fix (post-roll)"
push_branch main -f
MAIN_FIX_SHA=$(cd "$REPO" && git rev-parse main)
note "main-only commit: $MAIN_FIX_SHA"

note "Confirm the main-only commit is genuinely absent from the release branch"
if (cd "$REPO" && git merge-base --is-ancestor "$MAIN_FIX_SHA" "$RELEASE_BRANCH" 2>/dev/null)
	then bad "precondition broken: $MAIN_FIX_SHA is in the release branch — test would pass vacuously"
	else ok  "precondition: main-only commit is not in the release branch"
fi

note "Setup: rewind LOCAL main so it is stale relative to origin/main"
(
	cd "$REPO"
	git checkout --quiet main
	git reset --hard --quiet "$MAIN_FIX_SHA~1"
)
note "LOCAL main deliberately stale at: $(cd "$REPO" && git rev-parse main)"

note "Action: run 'git release to prod-live' (release NOT merged back to main)"
run_release to prod-live
assert_rc 0 "to prod-live succeeds"
# Merge-back happens after the deploy in this workflow, so the deploy must not
# complain that main has not received the release yet.
assert_output_not_contains "ERROR:" "no error on a deploy that precedes merge-back"
assert_output_not_contains "silent fix-drop" "no merge-back nag at deploy time"
assert_output_not_contains "NOT reachable from origin/" "no post-push ancestor check"

note "Verify: throwaway prod-live commit was discarded"
if git --git-dir="$ORIGIN" merge-base --is-ancestor "$DISCARD_SHA" prod-live 2>/dev/null
	then bad "commit $DISCARD_SHA is still in origin/prod-live — target was NOT rebuilt from main"
	else ok  "commit $DISCARD_SHA discarded — target rebuilt from main"
fi

note "Verify: main-only commit reached origin/prod-live (stale LOCAL main not used)"
if git --git-dir="$ORIGIN" merge-base --is-ancestor "$MAIN_FIX_SHA" prod-live 2>/dev/null
	then ok  "main-only commit $MAIN_FIX_SHA present — rebuild used origin/main"
	else bad "main-only commit $MAIN_FIX_SHA missing — rebuild used stale LOCAL main"
fi

note "Verify: release tip reached origin/prod-live"
if git --git-dir="$ORIGIN" merge-base --is-ancestor "$RELEASE_TIP" prod-live 2>/dev/null
	then ok  "origin/prod-live contains the release tip"
	else bad "origin/prod-live does NOT contain the release tip"
fi

summary
