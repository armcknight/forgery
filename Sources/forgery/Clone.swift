import ArgumentParser
import Foundation
import GitKit
import OctoKit
import forgery_lib
import GitLabSwift

struct Clone: AsyncParsableCommand {
    @Option(help: "The access token for the GitHub user whose repos should be synced.")
    var githubToken: String? = nil
    
    @Option(help: "The access token for the GitHub user whose repos should be synced.")
    var gitlabToken: String? = nil
    
    @Argument(help: "Local location to work with repos.")
    var basePath: String
    
    @OptionGroup var repoTypes: RepoTypeOptions
    
    // MARK: Orgs
    
    @Option(help: "Instead of fetching the list of the authenticated user's repos, fetch the specified organization's.")
    var organization: String?
}

extension Clone {
    mutating func run() async throws {
        logger.info("Starting clone...")
        
        if let token = githubToken {
            let github = GitHub(accessToken: token)
            
            if let organization = organization {
                try github.cloneForOrganization(basePath: basePath, repoTypes: repoTypes.resolved, organization: organization)
            } else {
                try github.cloneForUser(basePath: basePath, repoTypes: repoTypes.resolved, organization: organization)
            }
        }
        
        if let token = gitlabToken {
            let gitlab = GitLab(accessToken: token)
            try await gitlab.cloneForUser(basePath: basePath, repoTypes: repoTypes.resolved, organization: organization)
        }
    }
}
