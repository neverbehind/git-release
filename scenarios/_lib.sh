#!/bin/bash
# Sandbox helpers for `function to` guard scenario tests.
#
# Each scenario sources this file, then calls `setup_sandbox` to build a
# self-contained playground in $TMPDIR with:
#   - a bare repo (the simulated "origin")
#   - a working clone (the operator's local repo) pre-configured for git-release
#
# The playground is destroyed on EXIT unless KEEP_SANDBOX=1 is set.
#
# These scripts are NOT a bats harness. They are reproducible "I want to see
# what happens" scripts. Each one prints what it did, what it asserted, and
# whether the assertion passed.

set -u

# Resolve repo-relative path to git-release executable.
GIT_RELEASE_BIN=${GIT_RELEASE_BIN:-"$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/git-release"}
if [ ! -x "$GIT_RELEASE_BIN" ]
	then
	echo "FATAL: cannot locate git-release executable at $GIT_RELEASE_BIN" >&2
	exit 99
fi

PASS=0
FAIL=0

note() { printf "\n[%s] %s\n" "$(date +%H:%M:%S)" "$*"; }
ok()   { PASS=$((PASS+1)); printf "  PASS: %s\n" "$*"; }
bad()  { FAIL=$((FAIL+1)); printf "  FAIL: %s\n" "$*" >&2; }

# --- Sandbox setup ---------------------------------------------------------

setup_sandbox() {
	SANDBOX=$(mktemp -d -t git-release-scenario-XXXXXX)
	ORIGIN="$SANDBOX/origin.git"
	REPO="$SANDBOX/repo"
	export SANDBOX ORIGIN REPO

	if [ "${KEEP_SANDBOX:-0}" != "1" ]
		then
		trap 'rm -rf "$SANDBOX"' EXIT
	else
		trap 'echo "[sandbox kept] $SANDBOX"' EXIT
	fi

	# Bare origin
	git init --quiet --bare "$ORIGIN"

	# Working clone with an initial main commit
	mkdir -p "$REPO"
	(
		cd "$REPO"
		git init --quiet -b main
		git config user.email "scenario@example.invalid"
		git config user.name "git-release scenarios"
		echo "init" > README
		git add README
		git commit --quiet -m "init"
		git remote add origin "$ORIGIN"
		git push --quiet -u origin main
	)
}

commit_on() {
	# commit_on <branch> <file> <content> <message>
	local branch=$1 file=$2 content=$3 msg=$4
	(
		cd "$REPO"
		git checkout --quiet "$branch"
		echo "$content" > "$file"
		git add "$file"
		git commit --quiet -m "$msg"
	)
}

create_branch_from() {
	# create_branch_from <new-branch> <base-branch>
	local new=$1 base=$2
	(
		cd "$REPO"
		git checkout --quiet -b "$new" "$base"
	)
}

push_branch() {
	# push_branch <branch> [-f]
	local branch=$1 flag=${2:-}
	(
		cd "$REPO"
		if [ "$flag" = "-f" ]
			then git push --quiet -f origin "$branch"
		else git push --quiet -u origin "$branch"
		fi
	)
}

# Run git-release inside the sandbox repo. Captures stdout+stderr to file.
# Echoes the captured output AND records the exit code in $LAST_RC.
run_release() {
	OUT_FILE="$SANDBOX/last-run.out"
	(
		cd "$REPO"
		"$GIT_RELEASE_BIN" "$@"
	) >"$OUT_FILE" 2>&1
	LAST_RC=$?
	cat "$OUT_FILE"
}

assert_rc() {
	# assert_rc <expected> <description>
	local expected=$1 desc=$2
	if [ "$LAST_RC" -eq "$expected" ]
		then ok "$desc (rc=$LAST_RC)"
	else bad "$desc (expected rc=$expected, got rc=$LAST_RC)"
	fi
}

assert_output_contains() {
	# assert_output_contains <pattern> <description>
	local pattern=$1 desc=$2
	if grep -q -- "$pattern" "$OUT_FILE"
		then ok "$desc"
	else
		bad "$desc — pattern not found: $pattern"
	fi
}

assert_output_not_contains() {
	local pattern=$1 desc=$2
	if grep -q -- "$pattern" "$OUT_FILE"
		then bad "$desc — pattern unexpectedly present: $pattern"
	else ok "$desc"
	fi
}

# Origin sha for a branch (without using local refs).
origin_sha() {
	# origin_sha <branch>
	git --git-dir="$ORIGIN" rev-parse "$1" 2>/dev/null
}

assert_origin_sha_equals() {
	# assert_origin_sha_equals <branch> <expected-sha> <description>
	local branch=$1 expected=$2 desc=$3
	local actual
	actual=$(origin_sha "$branch")
	if [ "$actual" = "$expected" ]
		then ok "$desc (origin/$branch @ $actual)"
	else bad "$desc — expected origin/$branch=$expected, got $actual"
	fi
}

summary() {
	echo
	echo "================================================================"
	if [ "$FAIL" -eq 0 ]
		then echo "RESULT: ALL ASSERTIONS PASSED ($PASS pass, 0 fail)"
		exit 0
	else
		echo "RESULT: FAILURES ($PASS pass, $FAIL fail)"
		echo "Sandbox: $SANDBOX (re-run with KEEP_SANDBOX=1 to inspect)"
		exit 1
	fi
}
