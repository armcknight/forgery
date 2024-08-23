# forgery

Automatically clone and sync repositories from a forge such as GitHub to a macOS machine.

## Getting started

- Create an access token with repo scope from GitHub.
- Run `make init`.
- Run `./forge -h`.

## Commands

###  `clone`

By default, pulls a listing of all of your public, private, starred and forked repos and gists (which are backed by git repos), and associated repo wikis (which are also git repos), and clones them locally on their default branch.

Can optionally be used for an organization instead of a user account.

Each repo's directory will be tagged with the language and topics from the repo (using [`tag`](https://github.com/jdberry/tag)).

Forks get their `origin` remote renamed to `fork` (also set as `branch.$(default).pushRemote`) and get a second remote added named `upstream` that points to the original repo that was forked (which is set as `branch.$(default).remote` for default pull source).

It builds a directory structure like so:
```
/path/to/.../code/
├── organization
│   └── apple
│       └── repos
│           ├── forked
│           │   └── LLVM
│           │       └── LLVM
│           ├── private
│           │   └── applesPrivateCode
│           └── public
│               └── swift
└── user
    └── armcknight
        ├── repos
        │   ├── forked
        │   │   └── apple
        │   │       └── swift
        │   ├── private
        │   │   └── myPrivateCode
        │   ├── public
        │   │   ├── AdventOfCode
        │   │   ├── armcknight
        │   │   └── armcknight.wiki
        │   └── starred
        │       ├── juanfont
        │       │   └── headscale
        │       └── sindresorhus
        │           └── awesome
        └── gists (...same structure)
```

### `sync`

Go through cloned repos and update them by doing things like fetching/fast-forwarding commits (and optionally for forks, pushing commits from `upstream` to `fork`), updating topic/language tags, and pruning local repos that no longer apply from remote, like unstarred repos.

## TODO

- [ ] generate a pretty report to display at the end of runs
- [ ] collect and print errors instead of failing out of the script
- [x] pull with rebase to replay current local topic branch commits onto latest upstream default branch, stashing uncommitted changes
- [x] forks fetch/fast-forward from `fork` remote first, then pull with rebase from `upstream`, then optionally push that back up to `fork` (how to handle conflicts?)
- [ ] move repos/gists between public/private directories in case those permissions are switched by the upstream owner
- [ ] move repos that have been transferred to new owners
- [ ] add option to create a cron job from the current invocation
- [ ] allow listing multiple organizations
- [x] update submodules recursivey, with an option to rebase them in `sync`
- [x] add a `status` command to report current status of all managed repos
- [x] add option to `clone` to avoid pulling down any repo that also belongs to an organization, if not running with `--organization`; the default behavior does clone those, and if organization is used afterwards, there would be multiple copies of the same repo
- [ ] support more VCS options
    - [ ] `hg`
    - [ ] `svn`
    - [ ] `fossil`
- [ ] allow providing a comma-delimited list to the `--organization` option
- [ ] add a search function that progressively searches by the following tiers:
    - repo name
    - file name
    - source code
- [ ] add option `--no-archives` to avoid cloning archived repos (not sure if gists can be archived-check that out)
- [ ] add dual options for all the `--no-...` flags that are `--only-...` (so, `--only-repos` to complement `--no-repos`)

## Alternatives

- https://github.com/jasonraimondi/deno-mirror-to-gitea
