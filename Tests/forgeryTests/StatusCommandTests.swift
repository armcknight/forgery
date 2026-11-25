import XCTest
import Foundation
import ForgeryTestSupport
@testable import forgery_lib

/**
 * End to end coverage of a scan over a full tree, through the same entry point the `status`
 * command uses.
 */
class StatusCommandTests: XCTestCase {

    private var temporaryDirectory: TemporaryDirectory!
    private var basePath: String { temporaryDirectory.path }
    private var userRoot: String { "\(basePath)/user/testuser" }

    override func setUp() {
        super.setUp()
        temporaryDirectory = TemporaryDirectory(prefix: "forgery-status-test")
    }

    override func tearDown() {
        temporaryDirectory = nil
        super.tearDown()
    }

    private func roots() throws -> [RepoRoot] {
        try UserPaths(basePath: basePath, username: "testuser", repoTypes: allRepoTypes(), createOnDisk: false).validRoots
    }

    // MARK: - Scanning a whole tree

    func testScanFindsEveryRepoTypeIncludingOwnerNestedOnes() async throws {
        try await GitFixture.makeRepo(at: "\(userRoot)/repos/public/my-blog")
        try await GitFixture.makeRepo(at: "\(userRoot)/repos/private/secrets")
        try await GitFixture.makeRepo(at: "\(userRoot)/repos/forked/apache/kafka")
        try await GitFixture.makeRepo(at: "\(userRoot)/repos/starred/github/swift")
        try await GitFixture.makeRepo(at: "\(userRoot)/gists/public/abc123")
        try await GitFixture.makeRepo(at: "\(userRoot)/gists/forked/someone/def456")

        let report = try await scanRepositories(roots: try roots())

        XCTAssertEqual(report.repos.count, 6)
        XCTAssertEqual(Set(report.repos.map { $0.category }), [
            .publicRepo, .privateRepo, .forkedRepo, .starredRepo, .publicGist, .forkedGist,
        ])
    }

    /// Forked repos and gists reached the report but never made it into any printed group.
    func testForkedReposAppearInTheRenderedReport() async throws {
        let repo = try await GitFixture.makeRepo(at: "\(userRoot)/repos/forked/apache/kafka")
        try repo.writeUncommittedChange()

        let report = try await scanRepositories(roots: try roots())
        let output = renderTerminalReport(report)

        XCTAssertEqual(report.reportingRepos.count, 1)
        XCTAssertEqual(report.reportingRepos.first?.category, .forkedRepo)
        XCTAssertTrue(output.contains("Forked Repositories:"))
        XCTAssertTrue(output.contains("kafka"))
    }

    func testOwnerIsRecordedForNestedTrees() async throws {
        try await GitFixture.makeRepo(at: "\(userRoot)/repos/starred/github/swift")
        try await GitFixture.makeRepo(at: "\(userRoot)/repos/public/my-blog")

        let report = try await scanRepositories(roots: try roots())
        let starred = try XCTUnwrap(report.repos.first { $0.category == .starredRepo })
        let owned = try XCTUnwrap(report.repos.first { $0.category == .publicRepo })

        XCTAssertEqual(starred.owner, "github")
        XCTAssertEqual(starred.shortLabel, "github/swift")
        XCTAssertNil(owned.owner)
        XCTAssertEqual(owned.shortLabel, "my-blog")
    }

    func testCleanTreeReportsNothingToDo() async throws {
        try await GitFixture.makeRepoWithUpstream(
            at: "\(userRoot)/repos/public/tidy",
            remotePath: temporaryDirectory.appending("tidy.git")
        )

        let report = try await scanRepositories(roots: try roots())

        XCTAssertEqual(report.repos.count, 1)
        XCTAssertTrue(report.isEmpty, "A repo tracking an in-sync upstream has nothing to report")
        XCTAssertTrue(renderTerminalReport(report).contains("All repositories are clean and up to date!"))
    }

    func testReposWithoutARemoteAreReportedAsLocalOnly() async throws {
        try await GitFixture.makeRepo(at: "\(userRoot)/repos/public/no-remote")

        let report = try await scanRepositories(roots: try roots())
        let repo = try XCTUnwrap(report.reportingRepos.first)

        XCTAssertEqual(repo.description, "L")
        XCTAssertEqual(repo.localOnlyBranches.map { $0.name }, ["main"])
    }

