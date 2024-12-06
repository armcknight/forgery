import Foundation
import GitKit
import OctoKit

struct GitHub {
    let client: Octokit
    
    init(accessToken: String) {
        client = Octokit(.init(accessToken))
    }
    
    func cloneWiki(repo: Repository, clonePath: String) {
        guard let hasWiki = repo.hasWiki else {
            logger.notice("Repository \(String(describing: repo.name)) didn't contain has_wiki property.")
            return
        }
        if hasWiki {
            let wikiURL = "git@github.com:\(repo.fullName!).wiki.git"
            if remoteRepoExists(repoSSHURL: wikiURL) {
                let wikiPath = "\(clonePath).wiki"
                if !FileManager.default.fileExists(atPath: wikiPath) {
                    logger.info("Cloning \(wikiURL)...")
                    do {
                        try Git(path: wikiPath).run(.clone(url: wikiURL))
                    } catch {
                        logger.error("Failed to clone wiki at \(wikiURL): \(error)")
                    }
                } else {
                    logger.info("\(wikiURL) already cloned")
                }
            }
        }
    }

    /// Use the https://github.com/jdberry/tag/ tool to add macOS tags to the directory containing the repo.
    func tagRepo(repo: Repository, clonePath: String, clearFirst: Bool = false) throws {
        guard let owner = repo.owner.login else {
            logger.error("Repo owner not available.")
            return
        }
        guard let name = repo.name else {
            logger.error("Repo name not available.")
            return
        }
        let tagList = try synchronouslyFetchRepositoryTopics(owner: owner, repo: name)
        var mutableTopicList = [String](tagList)
        if let language = repo.language {
            mutableTopicList.append(language.lowercased())
        }
        if clearFirst {
            let currentTags = shell("tag --no-name \(clonePath)")
            let _ = shell("tag -r \"\(currentTags)\"")
        }
        let newTags = mutableTopicList.joined(separator: ",")
        let _ = shell("tag -a \"\(newTags)\" \(clonePath)")
    }

    func cloneNonForkedRepo(repo: Repository, repoTypePath: String, noWikis: Bool) throws {
        guard let name = repo.name else {
            logger.error("No name provided for the repo (id \(repo.id)).")
            return
        }
        guard let sshURL = repo.sshURL else {
            logger.error("No SSH URL provided for \(name).");
            return
        }
        if cloneRepo(repoName: name, sshURL: sshURL, clonePath: repoTypePath) {
            try tagRepo(repo: repo, clonePath: "\(repoTypePath)/\(name)")
        }
        if !noWikis {
            cloneWiki(repo: repo, clonePath: repoTypePath)
        }
    }

    func updateLocalReposUnder(path: String, remoteRepoList: [Repository], pushToForkRemotes: Bool, prune: Bool, pullWithRebase: Bool, pushAfterRebase: Bool, rebaseSubmodules: Bool, publicRepos: Bool = false, privateRepos: Bool = false, forked: Bool = false, gist: Bool = false, starred: Bool = false) {
        guard FileManager.default.fileExists(atPath: path) else { return }
        
        for repo in try! FileManager.default.contentsOfDirectory(atPath: path) {
            let repoPath = "\(path)/\(repo)"
            if !FileManager.default.fileExists(atPath: repoPath) { continue }
            
            let repoToSync = remoteRepoList.first { $0.name == repo }
            guard let repoToSync = repoToSync else {
                if prune {
                    do {
                        try FileManager.default.removeItem(atPath: repoPath)
                    } catch {
                        logger.error("Error pruning repo \(repo): \(error)")
                    }
                }
                continue
            }
            
            let git = Git(path: repoPath)
            
            if forked {
                do {
                    try git.run(.fetch(remote: "fork"))
                    try git.run(.pull(remote: "fork", rebase: pullWithRebase))
                    try git.run(.fetch(remote: "upstream"))
                    try git.run(.pull(remote: "upstream", rebase: pullWithRebase))
                    if pushToForkRemotes {
                        try git.run(.push(remote: "fork"))
                    }
                } catch {
                    logger.error("Error syncing forked repo \(repo): \(error)")
                }
            } else {
                do {
                    try git.run(.fetch(remote: "origin"))
                    try git.run(.pull(remote: "origin", rebase: pullWithRebase))
                    if pushAfterRebase {
                        try git.run(.push(remote: "origin"))
                    }
                } catch {
                    logger.error("Error syncing repo \(repo): \(error)")
                }
            }
            
            do {
                try tagRepo(repo: repoToSync, clonePath: repoPath, clearFirst: true)
            } catch {
                logger.error("Failed to tag repo with GitHub topics")
            }
            
            do {
                try git.run(.submoduleUpdate(init: true, recursive: true, rebase: rebaseSubmodules))
            } catch {
                logger.error("Error updating submodules for repo \(repo): \(error)")
            }
        }
    }

    func synchronouslyAuthenticate() throws -> User {
        var result: Result<User, Error>?
        let group = DispatchGroup()
        group.enter()
        client.me {
            result = $0
            group.leave()
        }
        group.wait()
        
        guard let result else {
            throw RequestError.resultError
        }
        
        switch result {
        case .failure(let error): throw error
        case .success(let user): return user
        }
    }

    func synchronouslyAuthenticateUser(name: String) throws -> User {
        var result: Result<User, Error>?
        let group = DispatchGroup()
        group.enter()
        client.user(name: user) {
            result = $0
            group.leave()
        }
        group.wait()
        
        guard let result else {
            throw RequestError.resultError
        }
        
        switch result {
        case .failure(let error): throw error
        case .success(let user): return user
        }
    }

