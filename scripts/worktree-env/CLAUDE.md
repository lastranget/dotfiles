# worktree-env

Worktree-aware overrides for per-repo dev-environment launcher scripts (`env.sh`
and friends), plus the `e` command that dispatches to them.

## Why this exists

Several repos (e.g. `biofinder`) ship an `env.sh` that spins up a Docker
"dev environment" container and runs commands inside it. That stock `env.sh`:

- sets `PROJECT_ROOT` to the directory the script lives in, and
- names the container with a single **fixed** name (e.g.
  `biofinder-dev-environment`).

When you use **git worktrees**, this breaks silently. `run.sh` reuses any
already-running container with that fixed name — regardless of which directory
it was bound to. So if a container is up for the primary checkout and you run
`env.sh` from a worktree, your build/test/lint runs against the **primary
checkout's** files, not the worktree's. (This was discovered when a Spotless
check "passed" in a worktree while the CI pipeline failed on the same commit —
the local container was checking the primary checkout on `master`.)

The overrides here fix that by making `PROJECT_ROOT` the **current worktree** and
giving each worktree its **own** container name.

## Layout

```
~/scripts/worktree-env/
├── CLAUDE.md            # this file
├── e                    # the dispatcher (invoked as `e` from the shell)
└── <repo>/              # one directory per repo that needs an override
    ├── old/             # pristine copies of the repo scripts we reimplement,
    │   │                #   mirroring the repo's own directory layout
    │   ├── env.sh
    │   └── dev-environment/
    │       └── run.sh
    └── new/             # the replacements that actually get executed
        ├── env.sh
        └── run.sh
```

`<repo>` is matched by the **name of the repo's primary checkout directory**,
derived from git: `basename(dirname(git rev-parse --git-common-dir))`. For a
worktree of `~/repos/biofinder`, that resolves to `biofinder`, matching
`~/scripts/worktree-env/biofinder/`.

### `old/` — baselines for divergence detection

`old/` holds byte-for-byte copies of the repo scripts that `new/` reimplements,
laid out at the **same relative paths** they occupy in the repo
(`old/env.sh` ↔ `<repo>/env.sh`, `old/dev-environment/run.sh` ↔
`<repo>/dev-environment/run.sh`).

The **`e` dispatcher** (not `new/env.sh`) diffs every file under `old/` against
the live copy in the current worktree before it runs. If any differ (or have
gone missing), `e` prints a `[WARN]` block **before** running the command (or
going interactive) and **again after** it returns, then still runs using the
`new/` replacements. That warning is the signal that upstream changed its
scripts and the override may need to be refreshed — see "Updating" below. The
check is generic: it applies to any repo with an `old/` directory here, so a
`new/env.sh` never has to implement it.

### `new/` — the executed replacements

- `new/env.sh` — entry point. Determines `PROJECT_ROOT` from
  `git rev-parse --show-toplevel` (the current worktree), exports the same env
  vars the stock `env.sh` did, and hands off to the sibling `new/run.sh`. (The
  divergence check is handled generically by `e`, not here.)
- `new/run.sh` — a copy of the repo's `dev-environment/run.sh` with the **only**
  functional change being a per-worktree container name:
  `${PROJECT_NAME}-dev-environment-<worktree-slug>-<hash-of-PROJECT_ROOT>`.
  Keeping it otherwise identical keeps the divergence diff meaningful.

## The `e` command

`e` is a standalone script here (`~/scripts/worktree-env/e`), invoked via a thin
alias in `~/.bash_aliases`. It:

1. Identifies the repo from git.
2. If `~/scripts/worktree-env/<repo>/new/env.sh` exists → runs that override.
3. Otherwise → walks up from the current dir for the repo's own `env.sh` (the
   original behaviour), so repos without an override just work as before.
4. For override repos, runs the generic **divergence check** (`old/` vs the
   live worktree) and warns before and after running — never blocking.
5. Command mode (`e <cmd...>`) preserves the legacy wrapper: pipes output
   through `tee out.out` and, on success, runs `push_to_mobile.sh <cwd> done`.
   Interactive mode (`e` with no args) runs the launcher directly so the TTY is
   preserved (no `tee`, no notify).

## Adding an override for a new repo

1. `mkdir -p ~/scripts/worktree-env/<repo>/{old,new}`.
2. Copy the repo scripts you're reimplementing into `old/`, preserving their
   relative paths (mirror the repo layout).
3. Copy them into `new/` too, then apply your worktree-aware edits there. Keep
   edits minimal so the `old/` diff stays a useful "did upstream change?" signal.
4. `new/env.sh` must: resolve `PROJECT_ROOT` to the current worktree and invoke
   its worktree-aware `run.sh`. (The `old/` divergence check is automatic via
   `e` — you don't implement it per repo.)
5. `chmod +x` the `new/` scripts.

## Updating when a repo's scripts change

When you run `e` and see a `[WARN] ... has diverged` message:

1. Inspect the diff it prints (`diff old/<path> <worktree>/<path>`).
2. Port any relevant upstream change into `new/`.
3. Refresh the baseline: copy the repo's current file over the matching `old/`
   file so the warning clears.
