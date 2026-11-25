import Foundation

/**
 * How to walk a set of roots.
 */
public struct ScanOptions: Sendable {
    /// What to collect for each repo found.
    public var inspection: RepoInspectionOptions

    /// How many repos to inspect at once. Each repo costs several git subprocesses, so a serial
    /// walk of a large tree spends nearly all of its time waiting.
    public var maxConcurrentRepos: Int

    public init(inspection: RepoInspectionOptions = RepoInspectionOptions(), maxConcurrentRepos: Int = 8) {
        self.inspection = inspection
        self.maxConcurrentRepos = max(1, maxConcurrentRepos)
    }
}

/// A repo found on disk, before it is inspected.
struct DiscoveredRepo: Sendable {
    let path: String
    let category: RepoCategory
    let owner: String?
}

/**
 * Finds every repo under the given roots and reads the state of each one.
 *
 * Replaces the directory walk that `status` and `sync` each had their own copy of.
 */
public func scanRepositories(roots: [RepoRoot], options: ScanOptions = ScanOptions()) async throws -> StatusReport {
    let discovered = discoverRepositories(roots: roots)
    logger.debug("Found \(discovered.count) repos under \(roots.count) roots")

    let summaries = await inspect(discovered, options: options)

    return StatusReport(
        repos: summaries.sorted { $0.path < $1.path },
        didFetch: options.inspection.fetch
    )
}

/**
 * Walks the roots and returns the repos inside them.
 *
 * Whether a root nests its clones under an owner login is a property of the root's category, not
 * something guessed from the text of the path. The previous check tested whether the full path
 * contained `/starred` or `/forked` anywhere, so a base path such as `~/Code/forked-stuff` made
 * every root look owner-nested.
 */
func discoverRepositories(roots: [RepoRoot]) -> [DiscoveredRepo] {
    let fileManager = FileManager.default
    var discovered = [DiscoveredRepo]()

    for root in roots {
        let rootPath = (root.path as NSString).expandingTildeInPath

        var rootIsDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: rootPath, isDirectory: &rootIsDirectory) else {
            logger.debug("Path does not exist: \(rootPath)")
            continue
        }
        guard rootIsDirectory.boolValue else {
            logger.warning("Path is not a directory: \(rootPath)")
            continue
        }

        logger.debug("Checking repos in \(rootPath)")
        for entry in (try? fileManager.contentsOfDirectory(atPath: rootPath))?.sorted() ?? [] {
            let entryPath = "\(rootPath)/\(entry)"
            guard isDirectory(entryPath) else { continue }

            // A repo directly under an owner-nested root is unexpected but harmless, so take it
            // rather than discard it.
            if isGitRepository(entryPath) {
                discovered.append(DiscoveredRepo(path: entryPath, category: root.category, owner: nil))
                continue
            }

            guard root.isOwnerNested else {
                logger.warning("Directory does not contain a git repo: \(entryPath)")
                continue
            }

            logger.debug("Checking owner directory: \(entry)")
            for ownedEntry in (try? fileManager.contentsOfDirectory(atPath: entryPath))?.sorted() ?? [] {
                let ownedPath = "\(entryPath)/\(ownedEntry)"
                guard isDirectory(ownedPath) else { continue }
                guard isGitRepository(ownedPath) else {
                    logger.warning("Directory does not contain a git repo: \(ownedPath)")
                    continue
                }
                discovered.append(DiscoveredRepo(path: ownedPath, category: root.category, owner: entry))
            }
        }
    }

    return discovered
}

/**
 * Inspects the repos concurrently, up to `maxConcurrentRepos` at a time.
 *
 * A repo that cannot be read is logged and dropped. One unreadable clone must not end a scan of
 * hundreds of others.
 */
private func inspect(_ repos: [DiscoveredRepo], options: ScanOptions) async -> [RepoSummary] {
    guard !repos.isEmpty else { return [] }

    return await withTaskGroup(of: RepoSummary?.self) { group in
        var summaries = [RepoSummary]()
        summaries.reserveCapacity(repos.count)

        var next = 0
        let limit = min(options.maxConcurrentRepos, repos.count)

        func addTask(for repo: DiscoveredRepo) {
            group.addTask {
                do {
                    return try await inspectRepo(
                        at: repo.path,
                        category: repo.category,
                        owner: repo.owner,
                        options: options.inspection
                    )
                } catch {
                    logger.warning("Could not read repo at \(repo.path): \(error)")
                    return nil
                }
            }
        }

        while next < limit {
            addTask(for: repos[next])
            next += 1
        }

        while let summary = await group.next() {
            if let summary { summaries.append(summary) }
            if next < repos.count {
                addTask(for: repos[next])
                next += 1
            }
        }

        return summaries
    }
}

private func isDirectory(_ path: String) -> Bool {
    var flag: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &flag) else { return false }
    return flag.boolValue
}

/// True when the directory holds a `.git` entry. Worktrees and submodules use a `.git` file rather
/// than a directory, so the kind of entry is deliberately not checked.
private func isGitRepository(_ path: String) -> Bool {
    FileManager.default.fileExists(atPath: (path as NSString).appendingPathComponent(".git"))
}
