# forgery

Automatically clone and sync repositories from a forge such as GitHub to a macOS machine.

## Getting started

- Create the necessary access tokens.
- Run `swift run forgery -h`.

### Access tokens

There are a couple of options for access tokens. You can create a classic token that can be used to access repos for a user or organization. Or, create separate fine-grained access tokens for a user and an organization, since the same fine-grained tokens exist per entity.

> For organization access, you must go to your organization settings and allow access via user tokens. Then, follow the same steps below to create tokens.

#### Fine grained tokens 

Create an access token in GitHub's developer settings for "all repositories" with the following permissions set to read-only:
    - repository 
        - metadata
    - account
        - starring
        
#### Classic tokens

Select the following scopes for all functionality, or pick and choose:
- repo::public_repo
- admin:org:::read:org
- gist
- user::read:user

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

### Features & Enhancements

- [ ] add verbose mode for debug logging
- reporting
    - [ ] generate a pretty report to display at the end of runs
        - [ ] commit to a repository so diffs between reports can be used to more succinctly monitor changes
    - [ ] collect and print errors instead of failing out of the script
- [ ] add option to create a cron job from the current invocation (take a cron schedule as parameter?)
- new command ideas
    - [x] `clone`
        - [x] add option to `clone` to avoid pulling down any repo that also belongs to an organization, if not running with `--organization`; the default behavior does clone those, and if organization is used afterwards, there would be multiple copies of the same repo
        - enhancements for cloning org repos
            - [ ] allow listing multiple organizations
            - [ ] option to `clone` all repos of all organizations followed by the authenticated user
        - [ ] add option `--no-archives` to avoid cloning archived repos (not sure if gists can be archived-check that out)
        - [ ] clone/sync other types of repos
            - [ ] watched/subscribed repos
        - [ ] filter cloning by only including or excluding tag/topic
    - [ ] `fork` 
        - [ ] fork all repos/gists in a category (like those belonging to followed org or user, or an org that the authenticated user belongs to, starred repos, etc.) and make them forks owned by the authenticated user
        - [ ] fork a list of repos/gists as specified in arg list
    - [ ] `sync`
        - [x] pull with rebase to replay current local topic branch commits onto latest upstream default branch, stashing uncommitted changes
        - [x] forks fetch/fast-forward from `fork` remote first, then pull with rebase from `upstream`, then optionally push that back up to `fork` 
            - [ ] how to handle conflicts?
        - [ ] handle submodules
        - [ ] pretty print a summary at the end
        - [ ] move repos/gists between public/private directories in case those permissions are switched by the upstream owner
        - [ ] move repos that have been transferred to new owners
        - [ ] check set of local and remote branches against each other
    - [x] `status`
        - [x] `--wip` option: commit all dirty index changes to a new branch called e.g. `forgery-wip` and have a way to check any locals/remotes for existence of such branches 
            - [ ] this should actually go under the `sync` command
            - [ ] make branch name customizable
        - [ ] handle submodules
        - [ ] options to fast-forward or pull-rebase new upstream commits
        - [ ] `--fork-dirty-starred` option: for a starred repo with a dirtied index or unpushed commits, create a fork if one doesn't already exist under the user, push it to that instead, move the local modified clone from star to fork path, and then reclone fresh starred version
        - [ ] print commit ranges that can be copied to run `git diff <sha>..<sha>` commands and print URLs to report that would allow to click to view diffs in a web browser
- [ ] handle private forks
- submodules
    - [x] update submodules recursively, with an option to rebase them in `sync`
    - [ ] check out branches `fork_main` and `upstream_main` and delete local `main` branch (or whatever the default branch name is)
    - [ ] check if submodules are forks, and treat them thusly (check github api `repo.is_fork`)
- [ ] support more VCS options
    - [ ] `hg`
    - [ ] `svn`
    - [ ] `fossil`
- add more forges
    - [ ] gitlab
    - [ ] codeberg
    - [ ] sourceforge
    - [ ] sourcehut
    - [ ] set a tag on repos/gists to indicate which forge they are from
- [ ] add a search function that progressively searches by the following tiers:
    - repo name
    - file name
    - source code
- [ ] add dual options for all the `--no-...` flags that are `--only-...` (so, `--only-repos` to complement `--no-repos`)

### Bugs

- [ ] Doesn't currently fetch private user repositories. May also not fetch private org repos. Need to look into how the two different API endpoints are called (authenticated user /repos returning private repos in the listing, vs nonauthenticated /<user>/repos only returning public repos. See `synchronouslyFetchRepositories`.) This may also involve tweaking the necessary auth token scopes described in the readme above to allow full repo access for classic, and some unknown changes to fine-grained tokens.

## Alternatives

- https://github.com/jasonraimondi/deno-mirror-to-gitea
