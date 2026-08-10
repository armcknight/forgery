import Foundation
import GitKit
import ShellKit

/// Set default branch to pull from upstream remote but push to fork remote
func setDefaultForkBranchRemotes(_ git: Git) throws {
    let defaultBranch = try git.run(.revParse(abbrevRef: true, revision: "fork/HEAD")).replacingOccurrences(of: "refs/remotes/fork/", with: "")
    try git.run(.writeConfig(name: "branch.\(defaultBranch).remote", value: "upstream"))
    try git.run(.writeConfig(name: "branch.\(defaultBranch).pushRemote", value: "fork"))
}

/// Clones a repo and then pulls down any submodules it may have.
func cloneRepo(repoName: String, sshURL: String, cloneRoot: String) throws {
    let repoPath = ("\(cloneRoot)/\(repoName)" as NSString).expandingTildeInPath
    guard !FileManager.default.fileExists(atPath: repoPath) else {
        throw ForgeryError.Clone.Repo.alreadyCloned
    }
    
    logger.info("Cloning \(sshURL) into \(repoName)...")
    var git = Git(path: cloneRoot)
    try git.run(.clone(url: sshURL, dirName: repoName))
    if FileManager.default.fileExists(atPath: "\(repoPath)/.gitmodules") {
        git = Git(path: repoPath)
        try git.run(.submoduleUpdate(init: true, recursive: true))
    }
}

func remoteRepoExists(repoSSHURL: String) -> Bool {
    do {
        try Git().run(.lsRemote(url: repoSSHURL, limitToHeads: true))
        return true
    } catch {
        return false
    }
}

public struct IndexState: OptionSet {
    public var rawValue: UInt
    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    public static let clean = IndexState(rawValue: 1 << 0)
    public static let dirtyIndex = IndexState(rawValue: 1 << 1)
    public static let pushedWIP = IndexState(rawValue: 1 << 2)
    public static let localOnlyBranches = IndexState(rawValue: 1 << 3)
}

public enum BranchStatus {
    case upToDate                           // Branch is clean and up to date with upstream
    case unpushedCommits(count: Int)        // Branch has commits that haven't been pushed to upstream
    case localOnly                          // Branch has no upstream configured
    case noUpstream                         // Branch exists but no upstream is configured (alias for localOnly)
    
    var isLocalOnly: Bool {
        switch self {
        case .localOnly, .noUpstream:
            return true
        default:
            return false
        }
    }
    
    var hasUnpushedCommits: Bool {
        switch self {
        case .unpushedCommits:
            return true
        default:
            return false
        }
    }
}

public struct BranchInfo {
    public let name: String
    public let status: BranchStatus
    public let isCurrentBranch: Bool
}

public struct RepositoryBranchInfo {
    public let branches: [BranchInfo]
    
    public var hasLocalOnlyBranches: Bool {
        branches.contains { $0.status.isLocalOnly }
    }
    
    public var hasUnpushedCommits: Bool {
        branches.contains { $0.status.hasUnpushedCommits }
    }
    
    public var localOnlyBranches: [BranchInfo] {
        branches.filter { $0.status.isLocalOnly }
    }
    
    public var branchesWithUnpushedCommits: [BranchInfo] {
        branches.filter { $0.status.hasUnpushedCommits }
    }
}

public struct RepoSummary {
    public let path: String
    public let status: IndexState
    public let repositoryBranchInfo: RepositoryBranchInfo
    
    // Legacy properties for backward compatibility
    public var branchInfo: [(branch: String, unpushedCommits: Int)] {
        repositoryBranchInfo.branchesWithUnpushedCommits.compactMap { branch in
            if case .unpushedCommits(let count) = branch.status {
                return (branch: branch.name, unpushedCommits: count)
            }
            return nil
        }
    }
    
    public var localOnlyBranches: [String] {
        repositoryBranchInfo.localOnlyBranches.map { $0.name }
    }

    public var needsReport: Bool {
        status.contains(.dirtyIndex) || status.contains(.pushedWIP) || 
        repositoryBranchInfo.hasUnpushedCommits || repositoryBranchInfo.hasLocalOnlyBranches
    }
}

extension RepoSummary: CustomStringConvertible {
    public var description: String {
        var string = ""
        if status.contains(IndexState.pushedWIP) {
            string += "W"
        } else if status.contains(IndexState.dirtyIndex) {
            string += "M"
        }
        if !branchInfo.isEmpty {
            string += "P"
        }
        if status.contains(IndexState.localOnlyBranches) {
            string += "L"
        }
        return string
    }
}

public func checkWorkingIndex(repoPath: String, pushWIPChanges: Bool) throws -> IndexState {
    let fullRepoPath = (repoPath as NSString).expandingTildeInPath
    logger.debug("Checking working index status of \(fullRepoPath)...")
    let git = Git(path: fullRepoPath)

    let clean = try git.run(.status(short: true)).isEmpty

    guard !clean else { return .clean }

    guard !pushWIPChanges else {
        try saveWIPChanges(repoPath: fullRepoPath)
        return .pushedWIP
    }

    return .dirtyIndex
}

public func summarizeStatus(repoPath: String, pushWIPChanges: Bool) throws -> RepoSummary {
    var state = try checkWorkingIndex(repoPath: repoPath, pushWIPChanges: pushWIPChanges)
    let repositoryBranchInfo = try getBranchInfo(repoPath: repoPath)
    
    // Add local-only branches indicator if any exist
    if repositoryBranchInfo.hasLocalOnlyBranches {
        state.insert(.localOnlyBranches)
    }
    
    return RepoSummary(path: repoPath, status: state, repositoryBranchInfo: repositoryBranchInfo)
}

func saveWIPChanges(repoPath: String) throws {
    let git = Git(path: repoPath)

    let branchName = "forgery-wip"
    try git.run(.checkout(branch: branchName, create: true))
    try git.run(.addAll)

    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    let timestamp = dateFormatter.string(from: Date())
    let commitMessage = "wip on \(timestamp)"
    try git.run(.commit(message: commitMessage))

    // TODO: if this is a fork, push to remote named "fork" instead of "origin"
    try git.run(.push())

    print("  ✓ Saved WIP changes to branch '\(branchName)'")
}

public func diffstat(repoPath: String) throws -> String {
    let git = Git(path: repoPath)
    return try git.run(.status())
}

public func getBranchInfo(repoPath: String) throws -> RepositoryBranchInfo {
    let git = Git(path: repoPath)
    let branchesOutput = try git.run(.raw("branch"))
    let branchLines = branchesOutput.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
    
    var branches: [BranchInfo] = []

    for branchLine in branchLines {
        let isCurrentBranch = branchLine.hasPrefix("* ")
        let branchName = branchLine.replacingOccurrences(of: "* ", with: "")
        
        // Check each branch's status individually
        let branchStatus: BranchStatus
        
        do {
            // Check for upstream without checking out - use branch-specific revision syntax
            let unpushedCommitsOutput = try git.run(.revList(count: true, revisions: "\(branchName)@{u}..\(branchName)"))
            let unpushedCommits = Int(unpushedCommitsOutput.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            
            if unpushedCommits > 0 {
                branchStatus = .unpushedCommits(count: unpushedCommits)
            } else {
                branchStatus = .upToDate
            }
        } catch {
            // If there's no upstream configured, this is a local-only branch
            logger.debug("No upstream configured for branch '\(branchName)': \(error)")
            branchStatus = .localOnly
        }
        
        branches.append(BranchInfo(name: branchName, status: branchStatus, isCurrentBranch: isCurrentBranch))
    }

    return RepositoryBranchInfo(branches: branches)
}
