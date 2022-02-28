# forgery

Automatically clone and sync repositories from a forge such as GitHub to a macOS machine.

## Getting started

- Create an access token with repo scope from GitHub.
- Run `make init`.
- Run `./forge -h`.

## Commands

###  `clone`

By default, pulls a listing of all of your public, private, starred and forked repos and gists (which are backed by git repos), and associated repo wikis (which are also git repos), and clones them all locally.

Can optionally be used for an organization instead of a user account.

Each repo's directory will be tagged with the language and topics from the repo (using [`tag`](https://github.com/jdberry/tag)).

Forks get their `origin` remote renamed to `fork` and get a second remote added named `upstream` that points to the original repo that was forked.

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

### `sync` (*WIP*)

Go through cloned repos and update them by doing things like fetching/fast-forwarding commits (and optionally for forks, pushing commits from `upstream` to `fork`), updating topic/language tags, and pruning local repos that no longer apply from remote, like unstarred repos.

## TODO

- pull with rebase to replay current local commits onto latest upstream, stashing uncommitted changes
- move repos/gists between public/private directories in case those permissions are switched by the upstream owner
- collect and print errors instread of failing out of the script