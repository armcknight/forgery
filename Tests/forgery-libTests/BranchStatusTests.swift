import XCTest
import Foundation
import ForgeryTestSupport
@testable import forgery_lib

/**
 * Covers what `readBranches` and `inspectRepo` report for each way a branch can relate to its
 * upstream.
 *
 * These use a real bare repo as a remote. Before that fixture existed, no test had a remote at
 * all, so every branch in every fixture was local-only and the ahead, behind and diverged paths
 * were never run.
 */
class BranchStatusTests: XCTestCase {

    private var temporaryDirectory: TemporaryDirectory!
    private var repoPath: String { temporaryDirectory.appending("repo") }
    private var remotePath: String { temporaryDirectory.appending("remote.git") }

    override func setUp() {
        super.setUp()
        temporaryDirectory = TemporaryDirectory(prefix: "forgery-branch-test")
    }

    override func tearDown() {
        temporaryDirectory = nil
        super.tearDown()
    }

    // MARK: - Tracking states

    func testTrackedBranchInSyncIsUpToDate() async throws {
        try await GitFixture.makeRepoWithUpstream(at: repoPath, remotePath: remotePath)

        let branches = try await readBranches(repoPath: repoPath)
        let main = try XCTUnwrap(branches.first { $0.name == "main" })

        XCTAssertEqual(main.upstream, "origin/main")
        XCTAssertEqual(main.ahead, 0)
        XCTAssertEqual(main.behind, 0)
        XCTAssertTrue(main.isUpToDate)
        XCTAssertFalse(main.needsAttention)
        XCTAssertTrue(main.isCurrent)
    }

    func testBranchAheadReportsTheCommitCount() async throws {
        let repo = try await GitFixture.makeRepoWithUpstream(at: repoPath, remotePath: remotePath)
        try await repo.commit(file: "a.txt", content: "a", message: "Local one")
        try await repo.commit(file: "b.txt", content: "b", message: "Local two")

        let branches = try await readBranches(repoPath: repoPath)
        let main = try XCTUnwrap(branches.first { $0.name == "main" })

        XCTAssertEqual(main.ahead, 2)
        XCTAssertEqual(main.behind, 0)
        XCTAssertTrue(main.isAhead)
        XCTAssertFalse(main.isDiverged)
    }

    /// A branch that is only behind used to look completely clean, because only the ahead count
    /// was ever computed.
    func testBranchBehindReportsTheCommitCount() async throws {
        let repo = try await GitFixture.makeRepoWithUpstream(at: repoPath, remotePath: remotePath)
        try await GitFixture.advanceRemote(remotePath, via: temporaryDirectory.appending("scratch"))
        try await repo.fetch()

        let branches = try await readBranches(repoPath: repoPath)
        let main = try XCTUnwrap(branches.first { $0.name == "main" })

        XCTAssertEqual(main.ahead, 0)
        XCTAssertEqual(main.behind, 1)
        XCTAssertTrue(main.isBehind)
        XCTAssertTrue(main.needsAttention)
    }

    func testDivergedBranchReportsBothCounts() async throws {
        let repo = try await GitFixture.makeRepoWithUpstream(at: repoPath, remotePath: remotePath)
        try await GitFixture.advanceRemote(remotePath, via: temporaryDirectory.appending("scratch"))
        try await repo.commit(file: "local.txt", content: "local", message: "Local commit")
        try await repo.fetch()

        let branches = try await readBranches(repoPath: repoPath)
        let main = try XCTUnwrap(branches.first { $0.name == "main" })

        XCTAssertEqual(main.ahead, 1)
        XCTAssertEqual(main.behind, 1)
        XCTAssertTrue(main.isDiverged)
    }

    func testBranchWithoutUpstreamIsLocalOnly() async throws {
        let repo = try await GitFixture.makeRepoWithUpstream(at: repoPath, remotePath: remotePath)
        try await repo.createBranch("scratch")

        let branches = try await readBranches(repoPath: repoPath)
        let scratch = try XCTUnwrap(branches.first { $0.name == "scratch" })
        let main = try XCTUnwrap(branches.first { $0.name == "main" })

        XCTAssertNil(scratch.upstream)
        XCTAssertTrue(scratch.isLocalOnly)
        XCTAssertFalse(main.isLocalOnly, "A tracked branch in the same repo stays tracked")
    }

