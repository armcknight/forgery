import Foundation

/**
 * The kind of tree a repo was found in. Assigned while scanning, from the root directory
 * being walked, rather than by matching substrings of the repo's path afterwards.
 */
public enum RepoCategory: String, CaseIterable, Sendable, Codable {
    case publicRepo
    case privateRepo
    case forkedRepo
    case starredRepo
    case publicGist
    case privateGist
    case forkedGist
    case starredGist

    public var displayName: String {
        switch self {
        case .publicRepo: return "Public Repositories"
        case .privateRepo: return "Private Repositories"
        case .forkedRepo: return "Forked Repositories"
        case .starredRepo: return "Starred Repositories"
        case .publicGist: return "Public Gists"
        case .privateGist: return "Private Gists"
        case .forkedGist: return "Forked Gists"
        case .starredGist: return "Starred Gists"
        }
    }

    /// Short label for rollups, where the full display name is too wide.
    public var shortName: String {
        switch self {
        case .publicRepo: return "public"
        case .privateRepo: return "private"
        case .forkedRepo: return "forked"
        case .starredRepo: return "starred"
        case .publicGist: return "public gists"
        case .privateGist: return "private gists"
        case .forkedGist: return "forked gists"
        case .starredGist: return "starred gists"
        }
    }

    /**
     * Whether clones under this category's root sit one level deeper, under the login of the
     * repo's owner.
     *
     * Starred and forked trees hold other people's repos, so they are cloned as
     * `<root>/<owner>/<repo>` to keep names from colliding. See `GitHub.cloneForkedRepo` and
     * the starred clone roots in `GitHub.clone(...)`.
     */
    public var isOwnerNested: Bool {
        switch self {
        case .forkedRepo, .starredRepo, .forkedGist, .starredGist: return true
        case .publicRepo, .privateRepo, .publicGist, .privateGist: return false
        }
    }
}

/**
 * A local branch and how it relates to its upstream.
 *
 * Collected from `git for-each-ref refs/heads`, so a detached HEAD can never appear here, and
 * branches checked out in another worktree are identified rather than mistaken for something
 * else.
 */
public struct BranchInfo: Sendable, Codable, Equatable {
    public let name: String

    /// Whether this branch is HEAD of the repo being scanned.
    public let isCurrent: Bool

    /// Whether this branch is checked out in a different worktree of the same repo.
    public let isCheckedOutElsewhere: Bool

    /// The upstream this branch tracks, such as `origin/main`. Nil means no upstream is configured.
    public let upstream: String?

    /// Whether an upstream is configured but no longer exists on the remote.
    public let upstreamGone: Bool

    /// Commits on this branch that the upstream does not have.
    public let ahead: Int

    /// Commits on the upstream that this branch does not have.
    public let behind: Int

    public init(
        name: String,
        isCurrent: Bool = false,
        isCheckedOutElsewhere: Bool = false,
        upstream: String? = nil,
        upstreamGone: Bool = false,
        ahead: Int = 0,
        behind: Int = 0
    ) {
        self.name = name
        self.isCurrent = isCurrent
        self.isCheckedOutElsewhere = isCheckedOutElsewhere
        self.upstream = upstream
        self.upstreamGone = upstreamGone
        self.ahead = ahead
        self.behind = behind
    }

    public var isLocalOnly: Bool { upstream == nil }
    public var isAhead: Bool { ahead > 0 }
    public var isBehind: Bool { behind > 0 }
    public var isDiverged: Bool { ahead > 0 && behind > 0 }

    /// True when the branch is tracking an upstream and agrees with it.
    public var isUpToDate: Bool { upstream != nil && !upstreamGone && ahead == 0 && behind == 0 }

    /// True when there is something worth telling the user about this branch.
    public var needsAttention: Bool { !isUpToDate }
}

/**
 * The state of a repo's working tree and stash stack.
 */
public struct WorkingTreeState: Sendable, Codable, Equatable {
    public let staged: Int
    public let unstaged: Int
    public let untracked: Int
    public let stashes: Int

    public init(staged: Int = 0, unstaged: Int = 0, untracked: Int = 0, stashes: Int = 0) {
        self.staged = staged
        self.unstaged = unstaged
        self.untracked = untracked
        self.stashes = stashes
    }

