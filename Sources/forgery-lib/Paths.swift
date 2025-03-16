import Foundation

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

    public var validPaths: [String] {
        var pathsToCheck: [String] = []

        // Add repo paths
        if !repoTypes.noPublicRepos {
            pathsToCheck.append(repoPaths.publicPath)
        }
        if !repoTypes.noPrivateRepos {
            pathsToCheck.append(repoPaths.privatePath)
        }
        if !repoTypes.noForkedRepos {
            pathsToCheck.append(repoPaths.forkPath)
        }

        // Add gist paths
        if !repoTypes.noPublicGists {
            pathsToCheck.append(gistPaths.publicPath)
        }
        if !repoTypes.noPrivateGists {
            pathsToCheck.append(gistPaths.privatePath)
        }

        return pathsToCheck
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

    public var validPaths: [String] {
        var pathsToCheck = commonPaths.validPaths

        if !commonPaths.repoTypes.noForkedGists {
            pathsToCheck.append(forkedGistPath)
        }
        if !commonPaths.repoTypes.noStarredGists {
            pathsToCheck.append(starredGistPath)
        }

        return pathsToCheck
    }
}
