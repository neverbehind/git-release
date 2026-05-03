# git release

Create release candidate branches with ease! `:)`

Original Motivation: http://nvie.com/posts/a-successful-git-branching-model/

Under the hood `git release` uses the git config system to store lists of branches, and creates release files that store the branch list for you.


*Install:*
Quick install: `curl -s -L https://raw.githubusercontent.com/neverbehind/git-release/main/install.sh | bash`


Repo Install:
* Checkout repo
* `bash install.sh`


*Usage Quick Start:*

> Most Common Process: Initialize release, add features, then create a the release by merging all branches in.

* `cd /to/repo`
* `git release init v0.0.0 0`
* `git release feature [partial branch name]`
* `git release roll`


*List of Commands:*
- `git release init [version] [candidate]` to configure release versions
- `git release add [full remote branch path]` to add feature branches into the list to release
- `git release feature [branch search string]` to search for and add feature branches into the list to release
- `git release deploystatus` to output the status of the release and the branches and the respective commit hash for each
- `git release remove [full remote branch path]` to remove feature branches from the list
- `git release status` to see what version you are on and the branches added
- `git release roll` to roll out a new release candidate branch, which:
 - Creates a new branch based on release versioning, incrementing the RC
 - Commits the Branch list to the new branch
 - Merges in each of the added feature branches
- `git release append` similar to roll, but doesn't create a new release branch, simple remerges all branches into the current RC
- `git release next` similar to roll, but uses current release branch as the base branch, instead of the main branch
- `git release deploy` checkout the main branch, and merge in release branch and tag commit with release tag.
- `git release dump` deletes release branch and rollsback the candidate version.
- `git release checkout` displays a list of release branches, allows for switching from release to release
- `git release devbranches` to list out branches that are contained in the development branch, that are not yet on the main branch
- `git release checkoutfeature` to find and create local branch from remote feature branch

*Helpful Tools*
- Versioning other systems can be achieved by adding a `afterversioncommit.sh` file to the repo, this file is executed after the version file is created, and committed to the repo. This is helpful for projects that use NPM packager, or composer, and you want to set the version in a package.json or composer.json file. 


## Recent Changes

### `git release to <target>` — release-merge-back guards (I40)

`git release to <target>` now hard-blocks three classes of silent failure
that previously caused fixes to disappear between releases:

- **R-e — stale local target.** Refuses to operate when the local `<target>`
  branch is behind `origin/<target>`. Force-pushing in that state would
  regress origin. Recover with:
  `git fetch origin && git checkout <target> && git reset --hard origin/<target>`.

- **R-f — `Already up to date.` is a topology mismatch.** When the merge of
  the release branch into `<target>` reports `Already up to date.`, the tool
  refuses to push. The release branch should not already be an ancestor of a
  clean `<target>` — that signals stale local state. Same recovery as R-e.

- **R-a — release tip must be in `origin/<mainbranch>` after push.** After
  the deploy push, the tool verifies that `git merge-base --is-ancestor
  <release-tip> origin/<mainbranch>` returns 0. If not, the release was
  deployed but never merged back to main — the silent fix-drop pattern. The
  error message includes the recovery commands.

In addition, a latent bug was fixed: `git release to <target>` previously did
`git reset --hard $(mainbranch)` which reset the trunk branch to LOCAL main
instead of `origin/<target>`. It now resets to `origin/<target>` (after R-e
has confirmed origin is sane).

#### Escape hatch

If you have a workflow where the deploy target is not expected to merge back
to main (likely the case for non-Fazemos consumers), set
`GIT_RELEASE_SKIP_ANCESTOR_CHECK=1` to bypass R-a only:

```bash
GIT_RELEASE_SKIP_ANCESTOR_CHECK=1 git release to <target>
```

R-e and R-f are unconditional safety checks and have no escape hatch — they
catch states where pushing would regress remote state, which is never the
intended action.

#### Scenario scripts

Reproducible failure-mode tests live in `scenarios/`. See
`scenarios/README.md` for how to run them.

#### Known parity gap

These guards live only in `function to`. `git release deploy` (the older
multi-environment path) is unchanged — it does not see the guards. If you
rely on `deploy` for production releases, file a ticket to port them.

