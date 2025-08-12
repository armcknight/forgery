import ArgumentParser
import Foundation
import OctoKit
import forgery_lib

struct Sync: ParsableCommand {
    @Argument(help: "The GitHub access token of the GitHub user whose repos should be synced.")
    var accessToken: String

    @Argument(help: "Location of the repos to sync.")
    var basePath: String

    @Flag(name: [.customShort("f"), .long], help: "After fast-forwarding any new commits from forks' remote upstreams, push the new commits to fork remotes.")
    var pushToForkRemotes: Bool = false

    @Flag(name: [.customShort("p"), .long], help: "If a local repository is no longer listed from the server, remove its local clone.")
    var prune: Bool = false

    @Flag(name: [.customShort("r"), .long], help: "Run `git pull --rebase` to rebase any local commits on top of the remote HEAD.")
    var pullWithRebase: Bool = false

    @Flag(name: [.customShort("a"), .long], help: "If `--pull-with-rebase` is provided, push HEAD to remote after rebasing any local commits on top of pulled remote commits.")
    var pushAfterRebase: Bool = false

    @Flag(name: [.customShort("s"), .long], help: "If development has occurred in a submodule, the changes are rebased onto any updated submodule commit hash that is pulled down as part of updating the superproject.")
    var rebaseSubmodules: Bool = false

    @Flag(name: .long, help: "Create WIP branches for repositories with uncommitted changes")
    var pushWIP = false

    @OptionGroup(title: "Repo types to work on")
    var repoTypes: RepoTypeOptions

    @OptionGroup(title: "The individual or sets of users/orgs whose repos should be checked")
    var userTypes: UserTypes

    var fullBasePath: String {
        (basePath as NSString).expandingTildeInPath
    }

    func run() throws {
        if pushWIP {
            try processWIPChanges()
        } else {
            let githubClient = GitHub(accessToken: accessToken)
            
            let user = try githubClient.authenticate()
            let userDir = "\(basePath)/\(user.login)"
            Task {
                do {
                    let remoteRepos = try githubClient.getRepos(ownedBy: user.login).map { $0 }
                    githubClient.updateLocalReposUnder(path: userDir, remoteRepoList: remoteRepos, pushToForkRemotes: pushToForkRemotes, prune: prune, pullWithRebase: pullWithRebase, pushAfterRebase: pushAfterRebase, rebaseSubmodules: rebaseSubmodules)
                } catch {
                    logger.error("Error fetching repositories: \(error)")
                }
            }
        }
    }

    private func processWIPChanges() throws {
        var repoSummaries = [RepoSummary]()

        if let organization = userTypes.organization {
            repoSummaries = try checkForOrganization(organization: organization)
        } else if let user = userTypes.user {
            repoSummaries = try checkForUsername(username: user)
        } else if userTypes.all {
            try iterateOverSubdirectories(path: "\(fullBasePath)/\(CommonPaths.userBasePathComponent)") { username in
                repoSummaries.append(contentsOf: try checkForUsername(username: username))
            }
            try iterateOverSubdirectories(path: "\(fullBasePath)/\(CommonPaths.orgBasePathComponent)") { organization in
                repoSummaries.append(contentsOf: try checkForOrganization(organization: organization))
            }
        } else if userTypes.allUsers {
            if userTypes.allOrgs {
                throw ForgeryError.Status.useAll
            }

            try iterateOverSubdirectories(path: "\(fullBasePath)/\(CommonPaths.userBasePathComponent)") { username in
                repoSummaries.append(contentsOf: try checkForUsername(username: username))
            }
        } else if userTypes.allOrgs {
            try iterateOverSubdirectories(path: "\(fullBasePath)/\(CommonPaths.orgBasePathComponent)") { organization in
                repoSummaries.append(contentsOf: try checkForOrganization(organization: organization))
            }
        } else {
            throw ForgeryError.Status.invalidOption
        }

        let wipRepos = repoSummaries.filter { $0.status.contains(.pushedWIP) }
        if !wipRepos.isEmpty {
            print("\nRepositories with WIP changes pushed:")
            for repo in wipRepos {
                print("  ✓ \(repo.path)")
            }
        } else {
            print("\nNo repositories with uncommitted changes found.")
        }
    }

    private func iterateOverSubdirectories(path: String, block: (String) throws -> Void) throws {
        guard FileManager.default.fileExists(atPath: path) else {
            throw ForgeryError.Status.pathDoesNotExist
        }

        for case let subdirectory in try FileManager.default.contentsOfDirectory(atPath: path) {
            try block(subdirectory)
        }
    }

    private func checkForUsername(username: String) throws -> [RepoSummary] {
        let userPaths = try UserPaths(basePath: basePath, username: username, repoTypes: repoTypes.resolved, createOnDisk: false)
        return try checkRepos(pathsToCheck: userPaths.validPaths)
    }

    private func checkForOrganization(organization: String) throws -> [RepoSummary] {
        let orgPaths = try CommonPaths(basePath: basePath, orgName: organization, repoTypes: repoTypes.resolved, createOnDisk: false)
        return try checkRepos(pathsToCheck: orgPaths.validPaths)
    }

    private func checkRepos(pathsToCheck: [String]) throws -> [RepoSummary] {
        var reposWithWork: [RepoSummary] = []
        let fileManager = FileManager.default
        for path in pathsToCheck {
            var isDirectory: ObjCBool = false
            let fullPath = (path as NSString).expandingTildeInPath
            guard fileManager.fileExists(atPath: fullPath, isDirectory: &isDirectory) else {
                logger.debug("Path does not exist: \(path)")
                continue
            }
            guard isDirectory.boolValue else {
                logger.warning("Path is not a directory: \(path)")
                continue
            }

            logger.debug("Checking repos in \(fullPath)")
            for case let repoPath in try fileManager.contentsOfDirectory(atPath: fullPath) {
                logger.debug("Checking repo: \(repoPath)")
                let fullRepoPath = "\(fullPath)/\(repoPath)"
                guard let type = try fileManager.attributesOfItem(atPath: fullRepoPath)[.type] as? FileAttributeType, type == .typeDirectory else {
                    continue
                }

                let gitDirURL = (fullRepoPath as NSString).appendingPathComponent(".git")
                guard fileManager.fileExists(atPath: gitDirURL) else {
                    logger.warning("Directory does not contain a git repo: \(fullRepoPath)")
                    continue
                }

                let repoSummary = try summarizeStatus(repoPath: fullRepoPath, pushWIPChanges: true)
                if repoSummary.status.contains(.pushedWIP) {
                    reposWithWork.append(repoSummary)
                }
            }
        }
        return reposWithWork
    }
}
