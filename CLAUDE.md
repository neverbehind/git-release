# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**git-release** is a single-file Bash utility (~1,700 lines, ~76 functions) that automates Git Flow-style release candidate (RC) branch management. It coordinates merging multiple feature branches into versioned RC branches (e.g., `release-v1.0.0-rc3`) and handles deployment workflows across environments.

Inspired by: http://nvie.com/posts/a-successful-git-branching-model/

## Architecture

### Single Script Design
The entire tool is one executable Bash script: `git-release`. There is no build system, no tests, and no external dependencies beyond Git, Bash, and curl.

### State Management
All release state is stored in **git's local config** (`.git/config`) under the `releases.*` namespace:
- `releases.version` / `releases.candidate` — current version and RC number
- `releases.current` — active release branch name
- `releases.branches` — multi-value list of feature branches to include
- `releases.mainbranch`, `releases.stagebranch`, `releases.qabranch`, `releases.devbranch` — configurable environment branches
- `releases.*deployurl` — optional webhook URLs for deployment triggers

Release files are also written to a `releases/` directory in the repo as a backup of the branch list.

### Key Patterns
- **`FETCHED_ALL` flag**: Prevents redundant `git fetch --all` calls when functions invoke each other within a single command.
- **Merge conflict detection**: After each merge, checks `git diff --name-only --diff-filter=U` and halts auto-push if conflicts exist.
- **`afterversioncommit.sh` hook**: Optional repo-root script executed after the version file commit. Used to update package.json, composer.json, etc. Exit code 1 is tolerated during `append` (handles "nothing to commit" case).
- **Interactive prompts**: Many commands use `read` for user confirmation and array-based menus for branch selection.
- **Branch-name helpers return LOCAL refs.** `mainbranch`, `stagebranch`, `qabranch`, `devbranch` all return the *local* branch name (e.g. `main`). Any guard that compares against remote state must explicitly prepend `origin/`. Easy to forget.
- **`function rm` shadows the filesystem `rm` binary** inside this script. Use `command rm` when you actually want to delete a file from inside a function (the `to` function does this for its merge-output tempfile).

### Guards (`function to` hardening)

`function to` is the single chokepoint for "merge release into deployment trigger branch and push."

**THE CONTRACT: `<target>` IS DISPOSABLE.** `to <target>` rebuilds `<target>` as `origin/$(mainbranch)` + release branch and force-pushes it. Deploy-trigger branches (`dev`/`stage`/`qa`) carry no history of their own and are never a source of truth; anything committed directly to them is discarded on the next deploy. The pre-existing `git push -f` is the tell. **Any guard added here must protect main and the release topology, never `<target>`'s prior state** — a guard defending `origin/<target>` from being rewound is defending the very thing this command exists to rewind, and will deadlock the workflow on the second deploy of an RC.

The reset base is `origin/$MAIN_BRANCH`, not local `$(mainbranch)`: `fetchall` has just refreshed the remote ref, whereas local main may be arbitrarily stale and would silently deploy old code.

**MERGE-BACK TO MAIN HAPPENS AFTER THE DEPLOY.** `to <target>` must therefore never assert anything about `origin/$(mainbranch)` containing the release. Such a check runs before merge-back can have occurred: it fails on every deploy and returns non-zero even though the push succeeded. The right place to catch a never-merged-back release is when the next release is cut from main (`roll`/`next`) — not at deploy time.

`to` is deliberately thin. Its full helper set:

| Helper | Requirement | When it runs | On failure |
|--------|-------------|--------------|------------|
| `is_release_branch_active` | Defensive precondition | Top of `to` | Aborts with "no release branch configured" |
| `notice_release_merge_no_op` | Reports "Already up to date." from the release merge | After `git merge --no-ff` | Never blocks — prints `NOTICE` and continues |

The no-op notice is advisory *because* the reset base is main: `Already up to date.` just means `origin/main` already contains the release tip (a prior cycle's merge-back landed, or the RC is being redeployed). Benign.

**Regression history — do not reintroduce any of these.** Commit `531692e` shipped three checks that each broke normal use, all since removed:

- **Reset base changed to `origin/$TRUNK_BRANCH`** (labelled a "latent bug fix"). Half right: local main *was* a staleness hazard. But it fixed that by preserving `<target>`'s history, defeating the rebuild-from-main contract entirely. The correct fix is `origin/$MAIN_BRANCH`, which is what the line now reads.
- **R-e** — aborted when local `<target>` was behind `origin/<target>`, i.e. defended the branch this command exists to force-push. Deadlocked the second deploy of an RC.
- **R-a** — post-push ancestor check against `origin/$(mainbranch)`, plus a hard-blocking **R-f** on `Already up to date.`. These directly contradicted each other: R-a demanded merge-back, R-f punished the topology a healthy merge-back produces. R-a also fired on every deploy in the normal deploy-then-merge-back ordering.

`GIT_RELEASE_SKIP_ANCESTOR_CHECK` was R-a's escape hatch and is now unused; the script no longer reads it.

`function deploy` (the older multi-env code path) is a parity gap: it still does `git reset --hard "$(mainbranch)"` for non-prod envs — same rebuild-from-main intent as `to`, but off LOCAL main, so it retains the staleness hazard `to` now avoids. `function status`'s `git branch --merged $(mainbranch) | grep $(releasebranch)` check is informational and uses LOCAL main.

Scenario scripts under `scenarios/` build self-contained sandbox repos and exercise each guard. Run `scenarios/scenario_*.sh` to verify.

### Core Command Groups
- **Release lifecycle**: `init`, `roll` (new RC from main), `next` (new RC from current RC), `append` (re-merge into current RC), `dump` (delete current RC)
- **Feature management**: `feature` (search/add), `add`, `remove`/`rm`, `newfeature`, `checkoutfeature`, `pushfeature`
- **Deployment**: `deploy [env]`, `stage`, `qa`, `to [branch]`, `merge`, `tag`
- **Status**: `status`, `deploystatus`, `checkout`, `devbranches`, `stagebranches`, `qabranches`
- **Cleanup**: `cleanup`, `cleanrelease`, `cleanupmergedlocalbranches`, `cleanupmergedremotebranches`, `purgelocalbranches`

## Development

### Running Locally
```bash
# Direct execution from repo
./git-release [command] [args]

# Or after install (copies to ~/bin)
bash install.sh
git release [command] [args]
```

### Making Changes
Edit `git-release` directly. Functions are defined at the top level and dispatched via a `case` statement at the bottom of the script. The command name maps directly to a function name (e.g., `git release roll` calls the `roll()` function).

### Branch Naming Convention
RC branches follow: `release-v{version}-rc{candidate}` (e.g., `release-v1.0.0-rc3`)
