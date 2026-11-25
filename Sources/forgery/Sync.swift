import ArgumentParser
import Foundation
import OctoKit
import forgery_lib

struct Sync: AsyncParsableCommand {
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

    func run() async throws {
        if pushWIP {
            try await processWIPChanges()
        } else {
            let githubClient = GitHub(accessToken: accessToken)
            
            let user = try githubClient.authenticate()
            let userDir = "\(basePath)/\(user.login)"
            Task {
                do {
                    let remoteRepos = try githubClient.getRepos(ownedBy: user.login).map { $0 }
                    await githubClient.updateLocalReposUnder(path: userDir, remoteRepoList: remoteRepos, pushToForkRemotes: pushToForkRemotes, prune: prune, pullWithRebase: pullWithRebase, pushAfterRebase: pushAfterRebase, rebaseSubmodules: rebaseSubmodules)
                } catch {
                    logger.error("Error fetching repositories: \(error)")
                }
            }
        }
    }

    private func processWIPChanges() async throws {
        let report = try await scanRepositories(
            roots: try collectRoots(),
            options: ScanOptions(
                inspection: RepoInspectionOptions(fetch: false, collectDiffstat: false, pushWIPChanges: true)
            )
        )

        let wipRepos = report.repos.filter { $0.pushedWIP }
        if !wipRepos.isEmpty {
            print("\nRepositories with WIP changes pushed:")
            for repo in wipRepos {
                print("  ✓ \(repo.path)")
            }
        } else {
            print("\nNo repositories with uncommitted changes found.")
        }
    }

    private func collectRoots() throws -> [RepoRoot] {
        var roots = [RepoRoot]()

        if let organization = userTypes.organization {
            roots += try organizationRoots(organization)
        } else if let user = userTypes.user {
            roots += try userRoots(user)
        } else if userTypes.all {
            try forEachSubdirectory(of: "\(fullBasePath)/\(CommonPaths.userBasePathComponent)") {
                roots += try userRoots($0)
            }
            try forEachSubdirectory(of: "\(fullBasePath)/\(CommonPaths.orgBasePathComponent)") {
                roots += try organizationRoots($0)
            }
        } else if userTypes.allUsers {
            if userTypes.allOrgs {
                throw ForgeryError.Status.useAll
            }
            try forEachSubdirectory(of: "\(fullBasePath)/\(CommonPaths.userBasePathComponent)") {
                roots += try userRoots($0)
            }
        } else if userTypes.allOrgs {
            try forEachSubdirectory(of: "\(fullBasePath)/\(CommonPaths.orgBasePathComponent)") {
                roots += try organizationRoots($0)
            }
        } else {
            throw ForgeryError.Status.invalidOption
        }

        return roots
    }

    private func userRoots(_ username: String) throws -> [RepoRoot] {
        try UserPaths(basePath: basePath, username: username, repoTypes: repoTypes.resolved, createOnDisk: false).validRoots
    }

    private func organizationRoots(_ organization: String) throws -> [RepoRoot] {
        try CommonPaths(basePath: basePath, orgName: organization, repoTypes: repoTypes.resolved, createOnDisk: false).validRoots
    }

    private func forEachSubdirectory(of path: String, block: (String) throws -> Void) throws {
        guard FileManager.default.fileExists(atPath: path) else {
            throw ForgeryError.Status.pathDoesNotExist
        }
        for subdirectory in try FileManager.default.contentsOfDirectory(atPath: path).sorted() {
            try block(subdirectory)
        }
    }
}
