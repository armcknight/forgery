#!/usr/bin/env swift

import Foundation
import OctoKit
import ArgumentParser
import Logging
import GitKit

let organization = "organization"
let user = "user"

let publicSubpath = "public"
let privateSubpath = "private"
let forkedSubpath = "forked"
let starredSubpath = "starred"

let reposSubpath = "repos"
let gistsSubpath = "gists"

let jsonDecoder = JSONDecoder()
let urlSession = URLSession(configuration: .default)

public var logger = Logger(label: "forgery")

func cloneRepo(repoName: String, sshURL: String, clonePath: String) -> Bool {
    let repoPath = "\(clonePath)/\(repoName)"
    if !FileManager.default.fileExists(atPath: repoPath) {
        logger.info("Cloning \(sshURL)...")
        var git = Git(path: clonePath)
        do {
            try git.run(.clone(url: sshURL))
        } catch {
            logger.error("Failed to clone \(sshURL): \(error)")
            return false
        }
        if FileManager.default.fileExists(atPath: "\(repoPath)/.gitmodules") {
            git = Git(path: repoPath)
            do {
                try git.run(.submoduleUpdate(init: true, recursive: true))
            } catch {
                logger.error("Failed to retrieve submodules under \(sshURL): \(error)")
                return false
            }
        }
    } else {
        logger.info("\(sshURL) already cloned")
        return false
    }
    
    return true
}

func remoteRepoExists(repoSSHURL: String) -> Bool {
    let task = Process()
    task.launchPath = "/usr/bin/git"
    task.arguments = ["ls-remote", "-h", repoSSHURL]
    task.standardOutput = Pipe()
    task.standardError = Pipe()

    task.launch()
    task.waitUntilExit()

    return task.terminationStatus == 0
}

