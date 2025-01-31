import Foundation
import GitKit

/// Set default branch to pull from upstream remote but push to fork remote
func setDefaultForkBranchRemotes(_ git: Git) throws {
    let defaultBranch = try git.run(.revParse(abbrevRef: "fork/HEAD")).replacingOccurrences(of: "refs/remotes/fork/", with: "")
    try git.run(.config(name: "branch.\(defaultBranch).remote", value: "upstream"))
    try git.run(.config(name: "branch.\(defaultBranch).pushRemote", value: "fork"))
}

enum ForgeryError {
    enum Clone {
        enum Repo: Error {
            case alreadyCloned
            case noSSHURL
            case couldNotFetchRepo
            case noOwnerLogin
            case noName
            case noForkParent
            case noForkParentLogin
            case noForkParentSSHURL
        }
        
        enum Gist: Error {
            case noPullURL
            case noTitle
            case noForkOwnerLogin
            case noForkParent
            case noForkParentPullURL
            case couldNotFetchForkParent
            case noGistAccessInfo
            case noID
        }
    }
}

/// Clones a repo and then pulls down any submodules it may have.
func cloneRepo(repoName: String, sshURL: String, cloneRoot: String) throws {
    let repoPath = "\(cloneRoot)/\(repoName)"
    guard !FileManager.default.fileExists(atPath: repoPath) else {
        throw ForgeryError.Clone.Repo.alreadyCloned
    }
    
    logger.info("Cloning \(sshURL)...")
    var git = Git(path: cloneRoot)
    try git.run(.clone(url: sshURL))
    if FileManager.default.fileExists(atPath: "\(repoPath)/.gitmodules") {
        git = Git(path: repoPath)
        try git.run(.submoduleUpdate(init: true, recursive: true))
    }
}

func remoteRepoExists(repoSSHURL: String) -> Bool {
    let task = Process()
    task.launchPath = "/usr/bin/git"
    task.arguments = ["ls-remote", "-h", repoSSHURL]
    task.standardOutput = Pipe()
    task.standardError = Pipe()

    task.launch()
    task.waitUntilExit()

    return task.terminationStatus == 0
}
