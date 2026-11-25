import XCTest
import Foundation
@testable import forgery_lib

/**
 * Covers the two renderers.
 *
 * Both take a hand-built `StatusReport` and run no git commands, which is the point of moving
 * rendering out of the command: the empty "Forked Repositories" group went unnoticed because
 * nothing could assert on rendered output.
 */
class ReportRendererTests: XCTestCase {

    // MARK: - Fixtures

    private func summary(
        path: String,
        category: RepoCategory,
        owner: String? = nil,
        workingTree: WorkingTreeState = .clean,
        branches: [BranchInfo] = [],
        detachedAt: String? = nil,
        fetchFailed: Bool = false,
        diffstat: String? = nil
    ) -> RepoSummary {
        RepoSummary(
            path: path,
            category: category,
            owner: owner,
            name: (path as NSString).lastPathComponent,
            workingTree: workingTree,
            branches: branches,
            detachedAt: detachedAt,
            fetchFailed: fetchFailed,
            diffstat: diffstat
        )
    }

    private func report(_ repos: [RepoSummary], didFetch: Bool = true) -> StatusReport {
        StatusReport(repos: repos, didFetch: didFetch, generatedAt: Date(timeIntervalSince1970: 0))
    }

    // MARK: - Terminal

    func testTerminalReportGroupsForkedRepositories() {
        let output = renderTerminalReport(report([
            summary(
                path: "/base/user/me/repos/forked/apache/kafka",
                category: .forkedRepo,
                owner: "apache",
                branches: [BranchInfo(name: "main", upstream: "origin/main", ahead: 2)]
            )
        ]))

        // Forked repos were collected, the section title printed, and then nothing appeared under
        // it, because the group filtered on "forks" while the clone path uses "forked".
        XCTAssertTrue(output.contains("Forked Repositories:"))
        XCTAssertTrue(output.contains("/base/user/me/repos/forked/apache/kafka"))
    }

    func testTerminalReportGroupsForkedGists() {
        let output = renderTerminalReport(report([
            summary(
                path: "/base/user/me/gists/forked/someone/abc123",
                category: .forkedGist,
                owner: "someone",
                workingTree: WorkingTreeState(unstaged: 1)
            )
        ]))

        XCTAssertTrue(output.contains("Forked Gists:"))
        XCTAssertTrue(output.contains("abc123"))
    }

    func testTerminalBranchLinesUseArrowsForAheadAndBehind() {
        let output = renderTerminalReport(report([
            summary(
                path: "/base/repos/public/forgery",
                category: .publicRepo,
                branches: [
                    BranchInfo(name: "main", isCurrent: true, upstream: "origin/main", ahead: 3, behind: 2),
                    BranchInfo(name: "feature-x", upstream: "origin/feature-x", ahead: 1),
                    BranchInfo(name: "old-thing", upstream: "origin/old-thing", behind: 4),
                    BranchInfo(name: "scratch"),
                ]
            )
        ]))

        XCTAssertTrue(output.contains("↑3 ↓2"), "A diverged branch shows both counts")
        XCTAssertTrue(output.contains("↑1"))
        XCTAssertTrue(output.contains("↓4"))
        XCTAssertTrue(output.contains("(no upstream)"))
        XCTAssertTrue(output.contains("* main"), "The current branch is marked")
    }

    func testTerminalReportHidesUpToDateBranchesUnlessAskedForThem() {
        let repo = summary(
            path: "/base/repos/public/forgery",
            category: .publicRepo,
            branches: [
                BranchInfo(name: "main", isCurrent: true, upstream: "origin/main", ahead: 1),
                BranchInfo(name: "release", upstream: "origin/release"),
            ]
        )

        let terse = renderTerminalReport(report([repo]))
        XCTAssertFalse(terse.contains("release"), "An up to date branch is not worth a line by default")

        let full = renderTerminalReport(report([repo]), options: TerminalReportOptions(showAllBranches: true))
        XCTAssertTrue(full.contains("release"))
        XCTAssertTrue(full.contains("✓"))
    }

