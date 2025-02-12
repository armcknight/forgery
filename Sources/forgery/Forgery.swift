import Foundation
import ArgumentParser

@main struct Forgery: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        subcommands: [Status.self, Sync.self, Clone.self],
        defaultSubcommand: Status.self
    )
}
