import ArgumentParser
import Foundation
import OctoKit

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