    public static let clean = WorkingTreeState()

    public var isDirty: Bool { staged + unstaged + untracked > 0 }
    public var hasStashes: Bool { stashes > 0 }
    public var changedFileCount: Int { staged + unstaged + untracked }
}

/**
 * The conditions a repo can be in. One repo can be in several at once, which is why these are
 * flags and not a single case.
 */
public struct RepoStatusFlags: OptionSet, Sendable {
    public var rawValue: UInt
    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    /// Uncommitted work in the tree: staged, unstaged, or untracked.
    public static let modified = RepoStatusFlags(rawValue: 1 << 0)
    /// Entries on the stash stack.
    public static let stashed = RepoStatusFlags(rawValue: 1 << 1)
    /// A branch is ahead of its upstream but not behind it.
    public static let ahead = RepoStatusFlags(rawValue: 1 << 2)
    /// A branch is behind its upstream but not ahead of it.
    public static let behind = RepoStatusFlags(rawValue: 1 << 3)
    /// A branch is both ahead of and behind its upstream.
    public static let diverged = RepoStatusFlags(rawValue: 1 << 4)
    /// A branch has no upstream configured.
    public static let localOnlyBranches = RepoStatusFlags(rawValue: 1 << 5)
    /// A branch tracks an upstream that no longer exists on the remote.
    public static let upstreamGone = RepoStatusFlags(rawValue: 1 << 6)
    /// HEAD does not point at a branch.
    public static let detachedHead = RepoStatusFlags(rawValue: 1 << 7)
    /// Uncommitted work was committed to a WIP branch and pushed. Set by `sync`, not `status`.
    public static let pushedWIP = RepoStatusFlags(rawValue: 1 << 8)
    /// A requested fetch did not complete, so the remote data below is old.
    public static let fetchFailed = RepoStatusFlags(rawValue: 1 << 9)

    /// The letters shown in the `[...]` tag, in the order they are printed.
    static let displayOrder: [(RepoStatusFlags, Character)] = [
        (.pushedWIP, "W"),
        (.modified, "M"),
        (.stashed, "S"),
        (.ahead, "A"),
        (.behind, "B"),
        (.diverged, "D"),
        (.localOnlyBranches, "L"),
        (.upstreamGone, "G"),
        (.detachedHead, "H"),
        (.fetchFailed, "!"),
    ]

    /// Human readable meanings, for the legend printed with the report.
    public static let legend: [(letter: Character, meaning: String)] = [
        ("M", "modified working tree (staged, unstaged, or untracked)"),
        ("S", "stashed changes"),
        ("A", "a branch is ahead of its upstream"),
        ("B", "a branch is behind its upstream"),
        ("D", "a branch is diverged (ahead and behind)"),
        ("L", "a branch has no upstream"),
        ("G", "an upstream is gone from the remote"),
        ("H", "detached HEAD"),
        ("!", "fetch failed, so remote data is old"),
    ]
}

/**
 * Everything `status` found out about one repo.
 */
public struct RepoSummary: Sendable {
    /// Absolute path to the repo on disk.
    public let path: String

    /// The tree this repo was found in.
    public let category: RepoCategory

    /// The login the repo is filed under, for the starred and forked trees. Nil elsewhere.
    public let owner: String?

    /// The directory name of the repo.
    public let name: String

    public let workingTree: WorkingTreeState
    public let branches: [BranchInfo]

    /// The short commit HEAD points at, when HEAD is not on a branch.
    public let detachedAt: String?

    /// Whether a requested fetch failed for this repo.
    public let fetchFailed: Bool

    /// Whether `sync` committed and pushed the dirty tree to a WIP branch.
    public let pushedWIP: Bool

    /// Collected while scanning, because the renderers must not run git themselves.
    public let diffstat: String?

    public init(
        path: String,
        category: RepoCategory,
        owner: String? = nil,
        name: String,
        workingTree: WorkingTreeState,
        branches: [BranchInfo],
        detachedAt: String? = nil,
        fetchFailed: Bool = false,
        pushedWIP: Bool = false,
        diffstat: String? = nil
    ) {
        self.path = path
        self.category = category
        self.owner = owner
        self.name = name
        self.workingTree = workingTree
        self.branches = branches
        self.detachedAt = detachedAt
        self.fetchFailed = fetchFailed
        self.pushedWIP = pushedWIP
        self.diffstat = diffstat
    }

