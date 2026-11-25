import Foundation
import GitKit

/// Set default branch to pull from upstream remote but push to fork remote
func setDefaultForkBranchRemotes(_ git: Git) async throws {
    let defaultBranch = try await git.run(.revParse(abbrevRef: true, revision: "fork/HEAD")).replacingOccurrences(of: "refs/remotes/fork/", with: "")
    try await git.run(.writeConfig(name: "branch.\(defaultBranch).remote", value: "upstream"))
    try await git.run(.writeConfig(name: "branch.\(defaultBranch).pushRemote", value: "fork"))
}

/// Clones a repo and then pulls down any submodules it may have.
func cloneRepo(repoName: String, sshURL: String, cloneRoot: String) async throws {
    let repoPath = ("\(cloneRoot)/\(repoName)" as NSString).expandingTildeInPath
    guard !FileManager.default.fileExists(atPath: repoPath) else {
        throw ForgeryError.Clone.Repo.alreadyCloned
    }

    logger.info("Cloning \(sshURL) into \(repoName)...")
    var git = Git(path: cloneRoot)
    try await git.run(.clone(url: sshURL, dirName: repoName))
    if FileManager.default.fileExists(atPath: "\(repoPath)/.gitmodules") {
        git = Git(path: repoPath)
        try await git.run(.submoduleUpdate(init: true, recursive: true))
    }
}

func remoteRepoExists(repoSSHURL: String) async -> Bool {
    do {
        try await Git().run(.lsRemote(url: repoSSHURL, limitToHeads: true))
        return true
    } catch {
        return false
    }
}

// MARK: - Inspecting a repo

/**
 * What to collect while inspecting a repo, and whether to touch the network or the working tree
 * on the way.
 */
public struct RepoInspectionOptions: Sendable {
    /// Fetch from all remotes, with `--prune`, before reading any state.
    public var fetch: Bool

    /// Collect `git status` output for repos with a dirty tree, so the renderers do not have to
    /// run git themselves.
    public var collectDiffstat: Bool

    /// Commit a dirty tree to a WIP branch and push it. Used by `sync`, never by `status`.
    public var pushWIPChanges: Bool

    public init(fetch: Bool = false, collectDiffstat: Bool = true, pushWIPChanges: Bool = false) {
        self.fetch = fetch
        self.collectDiffstat = collectDiffstat
        self.pushWIPChanges = pushWIPChanges
    }
}

/**
 * Reads the full state of one repo.
 *
 * Does not throw when git fails on the network. A fetch that does not complete is recorded on the
 * summary as `fetchFailed`, so one unreachable remote cannot stop a scan of a large tree.
 */
public func inspectRepo(
    at path: String,
    category: RepoCategory,
    owner: String? = nil,
    options: RepoInspectionOptions = RepoInspectionOptions()
) async throws -> RepoSummary {
    let fullPath = (path as NSString).expandingTildeInPath
    logger.debug("Inspecting \(fullPath)...")

    var fetchFailed = false
    if options.fetch {
        do {
            try await fetchAllRemotes(repoPath: fullPath)
        } catch {
            logger.warning("Fetch failed for \(fullPath): \(error)")
            fetchFailed = true
        }
    }

    var workingTree = try await readWorkingTreeState(repoPath: fullPath)

    var pushedWIP = false
    if options.pushWIPChanges, workingTree.isDirty {
        try await saveWIPChanges(repoPath: fullPath)
        pushedWIP = true
        // The tree is clean once the WIP branch is committed and pushed.
        workingTree = WorkingTreeState(stashes: workingTree.stashes)
    }

    let branches = try await readBranches(repoPath: fullPath)
    let detachedAt = try await readDetachedHead(repoPath: fullPath)

    var diffstat: String? = nil
    if options.collectDiffstat, workingTree.isDirty {
        // The short form, because the long form repeats the branch state already reported above
        // and buries the changed files in advice text.
        diffstat = try? await Git(path: fullPath).run(.status(short: true))
    }

    return RepoSummary(
        path: fullPath,
        category: category,
        owner: owner,
        name: (fullPath as NSString).lastPathComponent,
        workingTree: workingTree,
        branches: branches,
        detachedAt: detachedAt,
        fetchFailed: fetchFailed,
        pushedWIP: pushedWIP,
        diffstat: diffstat
    )
}

/**
 * Fetches every remote and prunes remote-tracking refs whose branches are gone.
 *
 * The prune is what lets `readBranches` tell a deleted upstream from a live one.
 */
public func fetchAllRemotes(repoPath: String) async throws {
    let git = Git(path: (repoPath as NSString).expandingTildeInPath)
    try await git.run(.raw("fetch --all --prune --quiet"))
}

/**
 * Counts staged, unstaged and untracked files, and entries on the stash stack.
 */
