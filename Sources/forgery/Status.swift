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

    @Flag(help: "Check all users' and orgs' repositories. Supersedes allUsers and allOrgs")
    var all: Bool = false
}

struct Status: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        abstract: "Shows the status of all repositories in the given directory",
        discussion: """
        Checks all repositories for uncommitted changes, unpushed commits, and local-only branches.
        
        Status indicators:
          M - Modified working tree (uncommitted changes)
          P - Unpushed commits exist (requires upstream configuration)
          L - Local-only branches (no upstream configured)
        
        Note: P and L are mutually exclusive per repository since local-only branches
        cannot have unpushed commits (no upstream to push to).
        
        Example output:
          Public Repositories:
            [M] /path/to/../repo-name               - has uncommitted changes
            [P] /path/to/../repo-nameother-repo     - has unpushed commits
            [L] /path/to/../repo-namelocal-repo     - has local-only branches
            [MP] /path/to/../repo-nameboth-repo     - has modifications and unpushed commits
            [ML] /path/to/../repo-namelocal-mod     - has modifications and local-only branches
        """
    )

    @OptionGroup(title: "Basic options")
    var baseOptions: BaseOptions

    @OptionGroup(title: "Repo types to work on")
    var repoTypes: RepoTypeOptions

    @OptionGroup(title: "The individual or sets of users/orgs whose repos should be checked")
    var userTypes: UserTypes

    var fullBasePath: String {
        (baseOptions.basePath as NSString).expandingTildeInPath
    }

    func run() async throws {
        if baseOptions.verbose {
            logger.logLevel = .debug
        }

        var repoSummaries = [RepoSummary]()

        if let organization = userTypes.organization {
            repoSummaries = try await checkForOrganization(organization: organization)
        } else if let user = userTypes.user {
            repoSummaries = try await checkForUsername(username: user)
        } else if userTypes.all {
            try await iterateOverSubdirectories(path: "\(fullBasePath)/\(CommonPaths.userBasePathComponent)") { username in
                repoSummaries.append(contentsOf: try await checkForUsername(username: username))
            }
            try await iterateOverSubdirectories(path: "\(fullBasePath)/\(CommonPaths.orgBasePathComponent)") { organization in
                repoSummaries.append(contentsOf: try await checkForOrganization(organization: organization))
            }
        } else if userTypes.allUsers {
            if userTypes.allOrgs {
                throw ForgeryError.Status.useAll
            }

            try await iterateOverSubdirectories(path: "\(fullBasePath)/\(CommonPaths.userBasePathComponent)") { username in
                repoSummaries.append(contentsOf: try await checkForUsername(username: username))
            }
        } else if userTypes.allOrgs {
            try await iterateOverSubdirectories(path: "\(fullBasePath)/\(CommonPaths.orgBasePathComponent)") { organization in
                repoSummaries.append(contentsOf: try await checkForOrganization(organization: organization))
            }
        } else {
            throw ForgeryError.Status.invalidOption
        }

        try await printSummary(reposWithWork: repoSummaries)
    }

    private func iterateOverSubdirectories(path: String, block: (String) async throws -> Void) async throws {
        guard FileManager.default.fileExists(atPath: path) else {
            throw ForgeryError.Status.pathDoesNotExist
        }

        for case let subdirectory in try FileManager.default.contentsOfDirectory(atPath: path) {
            try await block(subdirectory)
        }
    }

    private func checkForUsername(username: String) async throws -> [RepoSummary] {
        let userPaths = try UserPaths(basePath: baseOptions.basePath, username: username, repoTypes: repoTypes.resolved, createOnDisk: false)
        return try await checkRepos(pathsToCheck: userPaths.validPaths)
    }

    private func checkForOrganization(organization: String) async throws -> [RepoSummary] {
        let orgPaths = try CommonPaths(basePath: baseOptions.basePath, orgName: organization, repoTypes: repoTypes.resolved, createOnDisk: false)
        return try await checkRepos(pathsToCheck: orgPaths.validPaths)
    }

    private func checkRepos(pathsToCheck: [String]) async throws -> [RepoSummary] {
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
            
            // Check if this is a starred or forked directory that has an extra owner level
            let needsOwnerLevel = fullPath.contains("/starred") || fullPath.contains("/forked")
            
            for case let repoPath in try fileManager.contentsOfDirectory(atPath: fullPath) {
                logger.debug("Checking repo: \(repoPath)")
                let fullRepoPath = "\(fullPath)/\(repoPath)"
                guard let type = try fileManager.attributesOfItem(atPath: fullRepoPath)[.type] as? FileAttributeType, type == .typeDirectory else {
                    continue
                }

                if needsOwnerLevel {
                    // This is an owner directory, need to descend one more level to find actual repos
                    logger.debug("Checking owner directory: \(repoPath)")
                    for case let actualRepoPath in try fileManager.contentsOfDirectory(atPath: fullRepoPath) {
                        logger.debug("Checking actual repo: \(actualRepoPath)")
                        let fullActualRepoPath = "\(fullRepoPath)/\(actualRepoPath)"
                        guard let actualType = try fileManager.attributesOfItem(atPath: fullActualRepoPath)[.type] as? FileAttributeType, actualType == .typeDirectory else {
                            continue
                        }
                        
                        let gitDirURL = (fullActualRepoPath as NSString).appendingPathComponent(".git")
                        guard fileManager.fileExists(atPath: gitDirURL) else {
                            logger.warning("Directory does not contain a git repo: \(fullActualRepoPath)")
                            continue
                        }

                        let repoSummary = try await summarizeStatus(repoPath: fullActualRepoPath, pushWIPChanges: false)
                        if repoSummary.needsReport {
                            reposWithWork.append(repoSummary)
                        }
                    }
                } else {
                    // Regular directory structure - repo is directly here
                    let gitDirURL = (fullRepoPath as NSString).appendingPathComponent(".git")
                    guard fileManager.fileExists(atPath: gitDirURL) else {
                        logger.warning("Directory does not contain a git repo: \(fullRepoPath)")
                        continue
                    }

                    let repoSummary = try await summarizeStatus(repoPath: fullRepoPath, pushWIPChanges: false)
                    if repoSummary.needsReport {
                        reposWithWork.append(repoSummary)
                    }
                }
            }
        }
        return reposWithWork
    }

    private func printSummary(reposWithWork: [RepoSummary]) async throws {
        guard !reposWithWork.isEmpty else {
            print("\nAll repositories are clean and up to date!")
            return
        }

        let modifiedRepos = reposWithWork.filter { $0.status.contains(.dirtyIndex) }
        let unpushedRepos = reposWithWork.filter { !$0.branchInfo.isEmpty }
        let localOnlyRepos = reposWithWork.filter { $0.status.contains(.localOnlyBranches) }

        try await printReposByType(modifiedRepos, title: "Repositories with uncommitted changes", dirty: true, unpushed: false)
        try await printReposByType(unpushedRepos, title: "Repositories with unpushed commits on branches", dirty: false, unpushed: true)
        try await printReposByType(localOnlyRepos, title: "Repositories with local-only branches", dirty: false, unpushed: false, localOnly: true)
    }

    private func printReposByType(_ repos: [RepoSummary], title: String, dirty: Bool, unpushed: Bool, localOnly: Bool = false) async throws {
        guard !repos.isEmpty else { return }
        print("\n\(title):")
        try await printRepoGroup(repos.filter { $0.path.contains("repos/public/") }, title: "Public Repositories", dirty: dirty, unpushed: unpushed, localOnly: localOnly)
        try await printRepoGroup(repos.filter { $0.path.contains("repos/private/") }, title: "Private Repositories", dirty: dirty, unpushed: unpushed, localOnly: localOnly)
        try await printRepoGroup(repos.filter { $0.path.contains("repos/forks/") }, title: "Forked Repositories", dirty: dirty, unpushed: unpushed, localOnly: localOnly)
        try await printRepoGroup(repos.filter { $0.path.contains("repos/starred/") }, title: "Starred Repositories", dirty: dirty, unpushed: unpushed, localOnly: localOnly)
        try await printRepoGroup(repos.filter { $0.path.contains("gists/public/") }, title: "Public Gists", dirty: dirty, unpushed: unpushed, localOnly: localOnly)
        try await printRepoGroup(repos.filter { $0.path.contains("gists/private/") }, title: "Private Gists", dirty: dirty, unpushed: unpushed, localOnly: localOnly)
        try await printRepoGroup(repos.filter { $0.path.contains("gists/forks/") }, title: "Forked Gists", dirty: dirty, unpushed: unpushed, localOnly: localOnly)
        try await printRepoGroup(repos.filter { $0.path.contains("gists/starred/") }, title: "Starred Gists", dirty: dirty, unpushed: unpushed, localOnly: localOnly)
    }

    private func printRepoGroup(_ repos: [RepoSummary], title: String, dirty: Bool, unpushed: Bool, localOnly: Bool = false) async throws {
        guard !repos.isEmpty else { return }
        print("\t\(title):")
        for repo in repos.sorted(by: { $0.path.components(separatedBy: "/").last! < $1.path.components(separatedBy: "/").last! }) {
            print("\t\t[\(repo.description)] \(repo.path)")
            if dirty {
                print(try await diffstat(repoPath: repo.path).split(separator: "\n").map({ "\t\t\t\($0)" }).joined(separator: "\n"))
            } else if unpushed {
                for branch in repo.repositoryBranchInfo.branchesWithUnpushedCommits {
                    if case .unpushedCommits(let count) = branch.status {
                        let currentIndicator = branch.isCurrentBranch ? " (current)" : ""
                        print("\t\t\t\(branch.name): \(count) unpushed commits\(currentIndicator)")
                    }
                }
            } else if localOnly {
                for branch in repo.repositoryBranchInfo.localOnlyBranches {
                    let currentIndicator = branch.isCurrentBranch ? " (current)" : ""
                    print("\t\t\t\(branch.name): local-only branch (no upstream configured)\(currentIndicator)")
                }
            }
        }
    }
}
