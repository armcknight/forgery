import ArgumentParser
import Foundation
import GitKit
import OctoKit

struct Clone: ParsableCommand {
    @Argument(help: "The GitHub access token of the GitHub user whose repos should be synced.")
    var accessToken: String
    
    @Argument(help: "Local location to work with repos.")
    var basePath: String
    
    // MARK: Orgs
    
    @Option(help: "Instead of fetching the list of the authenticated user's repos, fetch the specified organization's.")
    var organization: String?
    
    @Flag(help: "When cloning repos for a user, don't clone repos created by a user by owned by an organization.")
    var dedupeOrgReposCreatedByUser: Bool = false
    
    // MARK: Repo exclusions
    
    @Flag(help: "Do not clone the authenticated user's or organization's public repos.")
    var noPublicRepos: Bool = false
    
    @Flag(help: "Do not clone the authenticated user's or organization's private repos.")
    var noPrivateRepos: Bool = false
    
    @Flag(help: "Do not clone the authenticated user's starred repos (does not apply to organizations as they cannot star repos).")
    var noStarredRepos: Bool = false
    
    @Flag(help: "Do not clone the authenticated user's or organization's forked repos.")
    var noForkedRepos: Bool = false
    
    @Flag(help: "Do not clone wikis associated with any repos owned by user or org.")
    var noWikis: Bool = false
    
    @Flag(help: "Do not clone any repos (includes wikis).")
    var noRepos: Bool = false
    
    // MARK: Repo selections
    // TODO: implement
    
    @Flag(help: "Only clone the authenticated user's or organization's public repos.")
    var onlyPublicRepos: Bool = false
    
    @Flag(help: "Only clone the authenticated user's or organization's private repos.")
    var onlyPrivateRepos: Bool = false
    
    @Flag(help: "Only clone the authenticated user's starred repos (does not apply to organizations as they cannot star repos).")
    var onlyStarredRepos: Bool = false
    
    @Flag(help: "Only clone the authenticated user's or organization's forked repos.")
    var onlyForkedRepos: Bool = false
    
    @Flag(help: "Only clone wikis associated with any repos owned by user or org.")
    var onlyWikis: Bool = false
    
    // MARK: Gists
    // TODO: implement
    
    @Flag(help: "Do not clone the authenticated user's or organization's public gists.")
    var noPublicGists: Bool = false
    
    @Flag(help: "Do not clone the authenticated user's or organization's private gists.")
    var noPrivateGists: Bool = false
    
    @Flag(help: "Do not clone the authenticated user's starred gists (does not apply to organizations).")
    var noStarredGists: Bool = false
    
    @Flag(help: "Do not clone the authenticated user's forked gists (does not apply to organizations).")
    var noForkedGists: Bool = false
    
    @Flag(help: "Do not clone any gists, no repos/wikis.")
    var noGists: Bool = false
    
    @Flag(help: "Only clone the authenticated user's or organization's public gists.")
    var onlyPublicGists: Bool = false
    
    @Flag(help: "Only clone the authenticated user's or organization's private gists.")
    var onlyPrivateGists: Bool = false
    
    @Flag(help: "Only clone the authenticated user's starred gists (does not apply to organizations as they cannot star gists).")
    var onlyStarredGists: Bool = false
    
    @Flag(help: "Only clone the authenticated user's forked gists (does not apply to organizations as they cannot fork gists).")
    var onlyForkedGists: Bool = false
    
    @Flag(help: "Only clone gists, no repos/wikis.")
    var onlyGists: Bool = false
    
    // MARK: Computed properties
    
    lazy var repoTypes = {
        var types = RepoTypes()
        if noForkedRepos {
            types.insert(.noForks)
        }
        if noPublicRepos {
            types.insert(.noPublic)
        }
        if noPrivateRepos {
            types.insert(.noPrivate)
        }
        return types
    }()
}

extension Clone {
    mutating func run() throws {
        logger.info("Starting clone...")
        
        let github = GitHub(accessToken: accessToken)
        
        if let organization = organization {
            try cloneForOrganization(github: github, organization: organization)
        } else {
            try cloneForUser(github: github)
        }
    }
}

