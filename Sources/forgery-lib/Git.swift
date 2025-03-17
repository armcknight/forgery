import Foundation
import GitKit
import ShellKit

/// Set default branch to pull from upstream remote but push to fork remote
func setDefaultForkBranchRemotes(_ git: Git) throws {
    let defaultBranch = try git.run(.revParse(abbrevRef: "fork/HEAD")).replacingOccurrences(of: "refs/remotes/fork/", with: "")
    try git.run(.config(name: "branch.\(defaultBranch).remote", value: "upstream"))
    try git.run(.config(name: "branch.\(defaultBranch).pushRemote", value: "fork"))
}

/// Clones a repo and then pulls down any submodules it may have.
func cloneRepo(repoName: String, sshURL: String, cloneRoot: String) throws {
    let escapedRepoName = repoName.replacingOccurrences(of: " ", with: "\\ ")
    let repoPath = ("\(cloneRoot)/\(escapedRepoName)" as NSString).expandingTildeInPath
    guard !FileManager.default.fileExists(atPath: repoPath) else {
        throw ForgeryError.Clone.Repo.alreadyCloned
    }
    
    logger.info("Cloning \(sshURL) into \(escapedRepoName)...")
    var git = Git(path: cloneRoot)
    try git.run(.clone(url: sshURL, dirName: escapedRepoName))
    if FileManager.default.fileExists(atPath: "\(repoPath)/.gitmodules") {
        git = Git(path: repoPath)
        try git.run(.submoduleUpdate(init: true, recursive: true))
    }
}

func remoteRepoExists(repoSSHURL: String) -> Bool {
    do {
        try Git().run(.lsRemote(url: repoSSHURL, limitToHeads: true))
        return true
    } catch {
        return false
    }
}

public struct RepoState: OptionSet {
    public var rawValue: UInt
    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    public static let clean = RepoState(rawValue: 1 << 0)
    public static let dirtyIndex = RepoState(rawValue: 1 << 1)
    public static let pushedWIP = RepoState(rawValue: 1 << 2)
    public static let unpushedBranches = RepoState(rawValue: 1 << 3)

    public var needsReport: Bool {
        contains(.dirtyIndex) || contains(.unpushedBranches) || contains(.unpushedBranches)
    }
}

extension RepoState: CustomStringConvertible {
    public var description: String {
        var status = ""
        if contains(.pushedWIP) {
            status += "W"
        } else if contains(.dirtyIndex) {
            status += "M"
        }
        if contains(.unpushedBranches) {
            status += "P"
        }
        return status
    }
}

public func checkWorkingIndex(repoPath: String, pushWIPChanges: Bool) throws -> RepoState {
    let fullRepoPath = (repoPath as NSString).expandingTildeInPath
    logger.info("Checking working index status of \(fullRepoPath)...")
    let git = Git(path: fullRepoPath)

    var wipState = RepoState.clean
    let clean = try git.run(.status(short: true)).isEmpty
    if !clean {
        wipState = .dirtyIndex
    }

    if pushWIPChanges && !clean {
        try saveWIPChanges(repoPath: fullRepoPath)
        wipState = .pushedWIP
    }

    return wipState
}

public func checkUnpushedCommits(repoPath: String) throws -> Bool {
    let fullRepoPath = (repoPath as NSString).expandingTildeInPath
    logger.info("Checking for unpushed commits in \(fullRepoPath)...")
    let git = Git(path: fullRepoPath)

    var unpushedCommits: Bool = false
    let dispatchGroup = DispatchGroup()
    var forgeryError: ForgeryError.Status?

    dispatchGroup.enter()
    git.run(.log(options: ["--oneline"], revisions: "@{u}..")) { result, error in
        defer { dispatchGroup.leave() }

        guard let shellKitError = error as? Shell.Error else {
            unpushedCommits = !result!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return
        }

        switch shellKitError {
        case .outputData:
            forgeryError = ForgeryError.Status.gitLogError
        case .generic(let code, _):
            if code == 128 {
                unpushedCommits = false
            } else {
                forgeryError = ForgeryError.Status.unexpectedGitLogStatus
            }
        }
    }
    dispatchGroup.wait()

    if let forgeryError = forgeryError {
        throw forgeryError
    }

    return unpushedCommits
}

public func checkStatus(repoPath: String, pushWIPChanges: Bool) throws -> RepoState {
    var state = try checkWorkingIndex(repoPath: repoPath, pushWIPChanges: pushWIPChanges)
    if try checkUnpushedCommits(repoPath: repoPath) {
        state.formUnion(.unpushedBranches)
    }

    return state
}

func saveWIPChanges(repoPath: String) throws {
    let git = Git(path: repoPath)

    let branchName = "forgery-wip"
    try git.run(.checkout(branch: branchName, create: true))
    try git.run(.addAll)

    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    let timestamp = dateFormatter.string(from: Date())
    let commitMessage = "wip on \(timestamp)"
    try git.run(.commit(message: commitMessage))

    // TODO: if this is a fork, push to remote named "fork" instead of "origin"
    try git.run(.push())

    print("  ✓ Saved WIP changes to branch '\(branchName)'")
}
