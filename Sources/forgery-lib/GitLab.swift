import Foundation
import GitLabSwift

public struct GitLab {
    let client: GLApi
    
    public init(accessToken: String) {
        client = GLApi(config: .init(baseURL: "https://gitlab.com/api/v4") {
            $0.token = accessToken
        })
    }
}

public extension GitLab {
    
    // MARK: Cloning
    
    func cloneForUser(basePath: String, repoTypes: RepoTypeOptions.Resolved, organization: String?) async throws {
        logger.info("Cloning for user...")
        
        let user = try await client.users.me().decode()
        
        guard let username = user?.username else {
            logger.error("No user login info returned after authenticating.")
            return
        }
        
        let userPaths = UserPaths(basePath: basePath, username: username)
        try userPaths.createOnDisk(repoTypes: repoTypes)
        
        if !repoTypes.noNonstarredRepos {
            logger.info("Fetching repositories owned by \(username).")
            
            if let projects = try await client.projects.list(options: {
                $0.owned = true
            }).decode() {
                
                logger.info("Retrieved list of projects to clone (\(projects.count) total).")
                
                for project in projects {
                    // TODO: implement gitlab organizations; starting with individual users
//                    if repo.organization != nil && organization == nil && repoTypes.dedupeOrgReposCreatedByUser {
//                        // the GitHub API only returns org repos that are owned by the authenticated user, so we skip this repo if it's owned by an org owned by the user, and we have deduping selected
//                        continue
//                    }
                    
                    guard let sshURL = project.ssh_url_to_repo else {
                        continue
                    }
                    let name = project.name
                    try cloneRepo(repoName: name, sshURL: sshURL.absoluteString, cloneRoot: userPaths.commonPaths.repoPaths.publicPath)
                    
//                    do {
//                        try cloneRepoType(repo: project, paths: userPaths.commonPaths, repoTypes: repoTypes)
//                    } catch {
//                        logger.error("Failed to clone repo \(String(describing: repo.fullName)): \(error)")
//                    }
                }
            }
        }
        
        // TODO: starred projects
//        if !repoTypes.noStarredRepos {
//            let repos = try getStarredRepos(starredBy: username)
//            for repo in repos {
//                guard let owner = repo.owner.login else {
//                    logger.error("No owner info returned for starred repo with id \(repo.id).")
//                    continue
//                }
//                do {
//                    try cloneNonForkedRepo(repo: repo, cloneRoot: "\(userPaths.starredRepoPath)/\(owner)", noWikis: repoTypes.noWikis)
//                } catch {
//                    logger.error("Failed to clone starred repo \(String(describing: repo.fullName)): \(error)")
//                }
//            }
//        }
        
        // TODO: snippets (gist:github::snippet:gitlab)
//        if !repoTypes.noNonstarredGists {
//            let gists = try getGists()
//            for gist in gists {
//                do {
//                    
//                    try cloneGistType(gist: gist, paths: userPaths, repoTypes: repoTypes)
//                } catch {
//                    logger.error("Failed to clone gist \(gist.fullName!): \(error)")
//                }
//            }
//        }
//        
//        if !repoTypes.noStarredGists {
//            let gists = try getStarredGists()
//            for gist in gists {
//                guard let owner = gist.owner?.login else {
//                    logger.error("No owner info returned for starred gist with id \(String(describing: gist.id)).")
//                    continue
//                }
//                try cloneNonForkedGist(gist: gist, cloneRoot: "\(userPaths.starredGistPath)/\(owner)")
//            }
//        }
    }
}