    func testDeletedUpstreamIsReportedAsGone() async throws {
        let repo = try await GitFixture.makeRepoWithUpstream(at: repoPath, remotePath: remotePath)
        try await repo.createBranch("doomed", checkout: true)
        try await repo.commit(file: "doomed.txt", content: "doomed", message: "Doomed commit")
        try await repo.push(branch: "doomed")
        try await repo.deleteRemoteBranch("doomed")

        let branches = try await readBranches(repoPath: repoPath)
        let doomed = try XCTUnwrap(branches.first { $0.name == "doomed" })

        XCTAssertNotNil(doomed.upstream, "The branch still has an upstream configured")
        XCTAssertTrue(doomed.upstreamGone, "The upstream no longer exists on the remote")
        XCTAssertFalse(doomed.isLocalOnly, "A gone upstream is not the same as never having one")
    }

    // MARK: - Cases that used to be misread

    /// `git branch` marks a branch checked out in another worktree with `+ ` rather than `* `. That
    /// prefix survived into the branch name, the upstream lookup failed, and the branch was
    /// reported as local-only.
    func testBranchCheckedOutInAnotherWorktreeKeepsItsTrackingState() async throws {
        let repo = try await GitFixture.makeRepoWithUpstream(at: repoPath, remotePath: remotePath)
        try await repo.createBranch("feature")
        try await repo.push(branch: "feature")
        try await repo.addWorktree(at: temporaryDirectory.appending("worktree"), branch: "feature")

        let branches = try await readBranches(repoPath: repoPath)
        let feature = try XCTUnwrap(branches.first { $0.name == "feature" })

        XCTAssertEqual(feature.name, "feature", "The name must not carry the '+ ' marker")
        XCTAssertEqual(feature.upstream, "origin/feature")
        XCTAssertFalse(feature.isLocalOnly)
        XCTAssertTrue(feature.isCheckedOutElsewhere)
        XCTAssertFalse(feature.isCurrent)
    }

    /// A detached HEAD prints as `* (HEAD detached at 1234abc)`, which became a branch of that
    /// name and was then reported as local-only.
    func testDetachedHeadDoesNotProduceAPhantomBranch() async throws {
        let repo = try await GitFixture.makeRepoWithUpstream(at: repoPath, remotePath: remotePath)
        try await repo.detachHead()

        let branches = try await readBranches(repoPath: repoPath)

        XCTAssertEqual(branches.map { $0.name }, ["main"], "Only real branches should be listed")
        XCTAssertFalse(branches.contains { $0.name.contains("HEAD") })

        let detachedAt = try await readDetachedHead(repoPath: repoPath)
        XCTAssertNotNil(detachedAt, "The detached commit should be reported separately")
    }

    func testHeadOnABranchIsNotReportedAsDetached() async throws {
        try await GitFixture.makeRepoWithUpstream(at: repoPath, remotePath: remotePath)

        let detachedAt = try await readDetachedHead(repoPath: repoPath)

        XCTAssertNil(detachedAt)
    }

    // MARK: - Working tree

    func testUntrackedAndModifiedFilesAreCountedSeparately() async throws {
        let repo = try await GitFixture.makeRepoWithUpstream(at: repoPath, remotePath: remotePath)
        try "changed".write(toFile: "\(repoPath)/initial.txt", atomically: true, encoding: .utf8)
        try repo.writeUncommittedChange(file: "brand-new.txt", content: "new")

        let state = try await readWorkingTreeState(repoPath: repoPath)

        XCTAssertEqual(state.unstaged, 1)
        XCTAssertEqual(state.untracked, 1)
        XCTAssertEqual(state.staged, 0)
        XCTAssertTrue(state.isDirty)
    }

    func testStagedFilesAreCounted() async throws {
        let repo = try await GitFixture.makeRepoWithUpstream(at: repoPath, remotePath: remotePath)
        try repo.writeUncommittedChange(file: "staged.txt", content: "staged")
        try await repo.run("add -A")

        let state = try await readWorkingTreeState(repoPath: repoPath)

        XCTAssertEqual(state.staged, 1)
        XCTAssertEqual(state.untracked, 0)
    }

