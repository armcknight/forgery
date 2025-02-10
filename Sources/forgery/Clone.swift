import ArgumentParser
import Foundation
import GitKit
import OctoKit
import forgery_lib

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
    
    @Flag(help: "Only clone the authenticated user's or organization's public repos. Has no effect on gist selection.")
    var onlyPublicRepos: Bool = false
    
    @Flag(help: "Only clone the authenticated user's or organization's private repos. Has no effect on gist selection.")
    var onlyPrivateRepos: Bool = false
    
    @Flag(help: "Only clone the authenticated user's starred repos (does not apply to organizations as they cannot star repos). Has no effect on gist selection.")
    var onlyStarredRepos: Bool = false
    
    @Flag(help: "Only clone the authenticated user's or organization's forked repos. Has no effect on gist selection.")
    var onlyForkedRepos: Bool = false
    
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
    
    @Flag(help: "Only clone the authenticated user's or organization's public gists. Has no effect on repo selection.")
    var onlyPublicGists: Bool = false
    
    @Flag(help: "Only clone the authenticated user's or organization's private gists. Has no effect on repo selection.")
    var onlyPrivateGists: Bool = false
    
    @Flag(help: "Only clone the authenticated user's starred gists (does not apply to organizations as they cannot star gists). Has no effect on repo selection.")
    var onlyStarredGists: Bool = false
    
    @Flag(help: "Only clone the authenticated user's forked gists (does not apply to organizations as they cannot fork gists). Has no effect on repo selection.")
    var onlyForkedGists: Bool = false
    
    // MARK: Computed properties
    
    lazy var repoTypes = {
        var types = RepoTypes()
        
        if noRepos || noForkedRepos || onlyStarredRepos || onlyPublicRepos || onlyPrivateRepos {
            types.insert(.noForks)
        }
        if noRepos || noPublicRepos || onlyStarredRepos || onlyForkedRepos || onlyPrivateRepos {
            types.insert(.noPublic)
        }
        if noRepos || noPrivateRepos || onlyStarredRepos || onlyPublicRepos || onlyForkedRepos {
            types.insert(.noPrivate)
        }
        if noRepos || noStarredRepos || onlyPublicRepos || onlyPrivateRepos || onlyForkedRepos {
            types.insert(.noStarred)
        }

        if noRepos || noWikis {
            types.insert(.noWikis)
        }
        
        if noGists || noForkedGists || onlyPrivateGists || onlyPublicGists || onlyStarredGists {
            types.insert(.noForkedGists)
        }
        if noGists || noPrivateGists || onlyPublicGists || onlyStarredGists || onlyForkedGists {
            types.insert(.noPrivateGists)
        }
        if noGists || noPublicGists || onlyPrivateGists || onlyForkedGists || onlyStarredGists {
            types.insert(.noPublicGists)
        }
        if noGists || noStarredGists || onlyPublicGists || onlyPrivateGists || onlyForkedGists {
            types.insert(.noStarredGists)
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
        
        let user = try github.authenticate()
        
        guard let username = user.login else {
            logger.error("No user login info returned after authenticating.")
            return
        }
        
        let userPaths = UserPaths(basePath: basePath, username: username)
        try userPaths.createOnDisk(repoTypes: repoTypes)
        
        if !(noRepos || repoTypes.noNonstarredRepos) {
            logger.info("Fetching repositories owned by \(username).")
            
            let repos = try github.getRepos(ownedBy: username)
            
            logger.info("Retrieved list of repos to clone (\(repos.count) total).")
            
            for repo in repos {
                if repo.organization != nil && organization == nil && dedupeOrgReposCreatedByUser {
                    // the GitHub API only returns org repos that are owned by the authenticated user, so we skip this repo if it's owned by an org owned by the user, and we have deduping selected
                    continue
                }
                
                do {
                    try github.cloneRepoType(repo: repo, paths: userPaths.commonPaths, repoTypes: repoTypes)
                } catch {
                    logger.error("Failed to clone repo \(String(describing: repo.fullName)): \(error)")
                }
            }
        }
        
        if !(noRepos || repoTypes.contains(.noStarred)) {
            let repos = try github.getStarredRepos(starredBy: username)
            for repo in repos {
                guard let owner = repo.owner.login else {
                    logger.error("No owner info returned for starred repo with id \(repo.id).")
                    continue
                }
                do {
                    try github.cloneNonForkedRepo(repo: repo, cloneRoot: "\(userPaths.starredRepoPath)/\(owner)", noWikis: repoTypes.contains(.noWikis))
                } catch {
                    logger.error("Failed to clone starred repo \(String(describing: repo.fullName)): \(error)")
                }
            }
        }
        
        if !(noGists || repoTypes.noNonstarredGists) {
            let gists = try github.getGists()
            for gist in gists {
                do {
                    
                    try github.cloneGistType(gist: gist, paths: userPaths, repoTypes: repoTypes)
                } catch {
                    logger.error("Failed to clone gist \(gist.fullName!): \(error)")
                }
            }
        }
        
        if !(noGists || repoTypes.contains(.noStarredGists)) {
            let gists = try github.getStarredGists()
            for gist in gists {
                guard let owner = gist.owner?.login else {
                    logger.error("No owner info returned for starred gist with id \(String(describing: gist.id)).")
                    continue
                }
                try github.cloneNonForkedGist(gist: gist, cloneRoot: "\(userPaths.starredGistPath)/\(owner)")
            }
        }
    }
    
    mutating func cloneForOrganization(github: GitHub, organization: String) throws {
        let orgUser: User = try github.authenticateOrg(name: organization)
        let orgPaths = CommonPaths(basePath: basePath, orgName: organization)
        try orgPaths.createOnDisk(repoTypes: repoTypes)
        guard let owner = orgUser.login else {
            logger.error("No user info returned for organization.")
            return
        }
        let repos = try github.getRepos(ownedBy: owner)
        for repo in repos {
            do {
                try github.cloneRepoType(repo: repo, paths: orgPaths, repoTypes: repoTypes)
            } catch {
                logger.error("Failed to clone repo \(String(describing: repo.fullName)): \(error)")
            }
        }
    }
}