func cloneWiki(repo: Repository, clonePath: String) {
    if repo.hasWiki {
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
func tagRepo(repo: Repository, clonePath: String, clearFirst: Bool = false) {
    switch getRepositoryTopics(owner: repo.owner.name!, repo: repo.name!) {
    case .success(let tagList):
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
    case .failure(let error):
        fatalError("Failed to get topic list: \(error)")
    }
}

func cloneNonForkedRepo(repo: Repository, repoTypePath: String, noWikis: Bool, accessToken: String) {
    let clonePath = "\(repoTypePath)/\(repo.name!)"
    if cloneRepo(sshURL: repo.sshURL!, clonePath: clonePath) {
        tagRepo(repo: repo, clonePath: clonePath)
    }
    if !noWikis {
        cloneWiki(repo: repo, clonePath: clonePath)
    }
}

func getRepositoryTopics(owner: String, repo: String) -> Result<[String], Error> {
    let url = "https://api.github.com/repos/\(owner)/\(repo)/topics"
    var request = URLRequest(url: URL(string: url)!)
    request.httpMethod = "GET"
    request.addValue("application/vnd.github.mercy-preview+json", forHTTPHeaderField: "Accept")
    let result: Result<Data, RequestError> = synchronouslyRequest(request: request)
    switch result {
    case .success(let data):
        do {
            guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               let topics = json["names"] as? [String] else {
                return .failure(RequestError.noRepoTopics)
            }
            logger.info("Topics: \(topics)")
            return .success(topics)
        } catch {
            return .failure(error)
        }
    case .failure(let error):
        return .failure(error)
    }
}

public enum RequestError: Error, CustomStringConvertible {
    case clientError(Error)
    case httpError(URLResponse)
    case noData
    case invalidData
    case resultError
    case noRepoTopics
    
    public var description: String {
        switch self {
        case .clientError(let error): return "Request failed in client stack with error: \(error)."
        case .httpError(let response): return "Request failed with HTTP status \((response as! HTTPURLResponse).statusCode)."
        case .noData: return "Response contained no data."
        case .invalidData: return "Response data couldn't be decoded."
        case .resultError: return "The request completed successfully but a problem occurred returning the decoded response."
        case .noRepoTopics: return "The request response did not contain a list of repository topics at the expected keypath."
        }
    }
}

public func synchronouslyRequest<T: Decodable>(request: URLRequest) -> Result<T, RequestError> {
    var result: T?
    var requestError: RequestError?
    
    let group = DispatchGroup()
    group.enter()
    urlSession.dataTask(with: request) { data, response, error in
        defer {
            group.leave()
        }
        
        guard error == nil else {
            requestError = RequestError.clientError(error!)
            return
        }
        
        let status = (response as! HTTPURLResponse).statusCode
        
        guard status >= 200 && status < 300 else {
            requestError = RequestError.httpError(response!)
            return
        }
        
        guard let data else {
            requestError = RequestError.noData
            return
        }
        
        do {
            result = try jsonDecoder.decode(T.self, from: data)
        } catch {
            guard let responseDataString = String(data: data, encoding: .utf8) else {
                logger.warning("Response data can't be decoded to a string for debugging error from decoding response data from request to \(String(describing: request.url)) (original error: \(error)")
                requestError = RequestError.invalidData
                return
            }
            logger.error("Failed decoding API response from request to \(String(describing: request.url)): \(error) (string contents: \(responseDataString))")
            requestError = RequestError.invalidData
        }
    }.resume()
    group.wait()
    
    if let requestError {
        return .failure(requestError)
    }
    
    guard let result else {
        return .failure(RequestError.resultError)
    }
    
    return .success(result)
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
        
        tagRepo(repo: repoToSync, clonePath: repoPath, clearFirst: true)
        
        do {
            try git.run(.submoduleUpdate(init: true, recursive: true, rebase: rebaseSubmodules))
        } catch {
            logger.error("Error updating submodules for repo \(repo): \(error)")
        }
    }
}

func synchronouslyAuthenticate(client: Octokit) -> Result<User, Error> {
    var result: Result<User, Error>?
    let group = DispatchGroup()
    client.me {
        result = $0
        group.leave()
    }
    group.wait()
    
    guard let result else {
        return .failure(RequestError.resultError)
    }
    
    return result
}

func synchronouslyAuthenticateUser(client: Octokit, name: String) -> Result<User, Error> {
    var result: Result<User, Error>?
    let group = DispatchGroup()
    client.user(name: user) {
        result = $0
        group.leave()
    }
    group.wait()
    
    guard let result else {
        return .failure(RequestError.resultError)
    }
    
    return result
}

func synchronouslyFetchRepositories(client: Octokit, owner: String) -> Result<[Repository], Error> {
    var result: Result<[Repository], Error>?
    let group = DispatchGroup()
    client.repositories(owner: owner) {
        result = $0
        group.leave()
    }
    group.wait()
    
    guard let result else {
        return .failure(RequestError.resultError)
    }
    
    return result
}

func synchronouslyFetchStarredRepositories(client: Octokit, owner: String) -> Result<[Repository], Error> {
    var result: Result<[Repository], Error>?
    let group = DispatchGroup()
    client.starredRepositories(owner: owner) {
        result = $0
        group.leave()
    }
    group.wait()
    
    guard let result else {
        return .failure(RequestError.resultError)
    }
    
    return result
}

struct Status: ParsableCommand {
    @Argument(help: "Location of the repos for which to report statuses.")
    var basePath: String

    @Option(name: .shortAndLong, help: "The GitHub access token of the GitHub user whose repos private repos should be reported in addition to public repos.")
    var accessToken: String?

    func run() throws {
        let config = TokenConfiguration(accessToken)
        let client = Octokit(config)

        client.user(name: user) { response in
            switch response {
            case .success(_):
                // TODO: implement
                break
            case .failure(let error):
                fatalError("Error: \(error)")
            }
        }
    }
}

struct Sync: ParsableCommand {
    @Argument(help: "The GitHub access token of the GitHub user whose repos should be synced.")
    var accessToken: String

    @Argument(help: "Location of the repos to sync.")
    var basePath: String

    @Flag(name: .shortAndLong, help: "After fast-forwarding any new commits from forks' remote upstreams, push the new commits to fork remotes.")
    var pushToForkRemotes: Bool = false

    @Flag(name: .shortAndLong, help: "If a local repository is no longer listed from the server, remove its local clone.")
    var prune: Bool = false

    @Flag(name: .shortAndLong, help: "Run `git pull --rebase` to rebase any local commits on top of the remote HEAD.")
    var pullWithRebase: Bool = false

    @Flag(name: .shortAndLong, help: "If `--pull-with-rebase` is provided, push HEAD to remote after rebasing any local commits on top of pulled remote commits.")
    var pushAfterRebase: Bool = false

    @Flag(name: .shortAndLong, help: "If development has occurred in a submodule, the changes are rebased onto any updated submodule commit hash that is pulled down as part of updating the superproject.")
    var rebaseSubmodules: Bool = false

    func run() throws {
        let config = TokenConfiguration(accessToken)
        let client = Octokit(config)
        
        switch synchronouslyAuthenticateUser(client: client, name: user) {
        case .success(let user):
            let userDir = "\(basePath)/\(user.login!)"
            Task {
                do {
                    let remoteRepos = try await client.repositories(owner: user.login).map { $0 }
                    updateLocalReposUnder(path: userDir, remoteRepoList: remoteRepos, pushToForkRemotes: pushToForkRemotes, prune: prune, pullWithRebase: pullWithRebase, pushAfterRebase: pushAfterRebase, rebaseSubmodules: rebaseSubmodules)
                } catch {
                    logger.error("Error fetching repositories: \(error)")
                }
            }
        case .failure(let error):
            logger.error("Error authenticating user: \(error)")
        }
    }
}

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

    @Option(help: "Instead of fetching the list of the authenticated user's repos, fetch the specified organization's.")
    var organization: String?

    @Flag(help: "When cloning repos for a user, don't clone repos created by a user by owned by an organization.")
    var dedupeOrgReposCreatedByUser: Bool = false

    fileprivate func setDefaultBranch(_ git: Git) throws {
        let defaultBranch = try git.run(.revParse(abbrevRef: "fork/HEAD")).replacingOccurrences(of: "refs/remotes/fork/", with: "")
        try git.run(.config(name: "branch.\(defaultBranch).remote", value: "upstream"))
        try git.run(.config(name: "branch.\(defaultBranch).pushRemote", value: "fork"))
    }
    
    func run() throws {
        logger.info("Starting clone...")
        let config = TokenConfiguration(accessToken)
        let client = Octokit(config)

        if let organization = organization {
            switch synchronouslyAuthenticateUser(client: client, name: organization) {
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
                switch synchronouslyFetchRepositories(client: client, owner: owner) {
                case .success(let repos):
                    for repo in repos {
                        if repo.isFork {
                            if noForkedRepos { continue }
                            guard let repoName = repo.name else {
                                logger.error("No name provided for repo with id \(repo.id).")
                                continue
                            }
                            let clonePath = "\(forkPath)/\(owner)/\(repoName)"
                            if cloneRepo(sshURL: repo.sshURL!, clonePath: clonePath) {
                                do {
                                    let git = Git(path: clonePath)
                                    try git.run(.renameRemote(oldName: "origin", newName: "fork"))
                                    let parentRepo = repo.parent
                                    if remoteRepoExists(repoSSHURL: parentRepo!.sshURL!) {
                                        try git.run(.addRemote(name: "upstream", url: parentRepo!.sshURL!))
                                        try setDefaultBranch(git)
                                        tagRepo(repo: parentRepo!, clonePath: clonePath)
                                        if !noWikis {
                                            cloneWiki(repo: parentRepo!, clonePath: clonePath)
                                        }
                                    }
                                } catch {
                                    logger.error("Error handling forked repo: \(error)")
                                }
                            }
                        } else {
                            if repo.isPrivate {
                                if noPrivateRepos { continue }
                                cloneNonForkedRepo(repo: repo, repoTypePath: privatePath, noWikis: noWikis, accessToken: accessToken)
                            } else {
                                if noPublicRepos { continue }
                                cloneNonForkedRepo(repo: repo, repoTypePath: publicPath, noWikis: noWikis, accessToken: accessToken)
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
            switch synchronouslyAuthenticate(client: client) {
            case .success(let user):
                let userReposPath = "\(basePath)/\(user)/\(reposSubpath)"
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
                switch synchronouslyFetchRepositories(client: client, owner: owner) {
                case .success(let repos):
                    logger.info("Retrieved list of repos to clone (\(repos.count) total).")
                    for repo in repos {
                        if repo.organization != nil && organization == nil && dedupeOrgReposCreatedByUser {
                            // the GitHub API only returns org repos that are owned by the authenticated user, so we skip this repo if it has any org ownership and we're cloning user repos
                            continue
                        }
                        if repo.isFork {
                            if noForkedRepos { continue }
                            guard let parentRepo = repo.parent else {
                                logger.error("No parent repo information provided for repo with id \(repo.id).")
                                continue
                            }
                            guard let repoName = repo.name else {
                                logger.error("No name provided for forked repo with id \(repo.id).")
                                continue
                            }
                            guard let parentOwner = parentRepo.owner.login else {
                                logger.error("No owner info returned for parent repo with id \(parentRepo.id).")
                                continue
                            }
                            let clonePath = "\(forkPath)/\(parentOwner)/\(repoName)"
                            if cloneRepo(sshURL: repo.sshURL!, clonePath: clonePath) {
                                do {
                                    let git = Git(path: clonePath)
                                    try git.run(.renameRemote(oldName: "origin", newName: "fork"))
                                    guard let parentURL = parentRepo.sshURL else {
                                        logger.error("No SSH URL provided for parent repo with id \(parentRepo.id).")
                                        return
                                    }
                                    guard remoteRepoExists(repoSSHURL: parentURL) else {
                                        logger.error("Could not verify existence of remote parent repo at \(parentURL).")
                                        return
                                    }
                                    try git.run(.addRemote(name: "upstream", url: parentURL))
                                    try setDefaultBranch(git)
                                    tagRepo(repo: parentRepo, clonePath: clonePath)
                                    if !noWikis {
                                        cloneWiki(repo: parentRepo, clonePath: clonePath)
                                    }
                                } catch {
                                    logger.error("Error handling forked repo: \(error)")
                                }
                            }
                        } else {
                            if repo.isPrivate {
                                if noPrivateRepos { continue }
                                cloneNonForkedRepo(repo: repo, repoTypePath: privatePath, noWikis: noWikis, accessToken: accessToken)
                            } else {
                                if noPublicRepos { continue }
                                cloneNonForkedRepo(repo: repo, repoTypePath: publicPath, noWikis: noWikis, accessToken: accessToken)
                            }
                        }
                    }
                    
                    if !noStarredRepos {
                        switch synchronouslyFetchStarredRepositories(client: client, owner: owner) {
                        case .success(let repos):
                            for repo in repos {
                                guard let owner = repo.owner.login else {
                                    logger.error("No owner info returned for starred repo with id \(repo.id).")
                                    continue
                                }
                                cloneNonForkedRepo(repo: repo, repoTypePath: "\(starredPath)/\(owner)", noWikis: noWikis, accessToken: accessToken)
                            }
                        case .failure(let error):
                            logger.error("Error fetching starred repositories: \(error)")
                        }
                    }
                case .failure(let error):
                    logger.error("Error authenticating user: \(error)")
                }
            case .failure(let error):
                logger.error("Error fetching repositories: \(error)")
            }
        }
    }
}

struct Forgery: ParsableCommand {
    static let configuration = CommandConfiguration(
        subcommands: [Status.self, Sync.self, Clone.self],
        defaultSubcommand: Status.self
    )
}

Forgery.main()

func shell(_ command: String, workingDirectory: String? = nil) -> String {
    let task = Process()
    task.launchPath = "/bin/bash"
    task.arguments = ["-c", command]

    if let workingDirectory = workingDirectory {
        task.currentDirectoryPath = workingDirectory
    }

    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe

    task.launch()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""

    return output.trimmingCharacters(in: .whitespacesAndNewlines)
}
