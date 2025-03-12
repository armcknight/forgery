import ArgumentParser
import Foundation
import OctoKit
import forgery_lib
import GitKit
import ShellKit

struct Status: ParsableCommand {
    static var configuration = CommandConfiguration(
        abstract: "Shows the status of all repositories in the given directory",
        discussion: """
        Checks all repositories for uncommitted changes and unpushed commits.
        
        Status indicators:
          M - Modified working tree (uncommitted changes)
          P - Unpushed commits exist
        
        Example output:
          Public Repositories:
            repo-name [M]  - has uncommitted changes
            other-repo [P] - has unpushed commits
            both-repo [MP] - has both
        """
    )

    @Argument(help: "Location of the repos for which to report statuses.")
    var basePath: String

    var fullBasePath: String {
        (basePath as NSString).expandingTildeInPath
    }

    @Option(name: .shortAndLong, help: "The GitHub access token of the GitHub user whose repos private repos should be reported in addition to public repos.")
    var accessToken: String
    
    @OptionGroup var repoTypes: RepoTypeOptions
    
    // MARK: Orgs
    
    @Option(help: "Instead of fetching the list of the authenticated user's repos, fetch the specified organization's.")
    var organization: String?

    func run() throws {
        let github = GitHub(accessToken: accessToken)
        
        let reposWithWork: [RepoSummary]
        if let organization = organization {
            let orgUser: User = try github.authenticateOrg(name: organization)
            guard let orgUserLogin = orgUser.login else {
                throw ForgeryError.Status.FailedToLoginOrg
            }
            reposWithWork = try checkRepos(pathsToCheck: pathsForOrg(organization: orgUserLogin))
        } else {
            let user = try github.authenticate()
            reposWithWork = try checkRepos(pathsToCheck: try pathsForUser(user: user))
        }
        
        printSummary(reposWithWork: reposWithWork)
    }

