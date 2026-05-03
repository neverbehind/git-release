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

`function to` is the single chokepoint for "merge release into deployment trigger branch and push." It carries four safety checks plus one latent-bug fix:

| Helper | Requirement | When it runs | On failure |
|--------|-------------|--------------|------------|
| `is_release_branch_active` | Defensive precondition | Top of `to` | Aborts with "no release branch configured" |
| `verify_local_target_fresh` | R-e: local `<target>` must not be behind `origin/<target>` | Before `git reset --hard` | Aborts with recovery command (`git reset --hard origin/<target>`) |
| (latent fix) | `git reset --hard origin/$TRUNK_BRANCH` instead of `$(mainbranch)` | After R-e passes | n/a — bug fix |
| `verify_release_merge_not_no_op` | R-f: merge of release branch must not report "Already up to date." | After `git merge --no-ff` | Aborts before push with topology-mismatch diagnostic |
| `verify_release_in_origin_main` | R-a: release tip must be reachable from `origin/$(mainbranch)` | After `git push -f` | Aborts with merge-back recovery commands; honors `GIT_RELEASE_SKIP_ANCESTOR_CHECK=1` |

R-a's escape hatch (`GIT_RELEASE_SKIP_ANCESTOR_CHECK=1`) exists because some consumers' `to <target>` workflows legitimately don't merge back to main. R-e and R-f are unconditional — they prevent regressing origin and have no documented legitimate workflow.

The guards live ONLY in `function to`. `function deploy` (the older multi-env code path) does NOT have them; it is documented as a parity gap (it is not on the path the new guards exercise). `function status`'s `git branch --merged $(mainbranch) | grep $(releasebranch)` check is informational and uses LOCAL main — it is a near-miss for R-a and is a v1.1 candidate to harden the same way.

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