    public var isDetachedHead: Bool { detachedAt != nil }

    public var localOnlyBranches: [BranchInfo] { branches.filter { $0.isLocalOnly } }
    public var divergedBranches: [BranchInfo] { branches.filter { $0.isDiverged } }
    public var goneUpstreamBranches: [BranchInfo] { branches.filter { $0.upstreamGone } }

    /// Branches ahead of their upstream and not behind it.
    public var aheadBranches: [BranchInfo] { branches.filter { $0.isAhead && !$0.isBehind } }

    /// Branches behind their upstream and not ahead of it.
    public var behindBranches: [BranchInfo] { branches.filter { $0.isBehind && !$0.isAhead } }

    /// Branches worth printing when the report is not listing every branch.
    public var branchesNeedingAttention: [BranchInfo] { branches.filter { $0.needsAttention } }

    /// Total commits this repo holds that no remote has.
    public var totalAhead: Int { branches.reduce(0) { $0 + $1.ahead } }

    /// Total commits the remotes hold that this repo does not.
    public var totalBehind: Int { branches.reduce(0) { $0 + $1.behind } }

    public var flags: RepoStatusFlags {
        var flags = RepoStatusFlags()
        if pushedWIP { flags.insert(.pushedWIP) }
        if workingTree.isDirty { flags.insert(.modified) }
        if workingTree.hasStashes { flags.insert(.stashed) }
        if !divergedBranches.isEmpty { flags.insert(.diverged) }
        if !aheadBranches.isEmpty { flags.insert(.ahead) }
        if !behindBranches.isEmpty { flags.insert(.behind) }
        if !localOnlyBranches.isEmpty { flags.insert(.localOnlyBranches) }
        if !goneUpstreamBranches.isEmpty { flags.insert(.upstreamGone) }
        if isDetachedHead { flags.insert(.detachedHead) }
        if fetchFailed { flags.insert(.fetchFailed) }
        return flags
    }

    /// True when this repo has anything the user should look at.
    public var needsReport: Bool {
        // A detached HEAD or a failed fetch alone is not work, but the user still wants to know.
        !flags.isEmpty
    }

    /// The states this repo counts towards in the rollup.
    public var states: [RepoState] {
        var states = [RepoState]()
        if workingTree.isDirty { states.append(.modified) }
        if workingTree.hasStashes { states.append(.stashed) }
        if !aheadBranches.isEmpty { states.append(.ahead) }
        if !behindBranches.isEmpty { states.append(.behind) }
        if !divergedBranches.isEmpty { states.append(.diverged) }
        if !localOnlyBranches.isEmpty { states.append(.localOnly) }
        if !goneUpstreamBranches.isEmpty { states.append(.upstreamGone) }
        if isDetachedHead { states.append(.detached) }
        if states.isEmpty { states.append(.clean) }
        return states
    }
}

extension RepoSummary: CustomStringConvertible {
    /// The letters shown in the `[...]` tag before the repo path.
    public var description: String {
        let flags = self.flags
        return String(RepoStatusFlags.displayOrder.compactMap { flags.contains($0.0) ? $0.1 : nil })
    }
}

/**
 * A condition repos are counted by in the rollup. Distinct from `RepoStatusFlags` because a repo
 * with nothing to report counts as `clean` here, and because `pushedWIP` is a `sync` concern.
 */
public enum RepoState: String, CaseIterable, Sendable {
    case modified
    case stashed
    case ahead
    case behind
    case diverged
    case localOnly
    case upstreamGone
    case detached
    case clean

    public var displayName: String {
        switch self {
        case .modified: return "modified"
        case .stashed: return "stashed"
        case .ahead: return "ahead"
        case .behind: return "behind"
        case .diverged: return "diverged"
        case .localOnly: return "local-only"
        case .upstreamGone: return "gone upstream"
        case .detached: return "detached HEAD"
        case .clean: return "clean"
        }
    }
}