extension Clone {
    mutating func cloneForUser(github: GitHub) throws {
        logger.info("Cloning for user...")
        
        let user = try github.synchronouslyAuthenticate()
        
        guard let username = user.login else {
            logger.error("No user login info returned after authenticating.")
            return
        }
        
        let userPaths = try createUserPaths(user: username)
        
        logger.info("Fetching repositories owned by \(username).")
        
        let repos = try github.synchronouslyFetchRepositories(owner: username)
        
        logger.info("Retrieved list of repos to clone (\(repos.count) total).")
        
        for repo in repos {
            if repo.organization != nil && organization == nil && dedupeOrgReposCreatedByUser {
                // the GitHub API only returns org repos that are owned by the authenticated user, so we skip this repo if it's owned by an org owned by the user, and we have deduping selected
                continue
            }
            
            do {
                try github.cloneRepoType(repo: repo, paths: userPaths.paths, repoTypes: repoTypes)
                
                if !noStarredRepos {
                    try github.cloneStarredRepositories(username, userPaths.starredPath, noWikis: noWikis)
                }
            } catch {
                logger.error("Failed to clone repo: \(error)")
            }
        }
    }
    
    mutating func cloneForOrganization(github: GitHub, organization: String) throws {
        let org = try github.synchronouslyAuthenticateUser(name: organization)
        let orgPaths = try createOrgDirectories(org: organization)
        guard let owner = org.login else {
            logger.error("No user info returned for organization.")
            return
        }
        let repos = try github.synchronouslyFetchRepositories(owner: owner)
        for repo in repos {
            do {
                try github.cloneRepoType(repo: repo, paths: orgPaths, repoTypes: repoTypes)
            } catch {
                logger.error("Failed to clone repo: \(error)")
            }
        }
    }
    
    func createOrgDirectories(org: String) throws -> Paths {
        let orgReposPath = "\(basePath)/\(org)/\(reposSubpath)"
        let forkPath = "\(orgReposPath)/\(forkedSubpath)"
        let publicPath = "\(orgReposPath)/\(publicSubpath)"
        let privatePath = "\(orgReposPath)/\(privateSubpath)"
        
        if !noForkedRepos {
            try FileManager.default.createDirectory(atPath: forkPath, withIntermediateDirectories: true, attributes: nil)
        }
        if !noPublicRepos {
            try FileManager.default.createDirectory(atPath: publicPath, withIntermediateDirectories: true, attributes: nil)
        }
        if !noPrivateRepos {
            try FileManager.default.createDirectory(atPath: privatePath, withIntermediateDirectories: true, attributes: nil)
        }
        
        return Paths(forkPath: forkPath, publicPath: publicPath, privatePath: privatePath)
    }
    
    func createUserPaths(user: String) throws -> UserPaths {
        let userReposPath = "\(basePath)/\(user)/\(reposSubpath)"
        let forkPath = "\(userReposPath)/\(forkedSubpath)"
        let publicPath = "\(userReposPath)/\(publicSubpath)"
        let privatePath = "\(userReposPath)/\(privateSubpath)"
        let starredPath = "\(userReposPath)/\(starredSubpath)"
        
        if !noForkedRepos {
            try FileManager.default.createDirectory(atPath: forkPath, withIntermediateDirectories: true, attributes: nil)
        }
        if !noPublicRepos {
            try FileManager.default.createDirectory(atPath: publicPath, withIntermediateDirectories: true, attributes: nil)
        }
        if !noPrivateRepos {
            try FileManager.default.createDirectory(atPath: privatePath, withIntermediateDirectories: true, attributes: nil)
        }
        if !noStarredRepos {
            try FileManager.default.createDirectory(atPath: starredPath, withIntermediateDirectories: true, attributes: nil)
        }
        
        return UserPaths(paths: Paths(forkPath: forkPath, publicPath: publicPath, privatePath: privatePath), starredPath: starredPath)
    }
}
