#!/usr/bin/env swift

import Foundation
import ArgumentParser

struct BaseOptions: ParsableArguments {
    @Argument(help: "Location of the repos for which to report statuses.")
    var basePath: String

    @Flag(help: "Verbose logging.")
    var verbose: Bool = false
}

struct Forgery: AsyncParsableCommand {
    // Single source of truth for the release version. Bumped by `vrsn -k
    // version` (see Makefile) and read by the release workflow.
    static let version = "1.0.0"

    static let configuration = CommandConfiguration(
        subcommands: [Status.self, Sync.self, Clone.self],
        defaultSubcommand: Status.self,
        version: Forgery.version
    )
}

await Forgery.main()
