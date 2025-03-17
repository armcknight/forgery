#!/usr/bin/env swift

import Foundation
import ArgumentParser

struct BaseOptions: ParsableArguments {
    @Argument(help: "Location of the repos for which to report statuses.")
    var basePath: String

    @Flag(help: "Verbose logging.")
    var verbose: Bool = false
}

struct Forgery: ParsableCommand {
    static let configuration = CommandConfiguration(
        subcommands: [Status.self, Sync.self, Clone.self],
        defaultSubcommand: Status.self
    )
}

Forgery.main()