    func testTerminalReportHidesCleanReposUnlessAskedForThem() {
        let repos = [
            summary(path: "/base/repos/public/dirty", category: .publicRepo, workingTree: WorkingTreeState(unstaged: 1)),
            summary(path: "/base/repos/public/spotless", category: .publicRepo),
        ]

        let terse = renderTerminalReport(report(repos))
        XCTAssertFalse(terse.contains("spotless"))
        XCTAssertTrue(terse.contains("dirty"))

        let full = renderTerminalReport(report(repos), options: TerminalReportOptions(showCleanRepos: true))
        XCTAssertTrue(full.contains("spotless"))
        XCTAssertTrue(full.contains("[✓]"), "A clean repo gets a tick rather than an empty tag")
    }

    func testTerminalSummaryCountsAndRanks() {
        let output = renderTerminalReport(report([
            summary(path: "/base/repos/public/a", category: .publicRepo,
                    branches: [BranchInfo(name: "main", upstream: "origin/main", ahead: 12)]),
            summary(path: "/base/repos/public/b", category: .publicRepo,
                    branches: [BranchInfo(name: "main", upstream: "origin/main", ahead: 3)]),
            summary(path: "/base/repos/public/c", category: .publicRepo),
        ]))

        XCTAssertTrue(output.contains("3 repos scanned, 2 need attention"))
        XCTAssertTrue(output.contains("Most unpushed commits:"))
        XCTAssertTrue(output.contains("↑12"))
        XCTAssertTrue(output.contains("Needing attention by type:"))
        XCTAssertTrue(output.contains("█"), "Counts are drawn as bars")

        let ranking = output.components(separatedBy: "Most unpushed commits:")[1]
        XCTAssertLessThan(
            ranking.range(of: "↑12")!.lowerBound,
            ranking.range(of: "↑3")!.lowerBound,
            "The worst offender is listed first"
        )
    }

    func testTerminalReportNotesStaleRemoteDataWhenNotFetching() {
        let withoutFetch = renderTerminalReport(report([], didFetch: false))
        XCTAssertTrue(withoutFetch.contains("--fetch"))

        let withFetch = renderTerminalReport(report([], didFetch: true))
        XCTAssertFalse(withFetch.contains("--fetch"))
    }

    func testTerminalReportReportsFetchFailures() {
        let output = renderTerminalReport(report([
            summary(path: "/base/repos/public/unreachable", category: .publicRepo, fetchFailed: true)
        ]))

        XCTAssertTrue(output.contains("1 repo could not be fetched."))
        XCTAssertTrue(output.contains("fetch failed"))
    }

    func testTerminalReportShowsDetachedHeadAndStashes() {
        let output = renderTerminalReport(report([
            summary(
                path: "/base/repos/public/odd",
                category: .publicRepo,
                workingTree: WorkingTreeState(stashes: 2),
                detachedAt: "99439eb"
            )
        ]))

        XCTAssertTrue(output.contains("HEAD is detached at 99439eb"))
        XCTAssertTrue(output.contains("2 stashed changes"))
    }

    func testTerminalReportSaysSoWhenEverythingIsClean() {
        let output = renderTerminalReport(report([
            summary(path: "/base/repos/public/spotless", category: .publicRepo)
        ]))

        XCTAssertTrue(output.contains("All repositories are clean and up to date!"))
    }

    func testTerminalLegendOnlyExplainsIndicatorsThatAppear() {
        let output = renderTerminalReport(report([
            summary(path: "/base/repos/public/a", category: .publicRepo, workingTree: WorkingTreeState(unstaged: 1))
        ]))

        XCTAssertTrue(output.contains("M  modified working tree"))
        XCTAssertFalse(output.contains("H  detached HEAD"), "Unused letters are left out of the legend")
    }

    // MARK: - HTML

    func testHTMLReportIsSelfContained() {
        let html = renderHTMLReport(report([
            summary(path: "/base/repos/public/forgery", category: .publicRepo,
                    branches: [BranchInfo(name: "main", isCurrent: true, upstream: "origin/main", ahead: 3, behind: 2)])
        ]))

        XCTAssertTrue(html.hasPrefix("<!doctype html>"))
        XCTAssertTrue(html.contains("<style>"))
        XCTAssertTrue(html.contains("<script>"))
        // The file has to open with no network, so nothing may be requested from elsewhere.
        XCTAssertFalse(html.contains("http://"))
        XCTAssertFalse(html.contains("https://"))
        XCTAssertFalse(html.contains("<link"))
        XCTAssertFalse(html.contains("src="))
    }

