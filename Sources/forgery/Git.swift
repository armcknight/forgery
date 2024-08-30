import Foundation
import GitKit

func cloneRepo(repoName: String, sshURL: String, clonePath: String) -> Bool {
    let repoPath = "\(clonePath)/\(repoName)"
    if !FileManager.default.fileExists(atPath: repoPath) {
        logger.info("Cloning \(sshURL)...")
        var git = Git(path: clonePath)
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
