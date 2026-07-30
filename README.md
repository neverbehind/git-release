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

### `git release to <target>`

#### The contract: `<target>` is disposable

`git release to <target>` rebuilds `<target>` as
`origin/<mainbranch>` + release branch, then force-pushes it. The deploy-trigger
branches (`dev`/`stage`/`qa`/`production`) hold no history of their own and are
never a source of truth — anything committed directly to them is discarded on
the next deploy. That is intentional, and it is why the push is `-f`.

The reset base is `origin/<mainbranch>`, not local `$(mainbranch)`: the remote
ref has just been refreshed by `fetchall`, whereas the operator's local main may
be arbitrarily stale and would silently deploy old code.

`to` does not verify anything about main after the push. Merge-back to main
happens *after* the deploy, so a deploy-time check could only ever report a
merge-back that has not happened yet.

#### No-op release merge is a notice, not an error

If merging the release into `<target>` reports `Already up to date.`, the tool
prints a `NOTICE` and continues. Since `<target>` was just reset to
`origin/<mainbranch>`, a no-op merge simply means `origin/main` already contains
the release tip — normal after a previous cycle's merge-back, or when
redeploying an already-merged RC.

> **If you are on a build between `531692e` and this change, upgrade.** That
> version shipped three checks in `to` that broke normal use:
>
> - It reset `<target>` to `origin/<target>` instead of to main, so `<target>`
>   accumulated history instead of being re-derived from main — the deploy
>   branch was never actually reset.
> - **R-e** aborted when local `<target>` was behind `origin/<target>` — i.e. it
>   defended the branch this command exists to force-push.
> - **R-a** required the release tip to be in `origin/<mainbranch>` immediately
>   after the deploy push, and **R-f** hard-failed on `Already up to date.`
>   These contradicted each other: R-a demanded merge-back, R-f punished it.
>
> All three are removed. `GIT_RELEASE_SKIP_ANCESTOR_CHECK` was R-a's escape
> hatch and is now a no-op — it can be dropped from any wrapper scripts.

#### Scenario scripts

Reproducible behavior tests live in `scenarios/`. See `scenarios/README.md` for
how to run them.

#### Known parity gap

`git release deploy` (the older multi-environment path) is unchanged. It still
does `git reset --hard "$(mainbranch)"` for non-prod environments — the same
rebuild-from-main intent as `to`, but off **local** main, so it retains the
staleness hazard that `to` now avoids.