    private func checkRepos(pathsToCheck: [String]) throws -> [RepoSummary] {
        var reposWithWork: [RepoSummary] = []
        let fileManager = FileManager.default
        for path in pathsToCheck {
            let pathURL = URL(fileURLWithPath: path)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
                print("Path does not exist: \(path)")
                continue
            }
            guard isDirectory.boolValue else {
                print("Path is not a directory: \(path)")
                continue
            }
            
            for case let repoPath in try fileManager.contentsOfDirectory(atPath: pathURL.path) {
                let fullRepoPath = "\(pathURL.path)/\(repoPath)"
                guard let type = try fileManager.attributesOfItem(atPath: fullRepoPath)[.type] as? FileAttributeType, type == .typeDirectory else {
                    continue
                }
                
                // Check if this is a git repository
                let gitDirURL = (fullRepoPath as NSString).appendingPathComponent(".git")
                guard fileManager.fileExists(atPath: gitDirURL) else {
                    continue
                }
                
                // Check repository status
                let git = Git(path: fullRepoPath)
                let repoStatus = try checkRepositoryStatus(using: git)
                if repoStatus.isDirty || repoStatus.hasUnpushedCommits {
                    reposWithWork.append(RepoSummary(
                        path: fullRepoPath,
                        status: repoStatus
                    ))
                }
            }
        }
        return reposWithWork
    }

    private func printSummary(reposWithWork: [RepoSummary]) {
        if reposWithWork.isEmpty {
            print("\nAll repositories are clean and up to date!")
        } else {
            print("\nRepositories with pending work:")
            
            // Group repos by type
            let publicRepos = reposWithWork.filter { $0.path.contains("public/") }
            let privateRepos = reposWithWork.filter { $0.path.contains("private/") }
            let forkedRepos = reposWithWork.filter { $0.path.contains("forks/") }
            let starredRepos = reposWithWork.filter { $0.path.contains("starred/") }
            let publicGists = reposWithWork.filter { $0.path.contains("gists/public/") }
            let privateGists = reposWithWork.filter { $0.path.contains("gists/private/") }
            let forkedGists = reposWithWork.filter { $0.path.contains("gists/forks/") }
            let starredGists = reposWithWork.filter { $0.path.contains("gists/starred/") }
            
            // Print each group if it has items
            if !publicRepos.isEmpty {
                print("\nPublic Repositories:")
                printRepoGroup(publicRepos)
            }
            if !privateRepos.isEmpty {
                print("\nPrivate Repositories:")
                printRepoGroup(privateRepos)
            }
            if !forkedRepos.isEmpty {
                print("\nForked Repositories:")
                printRepoGroup(forkedRepos)
            }
            if !starredRepos.isEmpty {
                print("\nStarred Repositories:")
                printRepoGroup(starredRepos)
            }
            if !publicGists.isEmpty {
                print("\nPublic Gists:")
                printRepoGroup(publicGists)
            }
            if !privateGists.isEmpty {
                print("\nPrivate Gists:")
                printRepoGroup(privateGists)
            }
            if !forkedGists.isEmpty {
                print("\nForked Gists:")
                printRepoGroup(forkedGists)
            }
            if !starredGists.isEmpty {
                print("\nStarred Gists:")
                printRepoGroup(starredGists)
            }
        }
    }

    func pathsForUser(user: User) throws -> [String] {
        guard let username = user.login else {
            throw ForgeryError.Status.failedToLogin
        }

        let userPaths = UserPaths(basePath: fullBasePath, username: username)

        var pathsToCheck: [String] = []
        
        // Add repo paths
        if !repoTypes.resolved.noPublicRepos {
            pathsToCheck.append(userPaths.commonPaths.repoPaths.publicPath)
        }
        if !repoTypes.resolved.noPrivateRepos {
            pathsToCheck.append(userPaths.commonPaths.repoPaths.privatePath)
        }
        if !repoTypes.resolved.noForkedRepos {
            pathsToCheck.append(userPaths.commonPaths.repoPaths.forkPath)
        }
        if !repoTypes.resolved.noStarredRepos {
            pathsToCheck.append(userPaths.starredRepoPath)
        }
        
        // Add gist paths
        if !repoTypes.resolved.noPublicGists {
            pathsToCheck.append(userPaths.commonPaths.gistPaths.publicPath)
        }
        if !repoTypes.resolved.noPrivateGists {
            pathsToCheck.append(userPaths.commonPaths.gistPaths.privatePath)
        }
        if !repoTypes.resolved.noForkedGists {
            pathsToCheck.append(userPaths.forkedGistPath)
        }
        if !repoTypes.resolved.noStarredGists {
            pathsToCheck.append(userPaths.starredGistPath)
        }

        return pathsToCheck
    }

    func pathsForOrg(organization: String) throws -> [String] {
        let orgPaths = CommonPaths(basePath: fullBasePath, orgName: organization)

        var pathsToCheck: [String] = []

        // Add repo paths
        if !repoTypes.resolved.noPublicRepos {
            pathsToCheck.append(orgPaths.repoPaths.publicPath)
        }
        if !repoTypes.resolved.noPrivateRepos {
            pathsToCheck.append(orgPaths.repoPaths.privatePath)
        }
        if !repoTypes.resolved.noForkedRepos {
            pathsToCheck.append(orgPaths.repoPaths.forkPath)
        }

        // Add gist paths
        if !repoTypes.resolved.noPublicGists {
            pathsToCheck.append(orgPaths.gistPaths.publicPath)
        }
        if !repoTypes.resolved.noPrivateGists {
            pathsToCheck.append(orgPaths.gistPaths.privatePath)
        }

        return pathsToCheck
    }
        
    private struct RepoStatus {
        let isDirty: Bool
        let hasUnpushedCommits: Bool
    }
    
    private struct RepoSummary {
        let path: String
        let status: RepoStatus
    }
    
    private func checkRepositoryStatus(using git: Git) throws -> RepoStatus {
        // Check for uncommitted changes
        let isDirty = try git.run(.status).isEmpty == false

        // Check for unpushed commits
        var unpushedCommits: Bool = false
        let dispatchGroup = DispatchGroup()
        var forgeryError: ForgeryError.Status?

        dispatchGroup.enter()
        git.run(.log(options: ["--oneline"], revisions: "@{u}..")) { result, error in
            defer { dispatchGroup.leave() }

            guard let shellKitError = error as? Shell.Error else {
                unpushedCommits = result!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
    
    private func printRepoGroup(_ repos: [RepoSummary]) {
        // Sort by name within each group
        for repo in repos.sorted(by: { $0.path.components(separatedBy: "/").last! < $1.path.components(separatedBy: "/").last! }) {
            let repoName = repo.path.components(separatedBy: "/").last!
            var status = ""
            if repo.status.isDirty {
                status += "M" // Modified
            }
            if repo.status.hasUnpushedCommits {
                status += "P" // Unpushed
            }
            print("  \(repoName) [\(status)]")
        }
    }
}
