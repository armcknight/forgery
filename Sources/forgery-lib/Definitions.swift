import Foundation
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

let organization = "organization"
public let user = "user"

let publicSubpath = "public"
let privateSubpath = "private"
let forkedSubpath = "forked"
let starredSubpath = "starred"

let reposSubpath = "repos"
let gistsSubpath = "gists"

let jsonDecoder = JSONDecoder()
let urlSession = URLSession(configuration: .default)

public var logger = Logger(label: "forgery")
