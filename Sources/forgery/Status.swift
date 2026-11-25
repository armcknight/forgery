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
        Checks every repository for uncommitted work, how its branches compare to their
        upstreams, and branches that have no upstream at all.

        Status indicators:
          M - modified working tree (staged, unstaged, or untracked)
          S - stashed changes
          A - a branch is ahead of its upstream
          B - a branch is behind its upstream
          D - a branch is diverged (both ahead of and behind its upstream)
          L - a branch has no upstream
          G - an upstream is gone from the remote
          H - detached HEAD
          ! - a requested fetch failed, so the remote data shown is old

        A repository can carry several indicators at once. One repository can hold both a
        tracked branch that is ahead and an untracked branch, so A, B, D and L are not
        exclusive of one another.

        Without --fetch, everything compared against a remote is only as fresh as your last
        fetch.

        Example output:
          Public Repositories:
            [MD] /path/to/repos/public/repo-name
                * main       ↑3 ↓2
                  feature-x  ↑1
                  scratch    (no upstream)
        """
    )

    @OptionGroup(title: "Basic options")
    var baseOptions: BaseOptions

    @OptionGroup(title: "Repo types to work on")
    var repoTypes: RepoTypeOptions

    @OptionGroup(title: "The individual or sets of users/orgs whose repos should be checked")
    var userTypes: UserTypes

    @Flag(name: .long, help: "Fetch from every remote, pruning deleted branches, before reading each repository's state. Slower, but the only way to get current remote comparisons.")
    var fetch: Bool = false

    @Flag(name: .long, help: "List every local branch of the reported repositories, not just the branches that need attention.")
    var allBranches: Bool = false

    @Flag(name: .long, help: "Also list repositories that have nothing to report.")
    var allRepos: Bool = false

    @Option(name: .long, help: "Write a self-contained HTML report to this path.")
    var html: String? = nil

    @Flag(name: .customLong("open"), help: "Open the HTML report in the default browser. Requires --html.")
    var openReport: Bool = false

    @Option(name: .long, help: "How many repositories to inspect at once.")
    var jobs: Int = 8

    @Option(name: .long, help: "How many repositories to rank in each of the summary's top lists.")
    var top: Int = 5

    @Flag(name: .long, help: "Do not print the terminal report. Useful together with --html.")
    var quiet: Bool = false

    var fullBasePath: String {
        (baseOptions.basePath as NSString).expandingTildeInPath
    }

    func validate() throws {
        if openReport && html == nil {
            throw ValidationError("--open needs --html, because there is nothing to open without it.")
        }
        if jobs < 1 {
            throw ValidationError("--jobs must be at least 1.")
        }
        if top < 1 {
            throw ValidationError("--top must be at least 1.")
        }
    }

    func run() async throws {
        if baseOptions.verbose {
            logger.logLevel = .debug
        }

        let roots = try collectRoots()
        let report = try await scanRepositories(
            roots: roots,
            options: ScanOptions(
                inspection: RepoInspectionOptions(fetch: fetch, collectDiffstat: true, pushWIPChanges: false),
                maxConcurrentRepos: jobs
            )
        )

        if !quiet {
            print(renderTerminalReport(report, options: TerminalReportOptions(
                showAllBranches: allBranches,
                showCleanRepos: allRepos,
                showDiffstat: true,
                topCount: top
            )))
        }

        if let html {
            try writeHTMLReport(report, to: html)
        }
    }

    // MARK: - Roots

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
        try UserPaths(basePath: baseOptions.basePath, username: username, repoTypes: repoTypes.resolved, createOnDisk: false).validRoots
    }

    private func organizationRoots(_ organization: String) throws -> [RepoRoot] {
        try CommonPaths(basePath: baseOptions.basePath, orgName: organization, repoTypes: repoTypes.resolved, createOnDisk: false).validRoots
    }

    private func forEachSubdirectory(of path: String, block: (String) throws -> Void) throws {
        guard FileManager.default.fileExists(atPath: path) else {
            throw ForgeryError.Status.pathDoesNotExist
        }
        for subdirectory in try FileManager.default.contentsOfDirectory(atPath: path).sorted() {
            try block(subdirectory)
        }
    }

    // MARK: - HTML

    private func writeHTMLReport(_ report: StatusReport, to path: String) throws {
        let destination = (path as NSString).expandingTildeInPath
        try renderHTMLReport(report, topCount: top).write(toFile: destination, atomically: true, encoding: .utf8)

        if !quiet {
            print("\nWrote HTML report to \(destination)")
        }

        guard openReport else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [destination]
        try process.run()
    }
}
