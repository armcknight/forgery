import ArgumentParser
import Foundation
import OctoKit
import forgery_lib

struct UserTypes: ParsableArguments {
    public init() {}

    @Option(help: "Login of the user owning repositories to check.")
    var user: String? = nil

    @Option(help: "Org name owning repositories to check.")
    var organization: String? = nil

    @Flag(help: "Check all users' repositories instead of just specifying one. Cannot be specified together with allOrgs; use all.")
    var allUsers: Bool = false

    @Flag(help: "Check all orgs' repositories instead of just specifying one. Cannot be specified together with allUsers; use all.")
    var allOrgs: Bool = false

    @Flag(help: "Check all users' and orgs' repositories. Supercedes allUsers and allOrgs")
    var all: Bool = false
}

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
            [M] /path/to/../repo-name               - has uncommitted changes
            [W] /path/to/../repo-namewip-repo       - uncommitted changes were pushed to WIP branch
            [P] /path/to/../repo-nameother-repo     - has unpushed commits
            [MP] /path/to/../repo-nameboth-repo     - has both
        
        When --wip is used, any repository with uncommitted changes will have those
        changes committed to a new 'forgery-wip' branch and pushed to remote.
        """
    )

    @OptionGroup(title: "Basic options")
    var baseOptions: BaseOptions

    @Flag(name: .long, help: "Create WIP branches for repositories with uncommitted changes")
    var pushWIP = false

    @OptionGroup(title: "Repo types to work on")
    var repoTypes: RepoTypeOptions

    @OptionGroup(title: "The individual or sets of users/orgs whose repos should be checked")
    var userTypes: UserTypes

    var fullBasePath: String {
        (baseOptions.basePath as NSString).expandingTildeInPath
    }

    func run() throws {
        if baseOptions.verbose {
            logger.logLevel = .debug
        }

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

        printSummary(reposWithWork: repoSummaries)
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
        let userPaths = try UserPaths(basePath: baseOptions.basePath, username: username, repoTypes: repoTypes.resolved, createOnDisk: false)
        return try checkRepos(pathsToCheck: userPaths.validPaths)
    }

    private func checkForOrganization(organization: String) throws -> [RepoSummary] {
        let orgPaths = try CommonPaths(basePath: baseOptions.basePath, orgName: organization, repoTypes: repoTypes.resolved, createOnDisk: false)
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

                let repoStatus = try checkStatus(repoPath: fullRepoPath, pushWIPChanges: pushWIP)
                if repoStatus.needsReport {
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
            logger.info("\nAll repositories are clean and up to date!")
        } else {
            logger.info("\nRepositories with pending work:")

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
                logger.info("\nPublic Repositories:")
                printRepoGroup(publicRepos)
            }
            if !privateRepos.isEmpty {
                logger.info("\nPrivate Repositories:")
                printRepoGroup(privateRepos)
            }
            if !forkedRepos.isEmpty {
                logger.info("\nForked Repositories:")
                printRepoGroup(forkedRepos)
            }
            if !starredRepos.isEmpty {
                logger.info("\nStarred Repositories:")
                printRepoGroup(starredRepos)
            }
            if !publicGists.isEmpty {
                logger.info("\nPublic Gists:")
                printRepoGroup(publicGists)
            }
            if !privateGists.isEmpty {
                logger.info("\nPrivate Gists:")
                printRepoGroup(privateGists)
            }
            if !forkedGists.isEmpty {
                logger.info("\nForked Gists:")
                printRepoGroup(forkedGists)
            }
            if !starredGists.isEmpty {
                logger.info("\nStarred Gists:")
                printRepoGroup(starredGists)
            }
        }
    }
    
    private struct RepoSummary {
        let path: String
        let status: RepoState
    }

    private func printRepoGroup(_ repos: [RepoSummary]) {
        for repo in repos.sorted(by: { $0.path.components(separatedBy: "/").last! < $1.path.components(separatedBy: "/").last! }) {
            print("  [\(repo.status.description)] \(repo.path)")
        }
    }
}
