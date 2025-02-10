import Foundation
import Logging

enum ForgeryError {
    enum Clone {
        enum Repo: Error {
            case alreadyCloned
            case noSSHURL
            case couldNotFetchRepo
            case noOwnerLogin
            case noName
            case noForkParent
            case noForkParentLogin
            case noForkParentSSHURL
        }
        
        enum Gist: Error {
            case noPullURL
            case noName
            case noForkOwnerLogin
            case noForkParent
            case noForkParentPullURL
            case couldNotFetchForkParent
            case noGistAccessInfo
            case noID
        }
    }
}

public struct RepoTypes: OptionSet {
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
    
    public let rawValue: Int
    
    public static let noForks = RepoTypes(rawValue: 1 << 0)
    public static let noPrivate = RepoTypes(rawValue: 1 << 1)
    public static let noPublic = RepoTypes(rawValue: 1 << 2)
    public static let noStarred = RepoTypes(rawValue: 1 << 3)
    
    public static let noWikis = RepoTypes(rawValue: 1 << 4)
    
    public static let noForkedGists = RepoTypes(rawValue: 1 << 5)
    public static let noPrivateGists = RepoTypes(rawValue: 1 << 6)
    public static let noPublicGists = RepoTypes(rawValue: 1 << 7)
    public static let noStarredGists = RepoTypes(rawValue: 1 << 8)
    
    public var noNonstarredRepos: Bool {
        contains(.noForks) && contains(.noPublic) && contains(.noPrivate)
    }
    
    public var noNonstarredGists: Bool {
        contains(.noForkedGists) && contains(.noPublicGists) && contains(.noPrivateGists)
    }
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
    public let repoPaths: RepoPaths
    public let gistPaths: GistPaths
    
    public init(basePath: String, username: String) {
        let userReposPath = "\(basePath)/\(user)/\(reposSubpath)"
        let forkedReposPath = "\(userReposPath)/\(forkedSubpath)"
        let publicRepoPath = "\(userReposPath)/\(publicSubpath)"
        let privatePath = "\(userReposPath)/\(privateSubpath)"
        self.repoPaths = RepoPaths(forkPath: forkedReposPath, publicPath: publicRepoPath, privatePath: privatePath)
        
        let userGistsPath = "\(basePath)/\(user)/\(gistsSubpath)"
        let publicGistPath = "\(userGistsPath)/\(publicSubpath)"
        let privateGistPath = "\(userGistsPath)/\(privateSubpath)"
        self.gistPaths = GistPaths(publicPath: publicGistPath, privatePath: privateGistPath)
    }
    
    public init(basePath: String, orgName: String) {
        let orgReposPath = "\(basePath)/\(orgName)/\(reposSubpath)"
        let forkPath = "\(orgReposPath)/\(forkedSubpath)"
        let publicPath = "\(orgReposPath)/\(publicSubpath)"
        let privatePath = "\(orgReposPath)/\(privateSubpath)"
        
        let orgGistsPath = "\(basePath)/\(orgName)/\(gistsSubpath)"
        let publicGistPath = "\(orgGistsPath)/\(publicSubpath)"
        let privateGistPath = "\(orgGistsPath)/\(privateSubpath)"
        
        self.gistPaths = GistPaths(publicPath: publicGistPath, privatePath: privateGistPath)
        self.repoPaths = RepoPaths(forkPath: forkPath, publicPath: publicPath, privatePath: privatePath)
    }
    
    public func createOnDisk(repoTypes: RepoTypes) throws {
        if !repoTypes.contains(.noForks) {
            try FileManager.default.createDirectory(atPath: repoPaths.forkPath, withIntermediateDirectories: true, attributes: nil)
        }
        if !repoTypes.contains(.noPublic) {
            try FileManager.default.createDirectory(atPath: repoPaths.publicPath, withIntermediateDirectories: true, attributes: nil)
        }
        if !repoTypes.contains(.noPrivate) {
            try FileManager.default.createDirectory(atPath: repoPaths.privatePath, withIntermediateDirectories: true, attributes: nil)
        }

        if !repoTypes.contains(.noPublicGists) {
            try FileManager.default.createDirectory(atPath: gistPaths.publicPath, withIntermediateDirectories: true, attributes: nil)
        }
        if !repoTypes.contains(.noPrivateGists) {
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
        let userReposPath = "\(basePath)/\(user)/\(reposSubpath)"
        self.starredRepoPath = "\(userReposPath)/\(starredSubpath)"
        
        let userGistsPath = "\(basePath)/\(user)/\(gistsSubpath)"
        self.forkedGistPath = "\(userGistsPath)/\(forkedSubpath)"
        self.starredGistPath = "\(userGistsPath)/\(starredSubpath)"
        
        self.commonPaths = CommonPaths(basePath: basePath, username: username)
    }
    
    public func createOnDisk(repoTypes: RepoTypes) throws {
        try commonPaths.createOnDisk(repoTypes: repoTypes)
        
        if !repoTypes.contains(.noStarred) {
            try FileManager.default.createDirectory(atPath: starredRepoPath, withIntermediateDirectories: true, attributes: nil)
        }

        if !repoTypes.contains(.noForkedGists) {
            try FileManager.default.createDirectory(atPath: forkedGistPath, withIntermediateDirectories: true, attributes: nil)
        }
        if !repoTypes.contains(.noStarredGists) {
            try FileManager.default.createDirectory(atPath: starredGistPath, withIntermediateDirectories: true, attributes: nil)
        }
    }
}

let organization = "organization"
public let user = "user"

let publicSubpath = "public"
let privateSubpath = "private"
let forkedSubpath = "forked"
let starredSubpath = "starred"

let reposSubpath = "repos"
let gistsSubpath = "gists"

let jsonDecoder = JSONDecoder()
let urlSession = URLSession(configuration: .default)

public var logger = Logger(label: "forgery")