public func readWorkingTreeState(repoPath: String) async throws -> WorkingTreeState {
    let git = Git(path: (repoPath as NSString).expandingTildeInPath)

    var staged = 0
    var unstaged = 0
    var untracked = 0

    let porcelain = try await git.run(.raw("status --porcelain"))
    for line in porcelain.split(separator: "\n") {
        guard line.count >= 2 else { continue }
        let index = line[line.startIndex]
        let worktree = line[line.index(after: line.startIndex)]

        if index == "?" && worktree == "?" {
            untracked += 1
            continue
        }
        if index != " " { staged += 1 }
        if worktree != " " { unstaged += 1 }
    }

    // A repo with no stash ref at all still exits zero here, with no output.
    let stashOutput = (try? await git.run(.raw("stash list"))) ?? ""
    let stashes = stashOutput.isEmpty ? 0 : stashOutput.split(separator: "\n").count

    return WorkingTreeState(staged: staged, unstaged: unstaged, untracked: untracked, stashes: stashes)
}

/**
 * Reads every local branch and how it compares to its upstream.
 *
 * Reads `refs/heads` through `for-each-ref` rather than parsing `git branch`. Parsing `git branch`
 * gives lines that are not branches at all: a detached HEAD prints as
 * `* (HEAD detached at 1234abc)`, and a branch checked out in another worktree is marked with a
 * `+ ` prefix rather than `* `. Both used to become branch names, fail the upstream lookup, and be
 * reported as local-only.
 */
public func readBranches(repoPath: String) async throws -> [BranchInfo] {
    let git = Git(path: (repoPath as NSString).expandingTildeInPath)

    let separator = "\u{1F}"
    let format = ["%(refname:short)", "%(upstream:short)", "%(HEAD)", "%(worktreepath)"]
        .joined(separator: separator)
    let output = try await git.run(.raw("for-each-ref --format='\(format)' refs/heads"))

    var branches = [BranchInfo]()
    for line in output.split(separator: "\n") {
        let fields = line.components(separatedBy: separator)
        guard fields.count >= 4, !fields[0].isEmpty else { continue }

        let name = fields[0]
        let upstream = fields[1].isEmpty ? nil : fields[1]
        let isCurrent = fields[2] == "*"
        // A branch reports a worktree path even when that worktree is the one being scanned, so
        // "elsewhere" means it has a worktree and it is not the branch HEAD points at here.
        let isCheckedOutElsewhere = !fields[3].isEmpty && !isCurrent

        var ahead = 0
        var behind = 0
        var upstreamGone = false

        if let upstream {
            do {
                let counts = try await git.run(
                    .raw("rev-list --left-right --count \(shellQuoted("\(name)...\(upstream)"))")
                )
                // Raw integers separated by a tab, so this does not depend on the locale the way
                // `%(upstream:track)` does.
                let parts = counts.split(whereSeparator: { $0 == "\t" || $0 == " " })
                ahead = parts.count > 0 ? Int(parts[0]) ?? 0 : 0
                behind = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
            } catch {
                // An upstream is configured but git cannot resolve it, so the remote branch is gone.
                logger.debug("Upstream '\(upstream)' of branch '\(name)' cannot be resolved: \(error)")
                upstreamGone = true
            }
        }

        branches.append(BranchInfo(
            name: name,
            isCurrent: isCurrent,
            isCheckedOutElsewhere: isCheckedOutElsewhere,
            upstream: upstream,
            upstreamGone: upstreamGone,
            ahead: ahead,
            behind: behind
        ))
    }

    return branches
}

/**
 * The short commit HEAD points at, when HEAD is not on a branch. Nil when HEAD is on a branch.
 */
public func readDetachedHead(repoPath: String) async throws -> String? {
    let git = Git(path: (repoPath as NSString).expandingTildeInPath)
    // Exits non-zero exactly when HEAD is not a symbolic ref.
    guard (try? await git.run(.raw("symbolic-ref -q HEAD"))) == nil else { return nil }
    return try? await git.run(.raw("rev-parse --short HEAD"))
}

func saveWIPChanges(repoPath: String) async throws {
    let git = Git(path: repoPath)

    let branchName = "forgery-wip"
    try await git.run(.checkout(branch: branchName, create: true))
    try await git.run(.addAll)

    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    let timestamp = dateFormatter.string(from: Date())
    let commitMessage = "wip on \(timestamp)"
    try await git.run(.commit(message: commitMessage))

    // TODO: if this is a fork, push to remote named "fork" instead of "origin"
    try await git.run(.push())

    logger.info("Saved WIP changes in \(repoPath) to branch '\(branchName)'")
}

/// Wraps a string so `/bin/sh` passes it to git unchanged.
func shellQuoted(_ string: String) -> String {
    "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
}