    func synchronouslyFetchRepositories(owner: String) throws -> [Repository] {
        var result: Result<[Repository], Error>?
        let group = DispatchGroup()
        group.enter()
        client.repositories(owner: owner) {
            result = $0
            group.leave()
        }
        group.wait()
        
        guard let result else {
            throw RequestError.resultError
        }
        
        switch result {
        case .failure(let error): throw error
        case .success(let repos): return repos
        }
    }

    func synchronouslyReadRepository(owner: String, repoName: String) throws -> Repository {
        var result: Result<Repository, Error>?
        let group = DispatchGroup()
        group.enter()
        client.repository(owner: owner, name: repoName) {
            result = $0
            group.leave()
        }
        group.wait()
        
        guard let result else {
            throw RequestError.resultError
        }
        
        switch result {
        case .failure(let error): throw error
        case .success(let repo): return repo
        }
    }

    func synchronouslyFetchStarredRepositories(owner: String) throws -> [Repository] {
        var result: Result<[Repository], Error>?
        let group = DispatchGroup()
        group.enter()
        client.stars(name: owner) {
            result = $0
            group.leave()
        }
        group.wait()
        
        guard let result else {
            throw RequestError.resultError
        }
        
        switch result {
        case .failure(let error): throw error
        case .success(let repos): return repos
        }
    }

    func synchronouslyFetchRepositoryTopics(owner: String, repo: String) throws -> [String] {
        var result: Result<Topics, Error>?
        
        let group = DispatchGroup()
        group.enter()
        
        client.repositoryTopics(owner: owner, name: repo) {
            result = $0
            group.leave()
        }
        group.wait()
        
        switch result {
        case .success(let topics):
            logger.info("Topics: \(topics.names)")
            return topics.names
        case .failure(let error):
            logger.error("Topic fetch failed: \(error)")
            throw RequestError.noRepoTopics
        case .none:
            throw RequestError.noRepoTopics
        }
    }
    
    func cloneStarredRepositories(_ owner: String, _ starredPath: String, noWikis: Bool) throws {
        let repos = try synchronouslyFetchStarredRepositories(owner: owner)
        for repo in repos {
            guard let owner = repo.owner.login else {
                logger.error("No owner info returned for starred repo with id \(repo.id).")
                continue
            }
            try cloneNonForkedRepo(repo: repo, repoTypePath: "\(starredPath)/\(owner)", noWikis: noWikis)
        }
    }
    
    func cloneForkedRepo(repo: Repository, forkPath: String, noWikis: Bool) throws {
        guard let owner = repo.owner.login else {
            logger.error("No owner login available for forked repo.")
            return
        }
        guard let repoName = repo.name else {
            logger.error("No name available for forked repo.")
            return
        }
        let repo = try synchronouslyReadRepository(owner: owner, repoName: repoName)
        guard let parentRepo = repo.parent else {
            logger.error("No parent repo information provided for forked repo \(owner)/\(repoName) (id \(repo.id)).")
            return
        }
        guard let repoName = repo.name else {
            logger.error("No name provided for forked repo \(owner)/\(repoName) (id \(repo.id)).")
            return
        }
        guard let parentOwner = parentRepo.owner.login else {
            logger.error("No owner info returned for parent of forked repo \(owner)/\(repoName) (id \(repo.id); parent id \(parentRepo.id).")
            return
        }
        let clonePath = "\(forkPath)/\(parentOwner)"
        if cloneRepo(repoName: repo.name!, sshURL: repo.sshURL!, clonePath: clonePath) {
            do {
                let repoPath = "\(clonePath)/\(repoName)"
                let git = Git(path: repoPath)
                logger.info("Renaming origin to fork.")
                try git.run(.renameRemote(oldName: "origin", newName: "fork"))
                guard let parentURL = parentRepo.sshURL else {
                    logger.error("No SSH URL provided for parent repo with id \(parentRepo.id).")
                    return
                }
                guard remoteRepoExists(repoSSHURL: parentURL) else {
                    logger.error("Could not verify existence of remote parent repo at \(parentURL).")
                    return
                }
                logger.info("Adding upstream remote.")
                try git.run(.addRemote(name: "upstream", url: parentURL))
                logger.info("Setting default branch.")
                try setDefaultForkBranchRemotes(git)
                try tagRepo(repo: parentRepo, clonePath: repoPath)
                if !noWikis {
                    cloneWiki(repo: parentRepo, clonePath: repoPath)
                }
            } catch {
                logger.error("Error handling forked repo: \(error)")
            }
        }
    }
    
    func cloneRepoType(repo: Repository, paths: Paths, repoTypes: RepoTypes) throws {
        if repo.isFork {
            if repoTypes.contains(.noForks) { return }
            try cloneForkedRepo(repo: repo, forkPath: paths.forkPath, noWikis: repoTypes.contains(.noWikis))
        } else {
            if repo.isPrivate {
                if repoTypes.contains(.noPrivate) { return }
                try cloneNonForkedRepo(repo: repo, repoTypePath: paths.privatePath, noWikis: repoTypes.contains(.noWikis))
            } else {
                if repoTypes.contains(.noPublic) { return }
                try cloneNonForkedRepo(repo: repo, repoTypePath: paths.publicPath, noWikis: repoTypes.contains(.noWikis))
            }
        }
    }
}
