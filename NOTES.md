# Framework Notes

Goal: make these scripts pleasant daily tools for GitHub, Forgejo, and local Git
repos without assuming a single forge.

Current direction:

- Keep general Git helpers forge-neutral. Require `gh` only in commands that are
  explicitly GitHub-specific.
- Put shared config under the `mwu.*` Git config namespace so scripts can share
  repo-local and global defaults.
- Prefer local Git primitives over API calls when the data already exists in the
  repository.
- Refuse ambiguous or destructive states before changing branches, pushing, or
  deleting anything.
- Split local branch setup from network publishing. Scripts should avoid
  creating remote branches until the user explicitly pushes or opens a PR.
- Print short, pretty status lines and summaries that explain exactly what
  changed.
- Keep tests dependency-free and backed by temporary local bare remotes.

Known shared config keys:

- `mwu.remote`: remote used by forge-neutral Git scripts. Defaults to `origin`.
- `mwu.branchPrefix`: remote branch namespace for personal work branches.
  Defaults to `id -un`.
- `mwu.defaultbranch`: legacy/default branch cache used by older scripts. New
  scripts should prefer remote ref detection when practical.
