# git-release scenario scripts

Reproducible failure-mode test scripts for the `function to` merge-back guards.
Each script builds a self-contained sandbox repo (under `mktemp -d`), exercises
one specific failure mode against `git-release`, and asserts on exit codes and
error output.

These are NOT a bats harness — there is no shared runner, no fixtures, no
plugin discovery. Each script is standalone and can be run on its own.

## Running

```bash
# From the repo root:
./scenarios/scenario_a_merge_back_happy_path.sh
./scenarios/scenario_a2_skip_hatch.sh
./scenarios/scenario_b_stale_local_target.sh
./scenarios/scenario_c_topology_mismatch.sh
```

Each script prints `PASS` / `FAIL` lines and a final `RESULT` summary. Exit
code is 0 if all assertions passed, 1 otherwise.

## Inspecting a failed run

Each scenario destroys its sandbox on exit. To keep the sandbox around for
manual inspection:

```bash
KEEP_SANDBOX=1 ./scenarios/scenario_b_stale_local_target.sh
# ... look at the printed sandbox path ...
```

## Pointing at a different `git-release` build

By default the scripts run the `git-release` executable in the parent directory.
Override with:

```bash
GIT_RELEASE_BIN=/path/to/git-release ./scenarios/scenario_a_merge_back_happy_path.sh
```

## What each scenario covers

| Script | Guard exercised | Expected outcome |
|--------|------------------|------------------|
| `scenario_a_merge_back_happy_path.sh` | R-a (ancestor check) | Tool aborts when release tip is not in `origin/main`; succeeds after merge-back. |
| `scenario_a2_skip_hatch.sh` | R-a escape hatch | `GIT_RELEASE_SKIP_ANCESTOR_CHECK=1` bypasses R-a with a logged warning. |
| `scenario_b_stale_local_target.sh` | R-e (stale local target) | Tool aborts before the merge; `origin/<target>` is unchanged. |
| `scenario_c_topology_mismatch.sh` | R-f (`Already up to date.`) | Tool aborts after the merge but before the push; `origin/<target>` is unchanged. |

## Why a sandbox repo and not a real-repo clone

The scripts force-push, reset --hard, and otherwise mutate refs aggressively.
They MUST run in a throwaway repo. Never point them at a working clone.
