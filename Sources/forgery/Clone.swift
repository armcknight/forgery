import ArgumentParser
import Foundation
import GitKit
import OctoKit

struct Clone: ParsableCommand {
    @Argument(help: "The GitHub access token of the GitHub user whose repos should be synced.")
    var accessToken: String
    
    @Argument(help: "Local location to work with repos.")
    var basePath: String
    
    @Flag(help: "Do not clone the authenticated user's or organization's public repos.")
    var noPublicRepos: Bool = false
    
    @Flag(help: "Do not clone the authenticated user's or organization's private repos.")
    var noPrivateRepos: Bool = false
    
    @Flag(help: "Do not clone the authenticated user's or organization's starred repos (does not apply to organizations).")
    var noStarredRepos: Bool = false
    
    @Flag(help: "Do not clone the authenticated user's or organization's forked repos.")
    var noForkedRepos: Bool = false
    
    @Flag(help: "Do not clone the authenticated user's or organization's public gists.")
    var noPublicGists: Bool = false
    
    @Flag(help: "Do not clone the authenticated user's or organization's private gists.")
    var noPrivateGists: Bool = false
    
    @Flag(help: "Do not clone the authenticated user's starred gists (does not apply to organizations).")
    var noStarredGists: Bool = false
    
    @Flag(help: "Do not clone the authenticated user's forked gists (does not apply to organizations).")
    var noForkedGists: Bool = false
    
    @Flag(help: "Do not clone wikis associated with any repos that are cloned.")
    var noWikis: Bool = false
    
    @Flag(help: "Do not clone any repos.")
    var noRepos: Bool = false
    
    @Flag(help: "Do not clone any gists.")
    var noGists: Bool = false
    
    @Flag(help: "Only clone gists.")
    var onlyGists: Bool = false
    
    @Option(help: "Instead of fetching the list of the authenticated user's repos, fetch the specified organization's.")
    var organization: String?
    
    @Flag(help: "When cloning repos for a user, don't clone repos created by a user by owned by an organization.")
    var dedupeOrgReposCreatedByUser: Bool = false
}

extension Clone {
    func run() throws {
        logger.info("Starting clone...")
        
        let github = GitHub(accessToken: accessToken)

        if let organization = organization {
            switch github.synchronouslyAuthenticateUser(name: organization) {
            case .success(let org):
                let orgReposPath = "\(basePath)/\(organization)/\(reposSubpath)"
                let forkPath = "\(orgReposPath)/\(forkedSubpath)"
                let publicPath = "\(orgReposPath)/\(publicSubpath)"
                let privatePath = "\(orgReposPath)/\(privateSubpath)"
                
                do {
                    if !noForkedRepos {
                        try FileManager.default.createDirectory(atPath: forkPath, withIntermediateDirectories: true, attributes: nil)
                    }
                    if !noPublicRepos {
                        try FileManager.default.createDirectory(atPath: publicPath, withIntermediateDirectories: true, attributes: nil)
                    }
                    if !noPrivateRepos {
                        try FileManager.default.createDirectory(atPath: privatePath, withIntermediateDirectories: true, attributes: nil)
                    }
                } catch {
                    logger.error("Failed to create a required directory: \(error)")
                    return
                }
                
                guard let owner = org.login else {
                    logger.error("No user info returned for organization.")
                    return
                }
                switch github.synchronouslyFetchRepositories(owner: owner) {
                case .success(let repos):
                    for repo in repos {
                        if repo.isFork {
                            if noForkedRepos { continue }
                            guard let repoName = repo.name else {
                                logger.error("No name provided for repo with id \(repo.id).")
                                continue
                            }
                            let clonePath = "\(forkPath)/\(owner)"
                            if cloneRepo(repoName: repoName, sshURL: repo.sshURL!, clonePath: clonePath) {
                                do {
                                    let git = Git(path: clonePath)
                                    try git.run(.renameRemote(oldName: "origin", newName: "fork"))
                                    let parentRepo = repo.parent
                                    if remoteRepoExists(repoSSHURL: parentRepo!.sshURL!) {
                                        try git.run(.addRemote(name: "upstream", url: parentRepo!.sshURL!))
                                        try setDefaultBranch(git)
                                        let repoPath = "\(clonePath)/\(repoName)"
                                        github.tagRepo(repo: parentRepo!, clonePath: repoPath)
                                        if !noWikis {
                                            github.cloneWiki(repo: parentRepo!, clonePath: repoPath)
                                        }
                                    }
                                } catch {
                                    logger.error("Error handling forked repo: \(error)")
                                }
                            }
                        } else {
                            if repo.isPrivate {
                                if noPrivateRepos { continue }
                                github.cloneNonForkedRepo(repo: repo, repoTypePath: privatePath, noWikis: noWikis)
                            } else {
                                if noPublicRepos { continue }
                                github.cloneNonForkedRepo(repo: repo, repoTypePath: publicPath, noWikis: noWikis)
                            }
                        }
                    }
                case .failure(let error):
                    logger.error("Error fetching repositories: \(error)")
                }
            case .failure(let error):
                logger.error("Error fetching organization: \(error)")
            }
        } else {
            logger.info("Cloning for user...")
            switch github.synchronouslyAuthenticate() {
            case .success(let user):
                guard let userName = user.login else {
                    logger.error("No user name returned.")
                    return
                }
                let userReposPath = "\(basePath)/\(userName)/\(reposSubpath)"
                let forkPath = "\(userReposPath)/\(forkedSubpath)"
                let publicPath = "\(userReposPath)/\(publicSubpath)"
                let privatePath = "\(userReposPath)/\(privateSubpath)"
                let starredPath = "\(userReposPath)/\(starredSubpath)"
                
                do {
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
                } catch {
                    logger.error("Failed to create a required directory: \(error)")
                    return
                }
                
                guard let owner = user.login else {
                    logger.error("No user login info returned after authenticating.")
                    return
                }
                
                logger.info("Fetching repositories owned by \(owner).")
                
                switch github.synchronouslyFetchRepositories(owner: owner) {
                case .success(let repos):
                    logger.info("Retrieved list of repos to clone (\(repos.count) total).")
                    for repo in repos {
                        if repo.organization != nil && organization == nil && dedupeOrgReposCreatedByUser {
                            // the GitHub API only returns org repos that are owned by the authenticated user, so we skip this repo if it has any org ownership and we're cloning user repos
                            continue
                        }
                        if repo.isFork {
                            if noForkedRepos { continue }
                            github.cloneForkedRepo(repo: repo, forkPath: forkPath, noWikis: noWikis)
                        } else {
                            if repo.isPrivate {
                                if noPrivateRepos { continue }
                                github.cloneNonForkedRepo(repo: repo, repoTypePath: privatePath, noWikis: noWikis)
                            } else {
                                if noPublicRepos { continue }
                                github.cloneNonForkedRepo(repo: repo, repoTypePath: publicPath, noWikis: noWikis)
                            }
                        }
                    }
                case .failure(let error):
                    logger.error("Error authenticating user: \(error)")
                }
                
                if !noStarredRepos {
                    github.cloneStarredRepositories(owner, starredPath, noWikis: noWikis)
                }
            case .failure(let error):
                logger.error("Error fetching repositories: \(error)")
            }
        }
    }
}
