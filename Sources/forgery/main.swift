#!/usr/bin/env swift

import Foundation
import ArgumentParser
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

struct RepoTypes: OptionSet {
    let rawValue: Int
    
    static let noForks = RepoTypes(rawValue: 1 << 0)
    static let noPrivate = RepoTypes(rawValue: 1 << 1)
    static let noPublic = RepoTypes(rawValue: 1 << 2)
    static let noStarred = RepoTypes(rawValue: 1 << 3)
    
    static let noWikis = RepoTypes(rawValue: 1 << 4)
    
    static let noForkedGists = RepoTypes(rawValue: 1 << 5)
    static let noPrivateGists = RepoTypes(rawValue: 1 << 6)
    static let noPublicGists = RepoTypes(rawValue: 1 << 7)
    static let noStarredGists = RepoTypes(rawValue: 1 << 8)
    
    var noNonstarredRepos: Bool {
        contains(.noForks) && contains(.noPublic) && contains(.noPrivate)
    }
    
    var noNonstarredGists: Bool {
        contains(.noForkedGists) && contains(.noPublicGists) && contains(.noPrivateGists)
    }
}

/**
 * Paths for different repository types that could exist for either users or orgs. Orgs cannot have starred repositories, so there is no property for that in this struct. See the sibling property for it in `UserPaths`.`
 */
struct RepoPaths {
    let forkPath: String
    let publicPath: String
    let privatePath: String
}

/**
 * Paths for different repository types that could exist for either users or orgs. Orgs cannot have forked or starred gists, so there is no property for that in this struct. See the sibling properties for them in `UserPaths`.`
 */
struct GistPaths {
    let publicPath: String
    let privatePath: String
}

struct CommonPaths {
    let repoPaths: RepoPaths
    let gistPaths: GistPaths
}

/**
 * Paths for different repo and gist types that a user can have.
 */
struct UserPaths {
    let commonPaths: CommonPaths
    
    /// - note; Only users can have starred repos, so it exists as a separate property here as opposed to living in the common RepoPaths struct property.
    let starredRepoPath: String
    
    /// - note: Only users can have forked gists, so it exists as a separate property here as opposed to living in the common GistPaths struct property.
    let forkedGistPath: String
    
    /// - note: Only users can have starred gists, so it exists as a separate property here as opposed to living in the common GistPaths struct property.
    let starredGistPath: String
}

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

struct Forgery: ParsableCommand {
    static let configuration = CommandConfiguration(
        subcommands: [Status.self, Sync.self, Clone.self],
        defaultSubcommand: Status.self
    )
}

Forgery.main()
