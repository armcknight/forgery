import ArgumentParser
import Foundation
import OctoKit
import forgery_lib
import GitKit

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

    @Option(name: .shortAndLong, help: "The GitHub access token of the GitHub user whose repos private repos should be reported in addition to public repos.")
    var accessToken: String
    
    @OptionGroup var repoTypes: RepoTypeOptions
    
    // MARK: Orgs
    
    @Option(help: "Instead of fetching the list of the authenticated user's repos, fetch the specified organization's.")
    var organization: String?

    func run() throws {
        let fileManager = FileManager.default
        var reposWithWork: [RepoSummary] = []
        
        let github = GitHub(accessToken: accessToken)


        let pathsToCheck: [String] = organization != nil ? pathsForOrg(organization: organization!) : pathsForUser()

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
            
            guard let enumerator = fileManager.enumerator(at: pathURL, 
                                                        includingPropertiesForKeys: [.isDirectoryKey],
                                                        options: []) else {
                continue
            }
            
            for case let repoPath as URL in enumerator {
                guard let resourceValues = try? repoPath.resourceValues(forKeys: [.isDirectoryKey]),
                        let isDirectory = resourceValues.isDirectory,
                        isDirectory else {
                    continue
                }
                
                // Check if this is a git repository
                let gitDirURL = repoPath.appendingPathComponent(".git")
                guard fileManager.fileExists(atPath: gitDirURL.path) else {
                    continue
                }
                
                // Check repository status
                let git = Git(directoryURL: repoPath)
                let repoStatus = try checkRepositoryStatus(using: git)
                if repoStatus.isDirty || repoStatus.hasUnpushedCommits {
                    reposWithWork.append(RepoSummary(
                        path: repoPath.lastPathComponent,
                        status: repoStatus
                    ))
                }
            }
        }
        
        // Print summary
        if reposWithWork.isEmpty {
            print("\nAll repositories are clean and up to date!")
        } else {
            print("\nRepositories with pending work:")
            
            // Group repos by type
            let publicRepos = reposWithWork.filter { $0.path.starts(with: "public/") }
            let privateRepos = reposWithWork.filter { $0.path.starts(with: "private/") }
            let forkedRepos = reposWithWork.filter { $0.path.starts(with: "forks/") }
            let starredRepos = reposWithWork.filter { $0.path.starts(with: "starred/") }
            let publicGists = reposWithWork.filter { $0.path.starts(with: "gists/public/") }
            let privateGists = reposWithWork.filter { $0.path.starts(with: "gists/private/") }
            let forkedGists = reposWithWork.filter { $0.path.starts(with: "gists/forks/") }
            let starredGists = reposWithWork.filter { $0.path.starts(with: "gists/starred/") }
            
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

    func pathsForUser() -> [String] {
        let userPaths = UserPaths(basePath: basePath, username: username)

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

    func pathsForOrg(organization: String) -> [String] {
        let orgUser: User = try authenticateOrg(name: organization)
        let orgPaths = CommonPaths(basePath: basePath, orgName: organization)

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
        let isDirty = try git.status().isEmpty == false
        
        // Check for unpushed commits
        let unpushedCommits = try git.log(["@{u}.."]).isEmpty == false
        
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
