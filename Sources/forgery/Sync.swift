import ArgumentParser
import Foundation
import OctoKit
import forgery_lib

struct Sync: ParsableCommand {
    @Argument(help: "The GitHub access token of the GitHub user whose repos should be synced.")
    var accessToken: String

    @Argument(help: "Location of the repos to sync.")
    var basePath: String

    @Flag(name: .shortAndLong, help: "After fast-forwarding any new commits from forks' remote upstreams, push the new commits to fork remotes.")
    var pushToForkRemotes: Bool = false

    @Flag(name: .shortAndLong, help: "If a local repository is no longer listed from the server, remove its local clone.")
    var prune: Bool = false

    @Flag(name: .shortAndLong, help: "Run `git pull --rebase` to rebase any local commits on top of the remote HEAD.")
    var pullWithRebase: Bool = false

    @Flag(name: .shortAndLong, help: "If `--pull-with-rebase` is provided, push HEAD to remote after rebasing any local commits on top of pulled remote commits.")
    var pushAfterRebase: Bool = false

    @Flag(name: .shortAndLong, help: "If development has occurred in a submodule, the changes are rebased onto any updated submodule commit hash that is pulled down as part of updating the superproject.")
    var rebaseSubmodules: Bool = false

    func run() throws {
        let githubClient = GitHub(accessToken: accessToken)
        
        let user = try githubClient.authenticate()
        
        guard let username = user.login else {
            logger.error("No user login info returned after authenticating.")
            return
        }
        
        let userDir = "\(basePath)/\(user.login!)"
        Task {
            do {
                let remoteRepos = try githubClient.getRepos(ownedBy: username).map { $0 }
                githubClient.updateLocalReposUnder(path: userDir, remoteRepoList: remoteRepos, pushToForkRemotes: pushToForkRemotes, prune: prune, pullWithRebase: pullWithRebase, pushAfterRebase: pushAfterRebase, rebaseSubmodules: rebaseSubmodules)
            } catch {
                logger.error("Error fetching repositories: \(error)")
            }
        }
    }
}
