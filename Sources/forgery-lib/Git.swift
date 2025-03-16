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

public struct RepoStatus {
    public let isDirty: Bool
    public let hasUnpushedCommits: Bool
}

public func checkStatus(repoPath: String) throws -> RepoStatus {
    let fullRepoPath = (repoPath as NSString).expandingTildeInPath
    logger.info("Checking status of \(fullRepoPath)...")
    let git = Git(path: fullRepoPath)
    // Check for uncommitted changes
    let isDirty = try git.run(.status(short: true)).isEmpty == false

    // Check for unpushed commits
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

    return RepoStatus(isDirty: isDirty, hasUnpushedCommits: unpushedCommits)
}
