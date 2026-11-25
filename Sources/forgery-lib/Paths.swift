import Foundation

/**
 * A directory to scan, and what the repos inside it are.
 *
 * The category travels with the root so that a repo can be classified while it is found, instead
 * of by matching substrings of its path afterwards. Path matching is what made forked repos and
 * gists disappear from the report: they are cloned under `forked`, but the report grouped on
 * `forks`.
 */
public struct RepoRoot: Sendable, Equatable {
    /// Absolute path of the directory holding the clones.
    public let path: String

    /// What kind of repos this directory holds.
    public let category: RepoCategory

    public init(path: String, category: RepoCategory) {
        self.path = path
        self.category = category
    }

    /// Whether the clones sit one level deeper, under the login of each repo's owner.
    public var isOwnerNested: Bool { category.isOwnerNested }
}

/**
 * Paths for different repository types that could exist for either users or orgs. Orgs cannot have starred repositories, so there is no property for that in this struct. See the sibling property for it in `UserPaths`.`
 */
public struct RepoPaths {
    public let forkPath: String
    public let publicPath: String
    public let privatePath: String
}

/**
 * Paths for different repository types that could exist for either users or orgs. Orgs cannot have forked or starred gists, so there is no property for that in this struct. See the sibling properties for them in `UserPaths`.`
 */
public struct GistPaths {
    public let publicPath: String
    public let privatePath: String
}

public struct CommonPaths {
    public static let userBasePathComponent = "user"
    public static let orgBasePathComponent = "organization"

    public let repoPaths: RepoPaths
    public let gistPaths: GistPaths
    public let repoTypes: RepoTypeOptions.Resolved

    public init(basePath: String, username: String, repoTypes: RepoTypeOptions.Resolved, createOnDisk: Bool) throws {
        self.repoTypes = repoTypes

        let userReposPath = "\(basePath)/\(CommonPaths.userBasePathComponent)/\(username)/\(reposSubpath)"
        let forkedReposPath = "\(userReposPath)/\(forkedSubpath)"
        let publicRepoPath = "\(userReposPath)/\(publicSubpath)"
        let privatePath = "\(userReposPath)/\(privateSubpath)"
        self.repoPaths = RepoPaths(forkPath: forkedReposPath, publicPath: publicRepoPath, privatePath: privatePath)
        
        let userGistsPath = "\(basePath)/\(CommonPaths.userBasePathComponent)/\(username)/\(gistsSubpath)"
        let publicGistPath = "\(userGistsPath)/\(publicSubpath)"
        let privateGistPath = "\(userGistsPath)/\(privateSubpath)"
        self.gistPaths = GistPaths(publicPath: publicGistPath, privatePath: privateGistPath)

        if createOnDisk {
            try self.createOnDisk()
        }
    }
    
    public init(basePath: String, orgName: String, repoTypes: RepoTypeOptions.Resolved, createOnDisk: Bool) throws {
        self.repoTypes = repoTypes

        let orgReposBasePath = "\(basePath)/\(CommonPaths.orgBasePathComponent)/\(orgName)/\(reposSubpath)"
        let forkPath = "\(orgReposBasePath)/\(forkedSubpath)"
        let publicPath = "\(orgReposBasePath)/\(publicSubpath)"
        let privatePath = "\(orgReposBasePath)/\(privateSubpath)"
        self.repoPaths = RepoPaths(forkPath: forkPath, publicPath: publicPath, privatePath: privatePath)

        let orgGistsBasePath = "\(basePath)/\(CommonPaths.orgBasePathComponent)/\(orgName)/\(gistsSubpath)"
        let publicGistPath = "\(orgGistsBasePath)/\(publicSubpath)"
        let privateGistPath = "\(orgGistsBasePath)/\(privateSubpath)"
        
        self.gistPaths = GistPaths(publicPath: publicGistPath, privatePath: privateGistPath)

        if createOnDisk {
            try self.createOnDisk()
        }
    }
    
