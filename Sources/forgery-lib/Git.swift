import Foundation
import GitKit

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
