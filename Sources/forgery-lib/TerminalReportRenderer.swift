import Foundation

/**
 * How much of the report to draw.
 */
public struct TerminalReportOptions: Sendable {
    /// List every local branch of a repo, not only the ones needing attention.
    public var showAllBranches: Bool

    /// List repos that have nothing to report, so the output is a full inventory.
    public var showCleanRepos: Bool

    /// Print the `git status` output collected for repos with a dirty tree.
    public var showDiffstat: Bool

    /// How many repos to rank in each "top offenders" list.
    public var topCount: Int

    /// Width to scale the rollup bars to.
    public var barWidth: Int

    public init(
        showAllBranches: Bool = false,
        showCleanRepos: Bool = false,
        showDiffstat: Bool = true,
        topCount: Int = 5,
        barWidth: Int = 24
    ) {
        self.showAllBranches = showAllBranches
        self.showCleanRepos = showCleanRepos
        self.showDiffstat = showDiffstat
        self.topCount = topCount
        self.barWidth = barWidth
    }
}

/**
 * Draws a report for a terminal.
 *
 * A pure function of the report: it runs no git commands and touches no disk, so it can be tested
 * on a hand-built `StatusReport`.
 */
public func renderTerminalReport(_ report: StatusReport, options: TerminalReportOptions = TerminalReportOptions()) -> String {
    var lines = [String]()

    let rollup = report.rollup(topCount: options.topCount)
    lines.append(contentsOf: renderSummary(rollup, options: options))

    if report.isEmpty && !options.showCleanRepos {
        lines.append("")
        lines.append("All repositories are clean and up to date!")
        lines.append(contentsOf: renderFooter(report))
        return lines.joined(separator: "\n")
    }

    lines.append("")
    lines.append(options.showCleanRepos ? "All repositories:" : "Repositories needing attention:")

    for category in RepoCategory.allCases {
        let repos = report.repos(in: category, includingClean: options.showCleanRepos)
        guard !repos.isEmpty else { continue }

        lines.append("")
        lines.append("  \(category.displayName):")
        for repo in repos {
            lines.append(contentsOf: renderRepo(repo, options: options))
        }
    }

    lines.append(contentsOf: renderLegend(for: report))
    lines.append(contentsOf: renderFooter(report))

    return lines.joined(separator: "\n")
}

// MARK: - Sections

private func renderSummary(_ rollup: StatusRollup, options: TerminalReportOptions) -> [String] {
    var lines = [String]()

    let repoWord = rollup.totalScanned == 1 ? "repo" : "repos"
    lines.append("Summary  (\(rollup.totalScanned) \(repoWord) scanned, \(rollup.needingAttention) need attention)")

    guard rollup.totalScanned > 0 else { return lines }

    let stateLabelWidth = rollup.byState.map { $0.state.displayName.count }.max() ?? 0
    for entry in rollup.byState {
        lines.append(barLine(
            label: entry.state.displayName,
            count: entry.count,
            max: rollup.maxStateCount,
            labelWidth: stateLabelWidth,
            barWidth: options.barWidth,
            // A clean repo is not a finding, so it gets a count without a bar.
            drawBar: entry.state != .clean
        ))
    }

    if !rollup.byCategory.isEmpty {
        lines.append("")
        lines.append("Needing attention by type:")
        let categoryLabelWidth = rollup.byCategory.map { $0.category.shortName.count }.max() ?? 0
        for entry in rollup.byCategory {
            lines.append(barLine(
                label: entry.category.shortName,
                count: entry.count,
                max: rollup.maxCategoryCount,
                labelWidth: categoryLabelWidth,
                barWidth: options.barWidth,
                drawBar: true
            ))
        }
    }

    if !rollup.topByAhead.isEmpty {
        lines.append("")
        lines.append("Most unpushed commits:")
        for repo in rollup.topByAhead {
            lines.append("  ↑\(repo.totalAhead)".padding(toLength: 7, withPad: " ", startingAt: 0) + repo.shortLabel)
        }
    }

    if !rollup.topByLocalOnly.isEmpty {
        lines.append("")
        lines.append("Most local-only branches:")
        for repo in rollup.topByLocalOnly {
            let count = repo.localOnlyBranches.count
            lines.append("  \(count)".padding(toLength: 7, withPad: " ", startingAt: 0) + repo.shortLabel)
        }
    }

    return lines
}