    private func createOnDisk() throws {
        if !repoTypes.noForkedRepos {
            try FileManager.default.createDirectory(atPath: repoPaths.forkPath, withIntermediateDirectories: true, attributes: nil)
        }
        if !repoTypes.noPublicRepos {
            try FileManager.default.createDirectory(atPath: repoPaths.publicPath, withIntermediateDirectories: true, attributes: nil)
        }
        if !repoTypes.noPrivateRepos {
            try FileManager.default.createDirectory(atPath: repoPaths.privatePath, withIntermediateDirectories: true, attributes: nil)
        }

        if !repoTypes.noPublicGists {
            try FileManager.default.createDirectory(atPath: gistPaths.publicPath, withIntermediateDirectories: true, attributes: nil)
        }
        if !repoTypes.noPrivateGists {
            try FileManager.default.createDirectory(atPath: gistPaths.privatePath, withIntermediateDirectories: true, attributes: nil)
        }
    }

    /// The directories to scan, each tagged with the kind of repos it holds.
    public var validRoots: [RepoRoot] {
        var roots = [RepoRoot]()

        // Add repo paths
        if !repoTypes.noPublicRepos {
            roots.append(RepoRoot(path: repoPaths.publicPath, category: .publicRepo))
        }
        if !repoTypes.noPrivateRepos {
            roots.append(RepoRoot(path: repoPaths.privatePath, category: .privateRepo))
        }
        if !repoTypes.noForkedRepos {
            roots.append(RepoRoot(path: repoPaths.forkPath, category: .forkedRepo))
        }

        // Add gist paths
        if !repoTypes.noPublicGists {
            roots.append(RepoRoot(path: gistPaths.publicPath, category: .publicGist))
        }
        if !repoTypes.noPrivateGists {
            roots.append(RepoRoot(path: gistPaths.privatePath, category: .privateGist))
        }

        return roots
    }
}

/**
 * Paths for different repo and gist types that a user can have.
 */
public struct UserPaths {
    public let commonPaths: CommonPaths
    
    /// - note; Only users can have starred repos, so it exists as a separate property here as opposed to living in the common RepoPaths struct property.
    public let starredRepoPath: String
    
    /// - note: Only users can have forked gists, so it exists as a separate property here as opposed to living in the common GistPaths struct property.
    public let forkedGistPath: String
    
    /// - note: Only users can have starred gists, so it exists as a separate property here as opposed to living in the common GistPaths struct property.
    public let starredGistPath: String
    
    public init(basePath: String, username: String, repoTypes: RepoTypeOptions.Resolved, createOnDisk: Bool) throws {
        let userBasePath = "\(basePath)/\(CommonPaths.userBasePathComponent)/\(username)"

        let userReposPath = "\(userBasePath)/\(reposSubpath)"
        self.starredRepoPath = "\(userReposPath)/\(starredSubpath)"
        
        let userGistsPath = "\(userBasePath)/\(gistsSubpath)"
        self.forkedGistPath = "\(userGistsPath)/\(forkedSubpath)"
        self.starredGistPath = "\(userGistsPath)/\(starredSubpath)"

        self.commonPaths = try CommonPaths(basePath: basePath, username: username, repoTypes: repoTypes, createOnDisk: createOnDisk)

        if createOnDisk {
            try self.createOnDisk()
        }
    }
    
    private func createOnDisk() throws {
        if !commonPaths.repoTypes.noStarredRepos {
            try FileManager.default.createDirectory(atPath: starredRepoPath, withIntermediateDirectories: true, attributes: nil)
        }

        if !commonPaths.repoTypes.noForkedGists {
            try FileManager.default.createDirectory(atPath: forkedGistPath, withIntermediateDirectories: true, attributes: nil)
        }
        if !commonPaths.repoTypes.noStarredGists {
            try FileManager.default.createDirectory(atPath: starredGistPath, withIntermediateDirectories: true, attributes: nil)
        }
    }

    /// The directories to scan, each tagged with the kind of repos it holds.
    public var validRoots: [RepoRoot] {
        var roots = commonPaths.validRoots

        if !commonPaths.repoTypes.noStarredRepos {
            roots.append(RepoRoot(path: starredRepoPath, category: .starredRepo))
        }

        if !commonPaths.repoTypes.noForkedGists {
            roots.append(RepoRoot(path: forkedGistPath, category: .forkedGist))
        }
        if !commonPaths.repoTypes.noStarredGists {
            roots.append(RepoRoot(path: starredGistPath, category: .starredGist))
        }

        return roots
    }
}
