import Foundation
import GitKit

/// Set default branch to pull from upstream remote but push to fork remote
func setDefaultForkBranchRemotes(_ git: Git) throws {
    let defaultBranch = try git.run(.revParse(abbrevRef: "fork/HEAD")).replacingOccurrences(of: "refs/remotes/fork/", with: "")
    try git.run(.config(name: "branch.\(defaultBranch).remote", value: "upstream"))
    try git.run(.config(name: "branch.\(defaultBranch).pushRemote", value: "fork"))
}

/// Clones a repo and then pulls down any submodules it may have.
func cloneRepo(repoName: String, sshURL: String, cloneRoot: String) -> Bool {
    let repoPath = "\(cloneRoot)/\(repoName)"
    if !FileManager.default.fileExists(atPath: repoPath) {
        logger.info("Cloning \(sshURL)...")
        var git = Git(path: cloneRoot)
        do {
            try git.run(.clone(url: sshURL))
        } catch {
            logger.error("Failed to clone \(sshURL): \(error)")
            return false
        }
        if FileManager.default.fileExists(atPath: "\(repoPath)/.gitmodules") {
            git = Git(path: repoPath)
            do {
                try git.run(.submoduleUpdate(init: true, recursive: true))
            } catch {
                logger.error("Failed to retrieve submodules under \(sshURL): \(error)")
                return false
            }
        }
    } else {
        logger.info("\(sshURL) already cloned")
        return false
    }
    
    return true
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
