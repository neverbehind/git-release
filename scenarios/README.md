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
./scenarios/scenario_b_target_rebuilt_from_main.sh
./scenarios/scenario_c_no_op_merge_notice.sh
./scenarios/scenario_d_agent_safety.sh
./scenarios/scenario_e_upgrade_atomicity.sh
```

Each script prints `PASS` / `FAIL` lines and a final `RESULT` summary. Exit
code is 0 if all assertions passed, 1 otherwise.

## Inspecting a failed run

Each scenario destroys its sandbox on exit. To keep the sandbox around for
manual inspection:

```bash
KEEP_SANDBOX=1 ./scenarios/scenario_b_target_rebuilt_from_main.sh
# ... look at the printed sandbox path ...
```

## Pointing at a different `git-release` build

By default the scripts run the `git-release` executable in the parent directory.
Override with:

```bash
GIT_RELEASE_BIN=/path/to/git-release ./scenarios/scenario_b_target_rebuilt_from_main.sh
```

## What each scenario covers

| Script | Behavior exercised | Expected outcome |
|--------|--------------------|------------------|
| `scenario_b_target_rebuilt_from_main.sh` | rebuild-from-main contract | `<target>` is re-derived from `origin/main` + release: junk on `<target>` is discarded, a stale LOCAL main is not used, and a deploy that precedes merge-back exits 0 silently. |
| `scenario_c_no_op_merge_notice.sh` | no-op release merge | Tool prints a `NOTICE` and still deploys; `origin/<target>` ends up at `origin/main`. |
| `scenario_d_agent_safety.sh` | unattended (agent/CI) guards | Prompting commands exit 78 instead of acting on an empty answer; `deploy` with a bad environment leaves the current branch untouched; dispatch refuses non-commands; `add` rejects an empty ref; remote cleanup skips branches in the current release; `roll`→`to`→`merge`→`tag` all exit 0 with stdin detached. |
| `scenario_e_upgrade_atomicity.sh` | `upgrade` replacing the running script | The self-replacement leaves no bogus syntax error and no temp file; a download that is missing, empty, or not valid bash is refused and the existing install stays byte-for-byte intact. Uses `file://` URLs and sandbox paths — no network, never touches the real install. |

## Why a sandbox repo and not a real-repo clone

The scripts force-push, reset --hard, and otherwise mutate refs aggressively.
They MUST run in a throwaway repo. Never point them at a working clone.
