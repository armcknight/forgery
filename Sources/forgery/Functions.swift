import Foundation
import GitKit
import OctoKit

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
    guard let owner = repo.owner.login else {
        logger.error("Repo owner not available.")
        return
    }
    guard let name = repo.name else {
        logger.error("Repo name not available.")
        return
    }
    switch getRepositoryTopics(owner: owner, repo: name) {
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
    guard let name = repo.name else {
        logger.error("No name provided for the repo (id \(repo.id)).")
        return
    }
    guard let sshURL = repo.sshURL else {
        logger.error("No SSH URL provided for \(name).");
        return
    }
    if cloneRepo(repoName: name, sshURL: sshURL, clonePath: repoTypePath) {
        tagRepo(repo: repo, clonePath: "\(repoTypePath)/\(name)")
    }
    if !noWikis {
        cloneWiki(repo: repo, clonePath: repoTypePath)
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
    group.enter()
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
    group.enter()
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
    group.enter()
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

func synchronouslyReadRepository(client: Octokit, owner: String, repoName: String) -> Result<Repository, Error> {
    var result: Result<Repository, Error>?
    let group = DispatchGroup()
    group.enter()
    client.repository(owner: owner, name: repoName) {
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
    group.enter()
    client.stars(name: owner) {
        result = $0
        group.leave()
    }
    group.wait()
    
    guard let result else {
        return .failure(RequestError.resultError)
    }
    
    return result
}

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