    func testCleanTreeReportsNothing() async throws {
        try await GitFixture.makeRepoWithUpstream(at: repoPath, remotePath: remotePath)

        let state = try await readWorkingTreeState(repoPath: repoPath)

        XCTAssertEqual(state, .clean)
        XCTAssertFalse(state.isDirty)
    }

    /// Stashed work made a repo look completely clean.
    func testStashesAreCounted() async throws {
        let repo = try await GitFixture.makeRepoWithUpstream(at: repoPath, remotePath: remotePath)
        try repo.writeUncommittedChange(file: "wip.txt", content: "wip")
        try await repo.stashChanges()

        let state = try await readWorkingTreeState(repoPath: repoPath)

        XCTAssertEqual(state.stashes, 1)
        XCTAssertFalse(state.isDirty, "Stashing takes the change out of the working tree")
        XCTAssertTrue(state.hasStashes)
    }

    // MARK: - Whole-repo summary

    func testSummaryCombinesWorkingTreeAndBranchState() async throws {
        let repo = try await GitFixture.makeRepoWithUpstream(at: repoPath, remotePath: remotePath)
        try await repo.commit(file: "ahead.txt", content: "ahead", message: "Unpushed commit")
        try await repo.createBranch("scratch")
        try repo.writeUncommittedChange()

        let summary = try await inspectRepo(at: repoPath, category: .publicRepo)

        XCTAssertTrue(summary.workingTree.isDirty)
        XCTAssertEqual(summary.totalAhead, 1)
        XCTAssertEqual(summary.localOnlyBranches.map { $0.name }, ["scratch"])
        XCTAssertTrue(summary.needsReport)
        XCTAssertEqual(summary.description, "MAL")
        XCTAssertEqual(summary.category, .publicRepo)
    }

    /// One repo can hold a tracked branch that is ahead and a branch with no upstream, so the
    /// unpushed and local-only indicators are not exclusive. The old help text claimed they were,
    /// and a test asserted it.
    func testAheadAndLocalOnlyCanBothApplyToOneRepo() async throws {
        let repo = try await GitFixture.makeRepoWithUpstream(at: repoPath, remotePath: remotePath)
        try await repo.commit(file: "ahead.txt", content: "ahead", message: "Unpushed commit")
        try await repo.createBranch("no-upstream")

        let summary = try await inspectRepo(at: repoPath, category: .publicRepo)

        XCTAssertTrue(summary.flags.contains(.ahead))
        XCTAssertTrue(summary.flags.contains(.localOnlyBranches))
    }

    func testCleanRepoNeedsNoReport() async throws {
        try await GitFixture.makeRepoWithUpstream(at: repoPath, remotePath: remotePath)

        let summary = try await inspectRepo(at: repoPath, category: .publicRepo)

        XCTAssertFalse(summary.needsReport)
        XCTAssertEqual(summary.description, "")
        XCTAssertEqual(summary.states, [.clean])
    }

    func testDiffstatIsCollectedForDirtyReposOnly() async throws {
        let repo = try await GitFixture.makeRepoWithUpstream(at: repoPath, remotePath: remotePath)

        let clean = try await inspectRepo(at: repoPath, category: .publicRepo)
        XCTAssertNil(clean.diffstat, "There is nothing to show for a clean tree")

        try repo.writeUncommittedChange()
        let dirty = try await inspectRepo(at: repoPath, category: .publicRepo)
        XCTAssertNotNil(dirty.diffstat, "The renderers cannot run git, so this must be collected here")
    }

    func testFetchFailureIsRecordedRatherThanThrown() async throws {
        let repo = try await GitFixture.makeRepoWithUpstream(at: repoPath, remotePath: remotePath)
        // Point the remote at a path that does not exist, so fetching cannot work.
        try await repo.run("remote set-url origin \(quoted(temporaryDirectory.appending("gone.git")))")

        let summary = try await inspectRepo(
            at: repoPath,
            category: .publicRepo,
            options: RepoInspectionOptions(fetch: true)
        )

        XCTAssertTrue(summary.fetchFailed, "One unreachable remote must not end the scan")
        XCTAssertTrue(summary.flags.contains(.fetchFailed))
    }
}
