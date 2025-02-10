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
    public let repoPaths: RepoPaths
    public let gistPaths: GistPaths
    
    public init(basePath: String, username: String) {
        let userReposPath = "\(basePath)/user/\(username)/\(reposSubpath)"
        let forkedReposPath = "\(userReposPath)/\(forkedSubpath)"
        let publicRepoPath = "\(userReposPath)/\(publicSubpath)"
        let privatePath = "\(userReposPath)/\(privateSubpath)"
        self.repoPaths = RepoPaths(forkPath: forkedReposPath, publicPath: publicRepoPath, privatePath: privatePath)
        
        let userGistsPath = "\(basePath)/\(username)/\(gistsSubpath)"
        let publicGistPath = "\(userGistsPath)/\(publicSubpath)"
        let privateGistPath = "\(userGistsPath)/\(privateSubpath)"
        self.gistPaths = GistPaths(publicPath: publicGistPath, privatePath: privateGistPath)
    }
    
    public init(basePath: String, orgName: String) {
        let orgReposPath = "\(basePath)/org/\(orgName)/\(reposSubpath)"
        let forkPath = "\(orgReposPath)/\(forkedSubpath)"
        let publicPath = "\(orgReposPath)/\(publicSubpath)"
        let privatePath = "\(orgReposPath)/\(privateSubpath)"
        
        let orgGistsPath = "\(basePath)/\(orgName)/\(gistsSubpath)"
        let publicGistPath = "\(orgGistsPath)/\(publicSubpath)"
        let privateGistPath = "\(orgGistsPath)/\(privateSubpath)"
        
        self.gistPaths = GistPaths(publicPath: publicGistPath, privatePath: privateGistPath)
        self.repoPaths = RepoPaths(forkPath: forkPath, publicPath: publicPath, privatePath: privatePath)
    }
    
    public func createOnDisk(repoTypes: RepoTypeOptions.Resolved) throws {
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
    
    public init(basePath: String, username: String) {
        let userBasePath = "\(basePath)/user/\(username)"
        
        let userReposPath = "\(userBasePath)/\(reposSubpath)"
        self.starredRepoPath = "\(userReposPath)/\(starredSubpath)"
        
        let userGistsPath = "\(userBasePath)/\(gistsSubpath)"
        self.forkedGistPath = "\(userGistsPath)/\(forkedSubpath)"
        self.starredGistPath = "\(userGistsPath)/\(starredSubpath)"
        
        self.commonPaths = CommonPaths(basePath: basePath, username: username)
    }
    
    public func createOnDisk(repoTypes: RepoTypeOptions.Resolved) throws {
        try commonPaths.createOnDisk(repoTypes: repoTypes)
        
        if !repoTypes.noStarredRepos {
            try FileManager.default.createDirectory(atPath: starredRepoPath, withIntermediateDirectories: true, attributes: nil)
        }

        if !repoTypes.noForkedGists {
            try FileManager.default.createDirectory(atPath: forkedGistPath, withIntermediateDirectories: true, attributes: nil)
        }
        if !repoTypes.noStarredGists {
            try FileManager.default.createDirectory(atPath: starredGistPath, withIntermediateDirectories: true, attributes: nil)
        }
    }
}
