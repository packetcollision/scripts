# mwu-scripts

Terminal scripts that come in handy.

Source `bootstrap.sh` from your shell profile to add `scripts/` to your `PATH`.
Git exposes any executable named `git-*` on your `PATH` as `git *`, so
`scripts/git-start` becomes `git start`.

## `git start`

Create a local branch without a username prefix and configure it to push to a
prefixed remote branch later:

```sh
git start plat-1234-fix-bug
```

With the default config, that creates:

```text
local branch:    plat-1234-fix-bug
future remote:   origin/$USER/plat-1234-fix-bug
base branch:     first remote branch found from dev, develop, development, main, master
```

Slash-containing branch names are supported. For example,
`git start feature/plat-1234-fix-bug` prepares
`origin/$USER/feature/plat-1234-fix-bug`.

### Config

These values can be set locally per repo or globally:

```sh
git config --global mwu.remote origin
git config --global mwu.branchPrefix "$(id -un)"
```

Useful Forgejo example:

```sh
git remote add forgejo git@git.808.systems:you/project.git
git config mwu.remote forgejo
git config mwu.branchPrefix enelson
git start feature/my-branch
```

`git start` also sets `push.default=upstream` in the current repo after it
creates the branch. This is intentional because the local branch name and
upstream branch name differ. The remote branch is not created by `git start`;
the first plain `git push` creates it.

Until that first push, Git may show the configured upstream as `[gone]`. That
is expected: it points at the branch that will be created when you publish.

### Assumptions and Safety

`git start`:

- must run inside a Git work tree
- refuses staged, unstaged, and untracked changes
- refuses local branch names already prefixed with `mwu.branchPrefix/`
- fetches the configured remote with `--prune`
- refuses to overwrite existing local or remote branches
- creates the branch from the first existing remote base in this order:
  `dev`, `develop`, `development`, `main`, `master`
- configures the intended upstream but does not push or create a remote branch

Run the tests with:

```sh
./tests/git-start-test.sh
```

## `git merge-pr`

Merge a pull request by number from the PR's local branch into its base branch:

```sh
git merge-pr 123
```

`git merge-pr` reads PR metadata with `gh pr view`, derives the local branch
from the PR head branch, runs `git merge --no-ff -m "Merge PR #<num>"
<local-branch>`, and pushes the updated base branch to `mwu.remote`.

If the PR head branch starts with `mwu.branchPrefix/`, that prefix is stripped
when choosing the local branch. For example, a PR head of
`enelson/feature/plat-1234-fix-bug` maps to local branch
`feature/plat-1234-fix-bug`.

### Safety

`git merge-pr`:

- must run inside a Git work tree
- requires `gh`
- refuses staged, unstaged, and untracked changes
- refuses to run unless the current branch is the PR base branch
- refuses to run unless the current `HEAD` exactly matches the fetched remote
  base branch head
- refuses to run unless the local branch exactly matches the PR head commit
- fetches the configured remote with `--prune` before checking commits
- merges with `--no-ff`
- pushes `HEAD:<base-branch>` to the configured remote

The stale-base check is an error, not a warning, because this command pushes
the merge result. If your local base is not the same commit as the fetched
remote base branch, update it before merging.

Run the tests with:

```sh
./tests/git-merge-pr-test.sh
```
