import Foundation
import GitKit
import OctoKit

public struct GitHub {
    let client: Octokit
    
    public init(accessToken: String) {
        client = Octokit(.init(accessToken))
    }
}

// MARK: API
public extension GitHub {
    /// Authenticate the user whose access token was used to initialize this client instance
    func authenticate() throws -> User {
        try synchronouslyAuthenticate()
    }
    
    /// Orgs cannot own access tokens, only people belonging to the org. So, in order to authenticate to access private org data, that user's access token is used to initialize the client instance, then the client authenticates with the org name.
    func authenticateOrg(name: String) throws -> User {
        try synchronouslyAuthenticateUser(name: name)
    }
    
    // MARK: Repos
    
    func getRepos(ownedBy owner: String) throws -> [Repository] {
        try synchronouslyFetchRepositories(owner: owner)
    }
    
    func getStarredRepos(starredBy username: String) throws -> [Repository] {
        try synchronouslyFetchStarredRepositories(username: username)
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
    
    func cloneWiki(repo: Repository, cloneRoot: String) {
        guard let hasWiki = repo.hasWiki else {
            logger.notice("Repository \(String(describing: repo.name)) didn't contain has_wiki property.")
            return
        }
        if hasWiki {
            let wikiURL = "git@github.com:\(repo.fullName!).wiki.git"
            
            if remoteRepoExists(repoSSHURL: wikiURL) {
                let wikiPath = "\(cloneRoot).wiki"
                if !FileManager.default.fileExists(atPath: wikiPath) {
                    logger.info("Cloning \(wikiURL)...")
                    do {
                        try Git(path: wikiPath).run(.clone(url: wikiURL))
                    } catch {
                        logger.error("Failed to clone wiki for \(String(describing: repo.fullName)): \(error)")
                    }
                } else {
                    logger.info("\(wikiURL) already cloned")
                }
            }
        }
    }
    
    func cloneNonForkedRepo(repo: Repository, cloneRoot: String, noWikis: Bool) throws {
        guard let name = repo.name else {
            logger.error("No name provided for the repo (id \(repo.id)).")
            return
        }
        guard let sshURL = repo.sshURL else {
            logger.error("No SSH URL provided for \(name).");
            return
        }
        
        try cloneRepo(repoName: name, sshURL: sshURL, cloneRoot: cloneRoot)
        try tagRepo(repo: repo, clonePath: "\(cloneRoot)/\(name)")
        
        if !noWikis {
            cloneWiki(repo: repo, cloneRoot: cloneRoot)
        }
    }
    
    func cloneForkedRepo(repo: Repository, forkPath: String, noWikis: Bool) throws {
        guard let owner = repo.owner.login else {
            throw ForgeryError.Clone.Repo.noOwnerLogin
        }
        guard let repoName = repo.name else {
            throw ForgeryError.Clone.Repo.noName
        }
        let repo = try synchronouslyReadRepository(owner: owner, repoName: repoName)
        guard let parentRepo = repo.parent else {
            throw ForgeryError.Clone.Repo.noForkParent
        }
        guard let parentOwner = parentRepo.owner.login else {
            throw ForgeryError.Clone.Repo.noForkParentLogin
        }
        let cloneRoot = "\(forkPath)/\(parentOwner)"
        guard let sshURL = repo.sshURL else {
            throw ForgeryError.Clone.Repo.noSSHURL
        }
        try cloneRepo(repoName: repoName, sshURL: sshURL, cloneRoot: cloneRoot)
        let repoPath = "\(cloneRoot)/\(repoName)"
        let git = Git(path: repoPath)
        logger.info("Renaming origin to fork.")
        try git.run(.renameRemote(oldName: "origin", newName: "fork"))
        guard let parentURL = parentRepo.sshURL else {
            throw ForgeryError.Clone.Repo.noForkParentSSHURL
        }
        guard remoteRepoExists(repoSSHURL: parentURL) else {
            throw ForgeryError.Clone.Repo.couldNotFetchRepo
        }
        logger.info("Adding upstream remote.")
        try git.run(.addRemote(name: "upstream", url: parentURL))
        logger.info("Setting default branch.")
        try setDefaultForkBranchRemotes(git)
        try tagRepo(repo: parentRepo, clonePath: repoPath)
        if !noWikis {
            cloneWiki(repo: parentRepo, cloneRoot: repoPath)
        }
    }
    
    func cloneRepoType(repo: Repository, paths: CommonPaths, repoTypes: RepoTypes) throws {
        if repo.isFork {
            if repoTypes.contains(.noForks) { return }
            try cloneForkedRepo(repo: repo, forkPath: paths.repoPaths.forkPath, noWikis: repoTypes.contains(.noWikis))
        } else {
            if repo.isPrivate {
                if repoTypes.contains(.noPrivate) { return }
                try cloneNonForkedRepo(repo: repo, cloneRoot: paths.repoPaths.privatePath, noWikis: repoTypes.contains(.noWikis))
            } else {
                if repoTypes.contains(.noPublic) { return }
                try cloneNonForkedRepo(repo: repo, cloneRoot: paths.repoPaths.publicPath, noWikis: repoTypes.contains(.noWikis))
            }
        }
    }
    
    // MARK: Syncing repos
    
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
    
    // MARK: Gists
    
    func getGists() throws -> [Gist] {
        try synchronouslyFetchUserGists()
    }
    
    func getStarredGists() throws -> [Gist] {
        try synchronouslyFetchUserStarredGists()
    }
    
    func cloneGistType(gist: Gist, paths: UserPaths, repoTypes: RepoTypes) throws {
        guard let id = gist.id else {
            throw ForgeryError.Clone.Gist.noID
        }
        let fullyFetchedGist = try synchronouslyReadGist(id: id)
        
        if fullyFetchedGist.forkOf != nil {
            if repoTypes.contains(.noForkedGists) { return }
            try cloneForkedGist(gist: fullyFetchedGist, forkPath: paths.forkedGistPath)
        } else {
            guard let isPublic = fullyFetchedGist.publicGist else {
                throw ForgeryError.Clone.Gist.noGistAccessInfo
            }
            if isPublic {
                if repoTypes.contains(.noPublicGists) { return }
                try cloneNonForkedGist(gist: fullyFetchedGist, cloneRoot: paths.commonPaths.gistPaths.publicPath)
            } else {
                if repoTypes.contains(.noPrivateGists) { return }
                try cloneNonForkedGist(gist: fullyFetchedGist, cloneRoot: paths.commonPaths.gistPaths.privatePath)
            }
        }
    }
    
    func cloneForkedGist(gist: Gist, forkPath: String) throws {
        guard let id = gist.id else {
            throw ForgeryError.Clone.Gist.noID
        }
        let gistInfo = try synchronouslyReadGist(id: id)
        guard let parentGist = gistInfo.forkOf else {
            throw ForgeryError.Clone.Gist.noForkParent
        }
        guard let gistTitle = gistInfo.name else {
            throw ForgeryError.Clone.Gist.noName
        }
        guard let parentOwner = parentGist.owner?.login else {
            throw ForgeryError.Clone.Gist.noForkOwnerLogin
        }
        let cloneRoot = "\(forkPath)/\(parentOwner)"
        guard let pullURL = gistInfo.gitPullURL else {
            throw ForgeryError.Clone.Gist.noPullURL
        }
        try cloneRepo(repoName: gistTitle, sshURL: pullURL.absoluteString, cloneRoot: cloneRoot)
        let repoPath = "\(cloneRoot)/\(gistTitle)"
        let git = Git(path: repoPath)
        logger.info("Renaming origin to fork.")
        try git.run(.renameRemote(oldName: "origin", newName: "fork"))
        guard let parentURL = parentGist.gitPullURL else {
            throw ForgeryError.Clone.Gist.noForkParentPullURL
        }
        guard remoteRepoExists(repoSSHURL: parentURL.absoluteString) else {
            throw ForgeryError.Clone.Gist.couldNotFetchForkParent
        }
        logger.info("Adding upstream remote.")
        try git.run(.addRemote(name: "upstream", url: parentURL.absoluteString))
        logger.info("Setting default branch.")
        try setDefaultForkBranchRemotes(git)
    }
    
    func cloneNonForkedGist(gist: Gist, cloneRoot: String) throws {
        guard let fileName = gist.name else {
            throw ForgeryError.Clone.Gist.noName
        }
        guard let pullURL = gist.gitPullURL else {
            throw ForgeryError.Clone.Gist.noPullURL
        }
        
        try cloneRepo(repoName: fileName, sshURL: pullURL.absoluteString, cloneRoot: cloneRoot)
    }
}

public extension Gist {
    /// A canonical path to the gist that mimics a repo's: owner/repoName
    var fullName: String? {
        guard let owner = owner?.login else { return nil }
        return "\(owner)/\(name!)"
    }
    
