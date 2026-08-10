import ArgumentParser
import Foundation
import GitKit
import OctoKit
import forgery_lib

struct Clone: AsyncParsableCommand {
    @Argument(help: "The GitHub access token of the GitHub user whose repos should be synced.")
    var accessToken: String

    @OptionGroup(title: "Basic options")
    var baseOptions: BaseOptions

    @OptionGroup(title: "Repo types to work on")
    var repoTypes: RepoTypeOptions

    // MARK: Orgs
    
    @Option(help: "Instead of fetching the list of the authenticated user's repos, fetch the specified organization's.")
    var organization: String?

    @Flag(help: "When cloning repos for a user, don't clone repos created by a user by owned by an organization.")
    var dedupeOrgReposCreatedByUser: Bool = false
}

extension Clone {
    mutating func run() async throws {
        logger.info("Starting clone...")

        if baseOptions.verbose {
            logger.logLevel = .debug
        }

        let github = GitHub(accessToken: accessToken)
        
        if let organization = organization {
            try await github.cloneForOrganization(basePath: baseOptions.basePath, repoTypes: repoTypes.resolved, organization: organization)
        } else {
            try await github.cloneForUser(basePath: baseOptions.basePath, repoTypes: repoTypes.resolved, organization: organization, dedupeOrgReposCreatedByUser: dedupeOrgReposCreatedByUser)
        }
    }
}
