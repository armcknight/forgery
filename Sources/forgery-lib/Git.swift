import Foundation
import GitKit
import ShellKit

/// Set default branch to pull from upstream remote but push to fork remote
func setDefaultForkBranchRemotes(_ git: Git) throws {
    let defaultBranch = try git.run(.revParse(abbrevRef: "fork/HEAD")).replacingOccurrences(of: "refs/remotes/fork/", with: "")
    try git.run(.config(name: "branch.\(defaultBranch).remote", value: "upstream"))
    try git.run(.config(name: "branch.\(defaultBranch).pushRemote", value: "fork"))
}

/// Clones a repo and then pulls down any submodules it may have.
func cloneRepo(repoName: String, sshURL: String, cloneRoot: String) throws {
    let escapedRepoName = repoName.replacingOccurrences(of: " ", with: "\\ ")
    let repoPath = ("\(cloneRoot)/\(escapedRepoName)" as NSString).expandingTildeInPath
    guard !FileManager.default.fileExists(atPath: repoPath) else {
        throw ForgeryError.Clone.Repo.alreadyCloned
    }
    
    logger.info("Cloning \(sshURL) into \(escapedRepoName)...")
    var git = Git(path: cloneRoot)
    try git.run(.clone(url: sshURL, dirName: escapedRepoName))
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
}

public struct RepoSummary {
    public let path: String
    public let status: IndexState
    public let branchInfo: [(branch: String, unpushedCommits: Int)]

    public var needsReport: Bool {
        status.contains(.dirtyIndex) || status.contains(.pushedWIP) || !branchInfo.isEmpty
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
    let state = try checkWorkingIndex(repoPath: repoPath, pushWIPChanges: pushWIPChanges)
    let branchInfo = try getLocalBranchesWithUnpushedCommits(repoPath: repoPath)
    return RepoSummary(path: repoPath, status: state, branchInfo: branchInfo)
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

public func getLocalBranchesWithUnpushedCommits(repoPath: String) throws -> [(branch: String, unpushedCommits: Int)] {
    let git = Git(path: repoPath)
    let branchesOutput = try git.run(.raw("branch"))
    let branches = branchesOutput.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "* ", with: "") }

    var branchesWithUnpushedCommits: [(branch: String, unpushedCommits: Int)] = []

    for branch in branches {
        let unpushedCommitsOutput = try git.run(.revList(branch: branch, count: true, revisions: "@{u}.."))
        if let unpushedCommits = Int(unpushedCommitsOutput.trimmingCharacters(in: .whitespacesAndNewlines)), unpushedCommits > 0 {
            branchesWithUnpushedCommits.append((branch: branch, unpushedCommits: unpushedCommits))
        }
    }

    return branchesWithUnpushedCommits
}
