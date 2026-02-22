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