    var name: String? {
        files.first?.1.filename ?? id
    }
}

// MARK: GitHub Networking
private extension GitHub {
    
    // MARK: GitHub auth requests
    
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
        client.user(name: name) {
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

    // MARK: GitHub repo requests
    
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

    func synchronouslyFetchStarredRepositories(username: String) throws -> [Repository] {
        var result: Result<[Repository], Error>?
        let group = DispatchGroup()
        group.enter()
        client.stars(name: username) {
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
        
        guard let result else {
            throw RequestError.resultError
        }
        
        switch result {
        case .success(let topics): return topics.names
        case .failure(let error): throw error
        }
    }
    
    // MARK: GitHub gist requests
    
    func synchronouslyFetchUserGists() throws -> [Gist] {
        var result: Result<[Gist], Error>?
        let group = DispatchGroup()
        group.enter()
        client.myGists {
            result = $0
            group.leave()
        }
        group.wait()
        
        guard let result else {
            throw RequestError.resultError
        }
        
        switch result {
        case .success(let gists): return gists
        case .failure(let error): throw error
        }
    }
    
    func synchronouslyFetchUserStarredGists() throws -> [Gist] {
        var result: Result<[Gist], Error>?
        let group = DispatchGroup()
        group.enter()
        client.myStarredGists {
            result = $0
            group.leave()
        }
        group.wait()
        
        guard let result else {
            throw RequestError.resultError
        }
        
        switch result {
        case .success(let gists): return gists
        case .failure(let error): throw error
        }
    }
    
    func synchronouslyFetchOrgGists(owner: String) throws -> [Gist] {
        var result: Result<[Gist], Error>?
        let group = DispatchGroup()
        group.enter()
        client.gists(owner: owner) {
            result = $0
            group.leave()
        }
        group.wait()
        
        guard let result else {
            throw RequestError.resultError
        }
        
        switch result {
        case .success(let gists): return gists
        case .failure(let error): throw error
        }
    }
    
    func synchronouslyReadGist(id: String) throws -> Gist {
        var result: Result<Gist, Error>?
        let group = DispatchGroup()
        group.enter()
        client.gist(id: id) {
            result = $0
            group.leave()
        }
        group.wait()
        
        guard let result else {
            throw RequestError.resultError
        }
        
        switch result {
        case .failure(let error): throw error
        case .success(let gist): return gist
        }
    }}