private func renderRepo(_ repo: RepoSummary, options: TerminalReportOptions) -> [String] {
    var lines = [String]()

    let tag = repo.description
    lines.append("    [\(tag.isEmpty ? "✓" : tag)] \(repo.displayPath)")

    if let detachedAt = repo.detachedAt {
        lines.append("        HEAD is detached at \(detachedAt)")
    }
    if repo.fetchFailed {
        lines.append("        fetch failed, remote comparisons below are out of date")
    }

    let branches = options.showAllBranches ? repo.branches : repo.branchesNeedingAttention
    if !branches.isEmpty {
        let nameWidth = branches.map { $0.name.count }.max() ?? 0
        for branch in branches {
            lines.append(renderBranch(branch, nameWidth: nameWidth))
        }
    }

    if repo.workingTree.hasStashes {
        let count = repo.workingTree.stashes
        lines.append("        \(count) stashed change\(count == 1 ? "" : "s")")
    }

    if options.showDiffstat, let diffstat = repo.diffstat, !diffstat.isEmpty {
        for line in diffstat.split(separator: "\n") {
            lines.append("        \(line)")
        }
    }

    return lines
}

private func renderBranch(_ branch: BranchInfo, nameWidth: Int) -> String {
    let marker = branch.isCurrent ? "*" : " "
    let name = branch.name.padding(toLength: max(nameWidth, branch.name.count), withPad: " ", startingAt: 0)

    var state: String
    if branch.upstreamGone {
        state = "(upstream gone)"
    } else if branch.isLocalOnly {
        state = "(no upstream)"
    } else if branch.ahead > 0 || branch.behind > 0 {
        var parts = [String]()
        if branch.ahead > 0 { parts.append("↑\(branch.ahead)") }
        if branch.behind > 0 { parts.append("↓\(branch.behind)") }
        state = parts.joined(separator: " ")
    } else {
        state = "✓"
    }

    if branch.isCheckedOutElsewhere {
        state += " (worktree)"
    }

    return "      \(marker) \(name)  \(state)"
}

private func renderLegend(for report: StatusReport) -> [String] {
    var present = Set<Character>()
    for repo in report.reportingRepos {
        present.formUnion(repo.description)
    }
    let entries = RepoStatusFlags.legend.filter { present.contains($0.letter) }
    guard !entries.isEmpty else { return [] }

    var lines = ["", "Legend:"]
    for entry in entries {
        lines.append("  \(entry.letter)  \(entry.meaning)")
    }
    return lines
}

private func renderFooter(_ report: StatusReport) -> [String] {
    var lines = [String]()

    if !report.didFetch {
        lines.append("")
        lines.append("Remote comparisons are as of your last fetch. Use --fetch for current data.")
    }

    let failures = report.fetchFailures.count
    if failures > 0 {
        lines.append("\(failures) repo\(failures == 1 ? "" : "s") could not be fetched.")
    }

    return lines
}

// MARK: - Helpers

private func barLine(label: String, count: Int, max maxCount: Int, labelWidth: Int, barWidth: Int, drawBar: Bool) -> String {
    let paddedLabel = label.padding(toLength: max(labelWidth, label.count), withPad: " ", startingAt: 0)
    let paddedCount = String(count).leftPadded(to: 5)
    guard drawBar, maxCount > 0, count > 0 else {
        return "  \(paddedLabel)\(paddedCount)"
    }
    let filled = max(1, Int((Double(count) / Double(maxCount) * Double(barWidth)).rounded()))
    return "  \(paddedLabel)\(paddedCount)  \(String(repeating: "█", count: filled))"
}

extension String {
    func leftPadded(to width: Int) -> String {
        count >= width ? self : String(repeating: " ", count: width - count) + self
    }
}

extension RepoSummary {
    /// The full path, so it can be copied straight into a `cd`.
    public var displayPath: String { path }

    /// A compact label for rollups, where the full path is too wide.
    public var shortLabel: String {
        if let owner { return "\(owner)/\(name)" }
        return name
    }
}
