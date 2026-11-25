# `status` follow-up work

Work that the `status` rework left open. The rework is commit `8c86114`,
`feat(status): Rework reporting with fetch, tracking counts, and HTML`.

At that commit the build is clean with no warnings, and all 58 tests pass.

Each item below gives the fault, where to find it, and a way to correct it.
Items are in the order of their importance.

---

## 1. `status` cannot see work in a linked worktree

**Priority: high. This is a defect, not a missing function.**

### The fault

`status` runs `git status` only in the main worktree of a repo. A linked worktree has
its own working tree, and `git status` does not read it. So uncommitted work in a
linked worktree is invisible, and the repo prints as clean.

This is a silent false clean. It is the same class of fault that the rework removed
everywhere else, so it does not belong in the command.

### How to see it

```sh
# make a repo with a remote, then add a worktree outside the scanned tree
git -C <repo> worktree add /tmp/outside-wt feature
echo dirty > /tmp/outside-wt/new.txt

forgery status <base> --user <login> --all-branches --all-repos
```

The repo prints with the `[✓]` tag, although `/tmp/outside-wt` holds an untracked
file:

```
[✓] …/repos/public/main-repo
      feature  ✓ (worktree)
    * main     ✓
```

### Two smaller parts of the same gap

- **The worktree path is never shown.** `BranchInfo.isCheckedOutElsewhere` records
  that a branch has a worktree, but it drops the path. The reader learns a branch is
  elsewhere, but not where to go. See `Sources/forgery-lib/Git.swift`, in
  `readBranches`, where `%(worktreepath)` is read and then discarded.
- **A worktree inside a scanned root counts as a second repo.** `refs/heads` is shared
  between all worktrees of one repo, so both directories list the same branches. The
  rollup counts the repo twice, and `--fetch` contacts the same remote twice. Nothing
  shows that the two directories are one repo. A linked worktree holds a `.git` file
  and not a `.git` directory, and `isGitRepository` in
  `Sources/forgery-lib/StatusScanner.swift` accepts both, which is why it is found.

### How to correct it

Use `git worktree list --porcelain`. One call for each repo gives every worktree and
its path. With that you can:

1. Read the working tree state of each worktree, so dirty work stops hiding.
2. Show the path of a branch that is checked out elsewhere.
3. Group the worktrees below their main repo, and scan the set one time only.

`RepoSummary` will need a field for the worktrees, and `renderRepo` in
`Sources/forgery-lib/TerminalReportRenderer.swift` will need to print them.

---

## 2. `sync` uses the shared scanner but not the report

**Priority: medium.**

`sync` calls `scanRepositories`, but it still prints its own three lines. See
`Sources/forgery/Sync.swift:70-75`. It never calls `renderTerminalReport`, so it gets
no rollups, no legend and no HTML.

Related, and easy to miss: `W` is in `RepoStatusFlags.displayOrder`
(`Sources/forgery-lib/RepoStatus.swift:174`) but it is **not** in
`RepoStatusFlags.legend`. If `sync` ever did render a report, `W` would print with no
explanation. The two lists must agree, and today a person must keep them in agreement.

### How to correct it

Give `sync` the renderers. Then add `W` to `legend`, or better, make one list the
source of both, so they cannot disagree.

---

## 3. The command layer has no tests

**Priority: medium.**

No test target depends on the `forgery` executable target. See `Package.swift`:
`forgeryTests` depends on `forgery-lib`, `ForgeryTestSupport`, `GitKit` and
`ArgumentParser`, but not on `forgery`.

So this code is proved only by runs made by hand:

- `Status.validate()` — the rule that `--open` needs `--html`, and the limits on
  `--jobs` and `--top`
- `Status.collectRoots()` — the `--user`, `--organization`, `--all`, `--all-users` and
  `--all-orgs` branches
- `Status.writeHTMLReport()` — the file write, and the call to `/usr/bin/open`

The library below this layer has 58 tests. The layer itself has none.

### How to correct it

Move the testable parts into `forgery-lib`, or let `forgeryTests` depend on the
executable target. An executable target can be a dependency of a test target, as long
as the platform permits it.

---

## 4. The `Codable` conformances do nothing

**Priority: low. Remove it or finish it.**

`BranchInfo`, `WorkingTreeState` and `RepoCategory` are `Codable`
(`Sources/forgery-lib/RepoStatus.swift`). But `RepoSummary` is not, and the package
holds no `JSONEncoder`. So no report can be encoded, and the conformances serve
nothing.

### How to correct it

Either add a `--json` option, and make `RepoSummary`, `StatusReport` and
`RepoStatusFlags` encodable with it, or delete the conformances. `RepoStatusFlags` is
an `OptionSet` of `UInt` and `RepoState` is an enum, so both need their own encoding.

---

## 5. Open items that were never requested

**Priority: low.**

- **Submodules.** A submodule's own branch state is not reported. The README tracks
  this.
- **Exit code.** `status` always exits 0. The README has an idea for a cron job, which
  needs an exit code to be of use.
- **`--json`.** See item 4.
- **Wikis.** `cloneWiki` puts `<repo>.wiki` beside the repo, so `status` lists it as an
  ordinary repo. `clone` has `--no-wikis`; `status` has no equal filter.
- **`--quiet` with `--html` prints nothing**, not even the path of the file it wrote.
  See `Status.writeHTMLReport`.
- **Tilde expansion is not consistent.** `Status.userRoots` passes the raw
  `baseOptions.basePath`, but `Status.forEachSubdirectory` uses `fullBasePath`. It
  works, because the scanner expands each root, but the two should agree.

---

## How to check your work

```sh
swift build          # must be clean, with no warnings
swift test           # 58 tests at commit 8c86114
```

For a test against real repos:

```sh
forgery status ~/Code --user <login> --only-public-repos
forgery status ~/Code --user <login> --fetch --jobs 16
forgery status ~/Code --user <login> --all-branches --all-repos
forgery status ~/Code --user <login> --html ~/status.html --open
```

Build a bare remote for any test of ahead, behind, diverged or gone-upstream states.
`Tests/ForgeryTestSupport/GitFixtures.swift` has the builders:
`makeRepoWithUpstream`, `advanceRemote`, `deleteRemoteBranch` and `addWorktree`.