    func testScanIsUnaffectedByHowManyReposRunAtOnce() async throws {
        for index in 1...6 {
            let repo = try await GitFixture.makeRepo(at: "\(userRoot)/repos/public/repo\(index)")
            try repo.writeUncommittedChange()
        }

        let serial = try await scanRepositories(roots: try roots(), options: ScanOptions(maxConcurrentRepos: 1))
        let concurrent = try await scanRepositories(roots: try roots(), options: ScanOptions(maxConcurrentRepos: 4))

        XCTAssertEqual(serial.repos.count, 6)
        XCTAssertEqual(concurrent.repos.count, 6)
        XCTAssertEqual(serial.repos.map { $0.path }, concurrent.repos.map { $0.path }, "Results are sorted, so order does not depend on timing")
    }

    func testUnreadableDirectoriesDoNotStopTheScan() async throws {
        let repo = try await GitFixture.makeRepo(at: "\(userRoot)/repos/public/real")
        try repo.writeUncommittedChange()
        try FileManager.default.createDirectory(atPath: "\(userRoot)/repos/public/junk", withIntermediateDirectories: true)

        let report = try await scanRepositories(roots: try roots())

        XCTAssertEqual(report.repos.map { $0.name }, ["real"])
    }

    func testExcludedRepoTypesAreNotScanned() async throws {
        try await GitFixture.makeRepo(at: "\(userRoot)/repos/public/wanted")
        try await GitFixture.makeRepo(at: "\(userRoot)/repos/starred/github/unwanted")

        let noStarred = RepoTypeOptions.Resolved(
            noRepos: false, noForkedRepos: false, noStarredRepos: true, noPublicRepos: false, noPrivateRepos: false,
            onlyStarredRepos: false, onlyForkedRepos: false, onlyPublicRepos: false, onlyPrivateRepos: false,
            noWikis: false, noGists: false, noForkedGists: false, noStarredGists: false, noPublicGists: false, noPrivateGists: false,
            onlyStarredGists: false, onlyForkedGists: false, onlyPublicGists: false, onlyPrivateGists: false
        )
        let roots = try UserPaths(basePath: basePath, username: "testuser", repoTypes: noStarred, createOnDisk: false).validRoots
        let report = try await scanRepositories(roots: roots)

        XCTAssertEqual(report.repos.map { $0.name }, ["wanted"])
    }

    // MARK: - Mixed states across a tree

    func testTreeWithSeveralStatesRollsUpCorrectly() async throws {
        let dirty = try await GitFixture.makeRepoWithUpstream(
            at: "\(userRoot)/repos/public/dirty",
            remotePath: temporaryDirectory.appending("dirty.git")
        )
        try dirty.writeUncommittedChange()

        let ahead = try await GitFixture.makeRepoWithUpstream(
            at: "\(userRoot)/repos/public/ahead",
            remotePath: temporaryDirectory.appending("ahead.git")
        )
        try await ahead.commit(file: "new.txt", content: "new", message: "Unpushed")

        try await GitFixture.makeRepoWithUpstream(
            at: "\(userRoot)/repos/public/tidy",
            remotePath: temporaryDirectory.appending("tidy.git")
        )

        let report = try await scanRepositories(roots: try roots())
        let rollup = report.rollup()
        let states = Dictionary(uniqueKeysWithValues: rollup.byState.map { ($0.state, $0.count) })

        XCTAssertEqual(rollup.totalScanned, 3)
        XCTAssertEqual(rollup.needingAttention, 2)
        XCTAssertEqual(states[.modified], 1)
        XCTAssertEqual(states[.ahead], 1)
        XCTAssertEqual(states[.clean], 1)
    }

    func testHTMLAndTerminalReportsDescribeTheSameScan() async throws {
        let repo = try await GitFixture.makeRepoWithUpstream(
            at: "\(userRoot)/repos/public/forgery",
            remotePath: temporaryDirectory.appending("forgery.git")
        )
        try await repo.commit(file: "new.txt", content: "new", message: "Unpushed")
        try await repo.createBranch("scratch")

        let report = try await scanRepositories(roots: try roots())

        let terminal = renderTerminalReport(report)
        let html = renderHTMLReport(report)

        for output in [terminal, html] {
            XCTAssertTrue(output.contains("forgery"))
            XCTAssertTrue(output.contains("scratch"))
        }
        XCTAssertTrue(terminal.contains("↑1"))
        XCTAssertTrue(html.contains("↑1"))
    }
}
