import Foundation

/**
 * Everything a scan found, plus the aggregates the renderers draw.
 *
 * This is the only input the renderers take. They must stay pure functions of it, because a
 * renderer that runs git cannot be tested.
 */
public struct StatusReport: Sendable {
    /// Every repo that was scanned, including the ones with nothing to report.
    public let repos: [RepoSummary]

    /// Whether the scan fetched from the remotes first. When false, all remote comparisons are
    /// only as fresh as the last fetch the user ran.
    public let didFetch: Bool

    public let generatedAt: Date

    public init(repos: [RepoSummary], didFetch: Bool, generatedAt: Date = Date()) {
        self.repos = repos
        self.didFetch = didFetch
        self.generatedAt = generatedAt
    }

    /// Repos with something worth showing the user.
    public var reportingRepos: [RepoSummary] { repos.filter { $0.needsReport } }

    /// Repos whose fetch did not complete, so their remote data is old.
    public var fetchFailures: [RepoSummary] { repos.filter { $0.fetchFailed } }

    public var isEmpty: Bool { reportingRepos.isEmpty }

    /// The repos to show for a category, sorted by name.
    public func repos(in category: RepoCategory, includingClean: Bool = false) -> [RepoSummary] {
        let candidates = includingClean ? repos : reportingRepos
        return candidates
            .filter { $0.category == category }
            .sorted { ($0.owner ?? "", $0.name) < ($1.owner ?? "", $1.name) }
    }

    /**
     * Counts and rankings drawn above the per-repo listing.
     *
     * - parameter topCount: how many repos to list in each "top offenders" ranking.
     */
    public func rollup(topCount: Int = 5) -> StatusRollup {
        var stateCounts = [RepoState: Int]()
        for repo in repos {
            for state in repo.states {
                stateCounts[state, default: 0] += 1
            }
        }

        var categoryCounts = [RepoCategory: Int]()
        for repo in reportingRepos {
            categoryCounts[repo.category, default: 0] += 1
        }

        let topByAhead = repos
            .filter { $0.totalAhead > 0 }
            .sorted { $0.totalAhead > $1.totalAhead }
            .prefix(topCount)

        let topByLocalOnly = repos
            .filter { !$0.localOnlyBranches.isEmpty }
            .sorted { $0.localOnlyBranches.count > $1.localOnlyBranches.count }
            .prefix(topCount)

        return StatusRollup(
            totalScanned: repos.count,
            needingAttention: reportingRepos.count,
            byState: RepoState.allCases.compactMap { state in
                guard let count = stateCounts[state], count > 0 else { return nil }
                return StateCount(state: state, count: count)
            },
            byCategory: RepoCategory.allCases.compactMap { category in
                guard let count = categoryCounts[category], count > 0 else { return nil }
                return CategoryCount(category: category, count: count)
            },
            topByAhead: Array(topByAhead),
            topByLocalOnly: Array(topByLocalOnly)
        )
    }
}

public struct StateCount: Sendable {
    public let state: RepoState
    public let count: Int
}

public struct CategoryCount: Sendable {
    public let category: RepoCategory
    public let count: Int
}

/**
 * The aggregates shown above the per-repo listing, in both the terminal and the HTML report.
 */
public struct StatusRollup: Sendable {
    public let totalScanned: Int
    public let needingAttention: Int

    /// How many repos are in each state. A repo in several states is counted in each of them, so
    /// these do not sum to `totalScanned`.
    public let byState: [StateCount]

    /// How many repos needing attention are in each category.
    public let byCategory: [CategoryCount]

    /// Repos holding the most commits no remote has.
    public let topByAhead: [RepoSummary]

    /// Repos with the most branches that have no upstream.
    public let topByLocalOnly: [RepoSummary]

    /// The largest state count, for scaling bars.
    public var maxStateCount: Int { byState.map { $0.count }.max() ?? 0 }

    /// The largest category count, for scaling bars.
    public var maxCategoryCount: Int { byCategory.map { $0.count }.max() ?? 0 }
}
