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
    
    @OptionGroup var repoTypes: RepoTypeOptions
    
    // MARK: Orgs
    
    @Option(help: "Instead of fetching the list of the authenticated user's repos, fetch the specified organization's.")
    var organization: String?
}

extension Clone {
    mutating func run() throws {
        logger.info("Starting clone...")
        
        let github = GitHub(accessToken: accessToken)
        
        if let organization = organization {
            try github.cloneForOrganization(basePath: basePath, repoTypes: repoTypes.resolved, organization: organization)
        } else {
            try github.cloneForUser(basePath: basePath, repoTypes: repoTypes.resolved, organization: organization)
        }
    }
}
