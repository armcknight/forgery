#!/usr/bin/env swift

import Foundation
import ArgumentParser
import Logging

struct RepoTypes: OptionSet {
    let rawValue: Int
    
    static let noForks = RepoTypes(rawValue: 1 << 0)
    static let noPrivate = RepoTypes(rawValue: 1 << 1)
    static let noPublic = RepoTypes(rawValue: 1 << 2)
    // starred repos are fetched differently from github, so are handled differently in the logic that uses RepoTypes; we don't need an option for them here
    
    static let noWikis = RepoTypes(rawValue: 1 << 3)
    static let noGists = RepoTypes(rawValue: 1 << 4)

    static let noForkedGists = RepoTypes(rawValue: 1 << 5)
    static let noPrivateGists = RepoTypes(rawValue: 1 << 6)
    static let noPublicGists = RepoTypes(rawValue: 1 << 7)
    // starred gists are fetched differently from github, so are handled differently in the logic that uses RepoTypes; we don't need an option for them here
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
