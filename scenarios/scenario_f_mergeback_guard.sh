#!/bin/bash
# Scenario F — roll/next refuse to cut while production carries a release that
# was never merged back into origin/main (check_mergeback).
#
# The discriminating pair is steps 2 and 5: the SAME prod state fails before
# merge-back and passes after it. Everything else is an edge case:
#   1. no origin/prod-live yet (first release)      -> pass, NOTICE
#   2. rc on prod-live, not merged back, roll        -> FAIL, nothing created,
#                                                       candidate not consumed
#   3. override: bare "1" refused; reason accepted   -> trailer on pushed RC
#   4. next from the very RC that is on prod         -> pass (carries it), NOTICE
#   5. merge-back done, roll                         -> pass
#   6. unmerged RC only on dev-live                  -> pass (dev not checked)
#   7. prod-live tip is NOT a merge (direct commit)  -> FAIL
#   8. multi-target: second prod target unmerged     -> FAIL via GIT_RELEASE_PROD_BRANCH
#   9. next on a release that lacks the prod release -> FAIL
#
# Every command runs with stdin detached (the agent case).

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_lib.sh"

run_u() { run_release "$@" < /dev/null > /dev/null; }
cand() { (cd "$REPO" && git config --get releases.candidate); }
origin_has() { git --git-dir="$ORIGIN" rev-parse -q --verify "refs/heads/$1" > /dev/null; }
merge_back() {
	( cd "$REPO" && git checkout --quiet main && git pull --quiet origin main \
	  && git merge --quiet --no-ff --no-edit "origin/$1" && git push --quiet origin main )
}

setup_sandbox
create_branch_from feature/a main
commit_on feature/a a.txt a "feature a"
push_branch feature/a

note "1. First release: origin/prod-live does not exist"
run_u init 1.0.0 0
run_u add origin/feature/a
run_u roll
assert_rc 0 "roll passes when there is no production target yet"
assert_output_contains "prod-live not found" "says there was nothing to check"
REL1=release-v1.0.0-rc1
origin_has "$REL1" && ok "$REL1 pushed" || bad "$REL1 not pushed"

note "Deploy $REL1 to prod-live via 'to' (creates the --no-ff merge tip); NO merge-back"
( cd "$REPO" && git checkout --quiet -b prod-live main && git push --quiet -u origin prod-live )
run_u to prod-live
assert_rc 0 "to prod-live succeeds"

note "2. Roll the next version while $REL1 is on prod but not in main"
create_branch_from feature/b main
commit_on feature/b b.txt b "feature b"
push_branch feature/b
run_u init 1.1.0 0
run_u add origin/feature/b
CAND_BEFORE=$(cand)
run_u roll
assert_rc 1 "roll REFUSES: prod release never merged back"
assert_output_contains "merge-back missing" "names the defect"
assert_output_contains "git release merge main" "prints the recovery"
assert_output_contains "origin/$REL1" "names the unmerged release branch"
[ "$(cand)" = "$CAND_BEFORE" ] && ok "candidate number not consumed ($CAND_BEFORE)" || bad "candidate bumped to $(cand)"
origin_has release-v1.1.0-rc1 && bad "release-v1.1.0-rc1 was pushed anyway" || ok "nothing pushed"

note "3a. Override with a non-reason is refused"
GIT_RELEASE_SKIP_MERGEBACK_CHECK=1 run_u roll
assert_rc 1 "bare '1' is not accepted as a reason"
assert_output_contains "is not a reason" "explains why"

note "3b. Override with a reason proceeds and is recorded"
GIT_RELEASE_SKIP_MERGEBACK_CHECK="INC-42 hotfix; merge-back tracked in BUG999" run_u roll
assert_rc 0 "roll proceeds with a reasoned override"
assert_output_contains "SKIPPED: INC-42" "warns loudly"
if git --git-dir="$ORIGIN" log --format=%B release-v1.1.0-rc1 | grep -q "^Merge-back-check: skipped (INC-42"
	then ok "trailer recorded on the pushed RC"
	else bad "no Merge-back-check trailer on origin/release-v1.1.0-rc1"
fi

note "4. next from the RC that IS on prod (second prod deploy of a version)"
run_u init 1.0.0 1          # back to v1.0.0 rc1 — the one on prod
run_u next
assert_rc 0 "next from the prod RC passes (rc2 carries rc1 forward)"
assert_output_contains "carries it forward" "NOTICE that merge-back is still owed"
origin_has release-v1.0.0-rc2 && ok "release-v1.0.0-rc2 pushed" || bad "rc2 not pushed"

note "5. Merge-back $REL1, then roll: the same prod state now passes"
merge_back "$REL1"
run_u init 1.2.0 0
run_u add origin/feature/b
run_u roll
assert_rc 0 "roll passes after merge-back"
assert_output_contains "Merge-back check: OK" "reports OK"

note "6. An unmerged RC on dev-live only does not block"
( cd "$REPO" && git checkout --quiet -b dev-live main && git push --quiet -u origin dev-live )
run_u to dev-live            # release-v1.2.0-rc1 → dev, not in main
run_u init 1.3.0 0
run_u roll
assert_rc 0 "dev-live is not a production target"

note "7. prod-live tip is a direct (non-merge) commit not in main"
( cd "$REPO" && git checkout --quiet prod-live && git pull --quiet origin prod-live && git reset --quiet --hard origin/main \
  && echo hot > hot.txt && git add hot.txt && git commit --quiet -m "hotfix straight on prod" && git push --quiet -f origin prod-live )
run_u init 1.4.0 0
run_u roll
assert_rc 1 "non-merge prod tip not in main is refused"
assert_output_contains "merge-back missing" "refused by the merge-back guard"

note "8. Multi-target: prod-live clean, prod-eu carries an unmerged release"
( cd "$REPO" && git checkout --quiet prod-live && git reset --quiet --hard origin/main && git push --quiet -f origin prod-live \
  && git checkout --quiet -b prod-eu origin/dev-live && git push --quiet -u origin prod-eu )
run_u init 1.5.0 0
run_u roll
assert_rc 0 "default (prod-live only) passes"
GIT_RELEASE_PROD_BRANCH="prod-live,prod-eu" run_u roll
assert_rc 1 "with prod-eu declared, its unmerged release is refused"
assert_output_contains "origin/prod-eu carries" "names the offending target"

note "9. next on a release that lacks what prod runs (parallel-release regression)"
( cd "$REPO" && git push --quiet origin --delete prod-eu )
run_u init 2.0.0 0
run_u roll                    # v2.0.0-rc1 cut from clean main
run_u init 1.9.0 0
run_u add origin/feature/b
run_u roll                    # v1.9.0-rc1 ...
run_u to prod-live            # ... ships to prod, never merged back
run_u init 2.0.0 1
run_u next
assert_rc 1 "next from v2.0.0-rc1 refused: it would drop v1.9.0-rc1 from prod"
assert_output_contains "origin/release-v1.9.0-rc1" "names v1.9.0-rc1 as the unmerged release"

summary
