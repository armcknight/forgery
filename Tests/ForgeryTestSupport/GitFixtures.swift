import Foundation
import GitKit
import forgery_lib

/**
 * Builds real git repositories on disk for tests to inspect.
 *
 * Every git invocation runs with the developer's global and system config switched off and with a
 * fixed identity, so a machine's `init.defaultBranch`, hooks, `commit.gpgsign` or
 * `url.*.insteadOf` rules cannot change what a test sees.
 */
public struct GitFixture {
    public let path: String

    public init(path: String) {
        self.path = path
    }

    /// Environment that isolates the fixture from the developer's git configuration.
    public static let isolatedEnvironment: [String: String] = [
        "GIT_CONFIG_GLOBAL": "/dev/null",
        "GIT_CONFIG_SYSTEM": "/dev/null",
        "GIT_AUTHOR_NAME": "Test User",
        "GIT_AUTHOR_EMAIL": "test@example.com",
        "GIT_COMMITTER_NAME": "Test User",
        "GIT_COMMITTER_EMAIL": "test@example.com",
        // Never let a fixture block waiting for credentials.
        "GIT_TERMINAL_PROMPT": "0",
    ]

    public var git: Git {
        Git(path: path, env: GitFixture.isolatedEnvironment)
    }

    @discardableResult
    public func run(_ command: String) async throws -> String {
        try await git.run(.raw(command))
    }

    // MARK: - Building repos

    /**
     * Creates a repository with one commit on `defaultBranch`.
     */
    @discardableResult
    public static func makeRepo(
        at path: String,
        defaultBranch: String = "main",
        file: String = "initial.txt",
        content: String = "initial content"
    ) async throws -> GitFixture {
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        let fixture = GitFixture(path: path)
        try await fixture.run("init -q -b \(defaultBranch)")
        try await fixture.commit(file: file, content: content, message: "Initial commit")
        return fixture
    }

    /// Creates a bare repository, for use as a remote.
    @discardableResult
    public static func makeBareRemote(at path: String) async throws -> GitFixture {
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        let fixture = GitFixture(path: path)
        try await fixture.run("init -q --bare")
        return fixture
    }

    /**
     * Creates a repository that tracks a bare remote, with `defaultBranch` pushed and its upstream
     * set.
     *
     * This is what makes ahead, behind, diverged and gone-upstream states reachable in a test. A
     * repo built without a remote has no upstream at all, so every branch in it is local-only.
     */
    @discardableResult
    public static func makeRepoWithUpstream(
        at path: String,
        remotePath: String,
        defaultBranch: String = "main"
    ) async throws -> GitFixture {
        try await makeBareRemote(at: remotePath)
        let repo = try await makeRepo(at: path, defaultBranch: defaultBranch)
        try await repo.run("remote add origin \(quoted(remotePath))")
        try await repo.run("push -q -u origin \(defaultBranch)")
        return repo
    }

    // MARK: - Changing repos

    /// Writes a file, stages everything, and commits.
    public func commit(file: String, content: String, message: String) async throws {
        try content.write(toFile: "\(path)/\(file)", atomically: true, encoding: .utf8)
        try await run("add -A")
        try await run("commit -q --no-gpg-sign -m \(quoted(message))")
    }

    /// Leaves an uncommitted change in the working tree.
    public func writeUncommittedChange(file: String = "modified.txt", content: String = "modified") throws {
        try content.write(toFile: "\(path)/\(file)", atomically: true, encoding: .utf8)
    }

    /// Creates a branch. It has no upstream until one is pushed.
    public func createBranch(_ name: String, checkout: Bool = false) async throws {
        try await run(checkout ? "checkout -q -b \(quoted(name))" : "branch \(quoted(name))")
    }

    public func checkout(_ revision: String) async throws {
        try await run("checkout -q \(quoted(revision))")
    }

    /// Puts HEAD on a commit rather than a branch.
    public func detachHead() async throws {
        try await run("checkout -q --detach HEAD")
    }

    /// Adds a worktree at `worktreePath` with `branch` checked out in it.
    public func addWorktree(at worktreePath: String, branch: String) async throws {
        try await run("worktree add -q \(quoted(worktreePath)) \(quoted(branch))")
    }

    public func stashChanges(message: String = "wip") async throws {
        try await run("stash push -q -u -m \(quoted(message))")
    }

    public func push(branch: String, setUpstream: Bool = true, remote: String = "origin") async throws {
        try await run("push -q \(setUpstream ? "-u " : "")\(remote) \(quoted(branch))")
    }

    /// Deletes a branch on the remote, then prunes locally so the upstream reads as gone.
    public func deleteRemoteBranch(_ branch: String, remote: String = "origin") async throws {
        try await run("push -q \(remote) --delete \(quoted(branch))")
        try await run("fetch -q --prune \(remote)")
    }

    public func fetch(prune: Bool = true) async throws {
        try await run("fetch -q --all\(prune ? " --prune" : "")")
    }

    /**
     * Commits on the remote's copy of `branch`, so the repo at `path` falls behind it.
     *
     * Works through a throwaway clone, because a bare repo has no working tree to commit in.
     */
    public static func advanceRemote(
        _ remotePath: String,
        branch: String = "main",
        via scratchPath: String,
        file: String = "remote.txt",
        content: String = "from the remote",
        message: String = "Remote commit"
    ) async throws {
        let scratch = GitFixture(path: scratchPath)
        try FileManager.default.createDirectory(atPath: scratchPath, withIntermediateDirectories: true)
        try await scratch.run("clone -q \(quoted(remotePath)) .")
        try await scratch.run("checkout -q \(quoted(branch))")
        try await scratch.commit(file: file, content: content, message: message)
        try await scratch.run("push -q origin \(quoted(branch))")
        try FileManager.default.removeItem(atPath: scratchPath)
    }
}

/// Wraps a string so `/bin/sh` passes it to git unchanged.
public func quoted(_ string: String) -> String {
    "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

/// A `RepoTypeOptions.Resolved` with nothing excluded.
public func allRepoTypes() -> RepoTypeOptions.Resolved {
    RepoTypeOptions.Resolved(
        noRepos: false, noForkedRepos: false, noStarredRepos: false, noPublicRepos: false, noPrivateRepos: false,
        onlyStarredRepos: false, onlyForkedRepos: false, onlyPublicRepos: false, onlyPrivateRepos: false,
        noWikis: false, noGists: false, noForkedGists: false, noStarredGists: false, noPublicGists: false, noPrivateGists: false,
        onlyStarredGists: false, onlyForkedGists: false, onlyPublicGists: false, onlyPrivateGists: false
    )
}

/**
 * A temporary directory that removes itself.
 */
public final class TemporaryDirectory {
    public let path: String

    public init(prefix: String = "forgery-test") {
        path = "\(NSTemporaryDirectory())\(prefix)-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(atPath: path)
    }

    public func appending(_ component: String) -> String {
        "\(path)/\(component)"
    }
}
