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

    @OptionGroup(title: "Repo types to work on")
    var repoTypes: RepoTypeOptions

    // MARK: Orgs
    
    @Option(help: "Instead of fetching the list of the authenticated user's repos, fetch the specified organization's.")
    var organization: String?

    @Flag(help: "When cloning repos for a user, don't clone repos created by a user by owned by an organization.")
    var dedupeOrgReposCreatedByUser: Bool = false

    @Flag(help: "Verbose logging.")
    var verbose: Bool = false
}

extension Clone {
    mutating func run() throws {
        logger.info("Starting clone...")

        if verbose {
            logger.logLevel = .debug
        }

        let github = GitHub(accessToken: accessToken)
        
        if let organization = organization {
            try github.cloneForOrganization(basePath: basePath, repoTypes: repoTypes.resolved, organization: organization)
        } else {
            try github.cloneForUser(basePath: basePath, repoTypes: repoTypes.resolved, organization: organization, dedupeOrgReposCreatedByUser: dedupeOrgReposCreatedByUser)
        }
    }
}