    func testHTMLReportSupportsBothColourSchemes() {
        let html = renderHTMLReport(report([
            summary(path: "/base/repos/public/a", category: .publicRepo, workingTree: WorkingTreeState(unstaged: 1))
        ]))

        XCTAssertTrue(html.contains(":root {"), "The light palette is defined unconditionally")
        XCTAssertTrue(html.contains("prefers-color-scheme: dark"))
    }

    func testHTMLReportIncludesBranchDetailAndCounts() {
        let html = renderHTMLReport(report([
            summary(
                path: "/base/repos/public/forgery",
                category: .publicRepo,
                branches: [
                    BranchInfo(name: "main", isCurrent: true, upstream: "origin/main", ahead: 3, behind: 2),
                    BranchInfo(name: "scratch"),
                ]
            )
        ]))

        XCTAssertTrue(html.contains("origin/main"))
        XCTAssertTrue(html.contains("↑3"))
        XCTAssertTrue(html.contains("↓2"))
        XCTAssertTrue(html.contains("no upstream"))
        XCTAssertTrue(html.contains("data-ahead=\"3\""))
        XCTAssertTrue(html.contains("data-behind=\"2\""))
    }

    func testHTMLReportEscapesRepoAndBranchNames() {
        let html = renderHTMLReport(report([
            summary(
                path: "/base/repos/public/<script>alert(1)</script>",
                category: .publicRepo,
                branches: [BranchInfo(name: "feature/\"quoted\" & <angled>")]
            )
        ]))

        XCTAssertFalse(html.contains("<script>alert(1)</script>"), "A repo name must not become markup")
        XCTAssertTrue(html.contains("&lt;script&gt;alert(1)&lt;/script&gt;"))
        XCTAssertTrue(html.contains("&amp;"))
        XCTAssertTrue(html.contains("&quot;"))
    }

    func testHTMLReportNotesStaleRemoteData() {
        XCTAssertTrue(renderHTMLReport(report([], didFetch: false)).contains("--fetch"))
        XCTAssertFalse(renderHTMLReport(report([], didFetch: true)).contains("--fetch"))
    }

    func testHTMLReportSaysSoWhenEverythingIsClean() {
        let html = renderHTMLReport(report([
            summary(path: "/base/repos/public/spotless", category: .publicRepo)
        ]))

        XCTAssertTrue(html.contains("All repositories are clean and up to date."))
    }

    // MARK: - Rollup

    func testRollupCountsARepoInEveryStateItIsIn() {
        let rollup = report([
            summary(
                path: "/base/repos/public/busy",
                category: .publicRepo,
                workingTree: WorkingTreeState(unstaged: 1, stashes: 1),
                branches: [
                    BranchInfo(name: "main", upstream: "origin/main", ahead: 1, behind: 1),
                    BranchInfo(name: "scratch"),
                ]
            )
        ]).rollup()

        let states = Dictionary(uniqueKeysWithValues: rollup.byState.map { ($0.state, $0.count) })
        XCTAssertEqual(states[.modified], 1)
        XCTAssertEqual(states[.stashed], 1)
        XCTAssertEqual(states[.diverged], 1)
        XCTAssertEqual(states[.localOnly], 1)
        XCTAssertNil(states[.clean])
        XCTAssertEqual(rollup.needingAttention, 1)
    }

    func testRollupRankingsAreLimitedToTopCount() {
        let repos = (1...10).map { index in
            summary(path: "/base/repos/public/repo\(index)", category: .publicRepo,
                    branches: [BranchInfo(name: "main", upstream: "origin/main", ahead: index)])
        }

        XCTAssertEqual(report(repos).rollup(topCount: 3).topByAhead.count, 3)
        XCTAssertEqual(report(repos).rollup(topCount: 3).topByAhead.first?.totalAhead, 10)
    }
}
