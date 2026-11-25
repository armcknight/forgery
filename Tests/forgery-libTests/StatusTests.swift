import XCTest
import Foundation
import ForgeryTestSupport
@testable import forgery_lib

/**
 * Covers how repos are found on disk and what category they are filed under.
 */
class StatusTests: XCTestCase {

    private var temporaryDirectory: TemporaryDirectory!
    private var basePath: String { temporaryDirectory.path }

    override func setUp() {
        super.setUp()
        temporaryDirectory = TemporaryDirectory()
    }

    override func tearDown() {
        temporaryDirectory = nil
        super.tearDown()
    }

    // MARK: - Roots

    func testUserRootsCoverEveryRepoType() throws {
        let paths = try UserPaths(basePath: basePath, username: "testuser", repoTypes: allRepoTypes(), createOnDisk: false)
        let categories = Set(paths.validRoots.map { $0.category })

        XCTAssertEqual(categories, Set(RepoCategory.allCases), "Every repo type should have a root to scan")
    }

    func testStarredRootIsIncluded() throws {
        let paths = try UserPaths(basePath: basePath, username: "testuser", repoTypes: allRepoTypes(), createOnDisk: false)
        let starred = paths.validRoots.first { $0.category == .starredRepo }

        XCTAssertEqual(starred?.path, "\(basePath)/user/testuser/repos/starred")
        XCTAssertEqual(starred?.path, paths.starredRepoPath)
    }

    func testOwnerNestedRootsAreTheStarredAndForkedTrees() throws {
        let paths = try UserPaths(basePath: basePath, username: "testuser", repoTypes: allRepoTypes(), createOnDisk: false)
        let nested = Set(paths.validRoots.filter { $0.isOwnerNested }.map { $0.category })

        // Starred and forked trees hold other people's repos, so they are cloned one level deeper
        // under the owner's login. See `GitHub.cloneForkedRepo`.
        XCTAssertEqual(nested, [.starredRepo, .forkedRepo, .starredGist, .forkedGist])
    }

    func testExcludedRepoTypesProduceNoRoot() throws {
        let noStarred = RepoTypeOptions.Resolved(
            noRepos: false, noForkedRepos: false, noStarredRepos: true, noPublicRepos: false, noPrivateRepos: false,
            onlyStarredRepos: false, onlyForkedRepos: false, onlyPublicRepos: false, onlyPrivateRepos: false,
            noWikis: false, noGists: false, noForkedGists: false, noStarredGists: false, noPublicGists: false, noPrivateGists: false,
            onlyStarredGists: false, onlyForkedGists: false, onlyPublicGists: false, onlyPrivateGists: false
        )
        let paths = try UserPaths(basePath: basePath, username: "testuser", repoTypes: noStarred, createOnDisk: false)

        XCTAssertFalse(paths.validRoots.contains { $0.category == .starredRepo })
    }

    func testOrganizationsHaveNoStarredOrForkedGistRoots() throws {
        let paths = try CommonPaths(basePath: basePath, orgName: "testorg", repoTypes: allRepoTypes(), createOnDisk: false)
        let categories = Set(paths.validRoots.map { $0.category })

        // Orgs cannot star repos or fork gists, so those roots do not exist for them.
        XCTAssertEqual(categories, [.publicRepo, .privateRepo, .forkedRepo, .publicGist, .privateGist])
    }

    // MARK: - Discovery

    func testDiscoversReposDirectlyUnderFlatRoots() async throws {
        let root = "\(basePath)/user/testuser/repos/public"
        try await GitFixture.makeRepo(at: "\(root)/my-blog")
        try await GitFixture.makeRepo(at: "\(root)/my-notes")

        let discovered = discoverRepositories(roots: [RepoRoot(path: root, category: .publicRepo)])

        XCTAssertEqual(discovered.map { ($0.path as NSString).lastPathComponent }, ["my-blog", "my-notes"])
        XCTAssertTrue(discovered.allSatisfy { $0.owner == nil }, "A flat root has no owner level")
        XCTAssertTrue(discovered.allSatisfy { $0.category == .publicRepo })
    }

    func testDiscoversReposUnderAnOwnerLevel() async throws {
        let root = "\(basePath)/user/testuser/repos/starred"
        try await GitFixture.makeRepo(at: "\(root)/owner1/awesome-repo")
        try await GitFixture.makeRepo(at: "\(root)/owner2/cool-project")

        let discovered = discoverRepositories(roots: [RepoRoot(path: root, category: .starredRepo)])

        XCTAssertEqual(discovered.count, 2)
        XCTAssertEqual(Set(discovered.compactMap { $0.owner }), ["owner1", "owner2"])
        XCTAssertTrue(discovered.allSatisfy { $0.category == .starredRepo })
    }

    /// Forked repos are cloned under `forked`, but the report grouped on `forks`, so they were
    /// scanned and then dropped before anything was printed.
    func testForkedReposAreDiscoveredAndCategorised() async throws {
        let root = "\(basePath)/user/testuser/repos/forked"
        try await GitFixture.makeRepo(at: "\(root)/apache/kafka")

        let discovered = discoverRepositories(roots: [RepoRoot(path: root, category: .forkedRepo)])

        XCTAssertEqual(discovered.count, 1)
        XCTAssertEqual(discovered.first?.owner, "apache")
        XCTAssertEqual(discovered.first?.category, .forkedRepo)
    }

    /// The old check tested whether the whole path contained `/forked` or `/starred`, so a base
    /// path with either word in it made every root look owner-nested.
    func testBasePathContainingForkedDoesNotAddAnOwnerLevel() async throws {
        let root = "\(basePath)/forked-stuff/user/testuser/repos/public"
        try await GitFixture.makeRepo(at: "\(root)/my-blog")

        let discovered = discoverRepositories(roots: [RepoRoot(path: root, category: .publicRepo)])

        XCTAssertEqual(discovered.count, 1, "A public root is flat no matter what the base path is called")
        XCTAssertNil(discovered.first?.owner)
    }

    func testNonRepositoryDirectoriesAreSkipped() async throws {
        let root = "\(basePath)/user/testuser/repos/public"
        try await GitFixture.makeRepo(at: "\(root)/real-repo")
        try FileManager.default.createDirectory(atPath: "\(root)/not-a-repo", withIntermediateDirectories: true)

        let discovered = discoverRepositories(roots: [RepoRoot(path: root, category: .publicRepo)])

        XCTAssertEqual(discovered.map { ($0.path as NSString).lastPathComponent }, ["real-repo"])
    }

    func testMissingRootIsSkippedRatherThanFailing() {
        let discovered = discoverRepositories(roots: [
            RepoRoot(path: "\(basePath)/does/not/exist", category: .publicRepo)
        ])

        XCTAssertTrue(discovered.isEmpty)
    }
}
