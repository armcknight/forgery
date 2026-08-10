import Foundation
import ArgumentParser

struct BaseOptions: ParsableArguments {
    @Argument(help: "Location of the repos for which to report statuses.")
    var basePath: String

    @Flag(help: "Verbose logging.")
    var verbose: Bool = false
}

// An AsyncParsableCommand root must be the `@main` entry point (or it needs an
// availability annotation that a top-level `await Forgery.main()` in main.swift
// still can't satisfy — that path hits the synchronous entry and fatal-errors
// with "Asynchronous root command needs availability annotation"). `@main` is
// not allowed in a file named main.swift, so this type lives in Forgery.swift.
@available(macOS 13, *)
@main
struct Forgery: AsyncParsableCommand {
    // Single source of truth for the release version. Bumped by `vrsn -k
    // version` (see Makefile) and read by the release workflow.
    static let version = "1.0.0"

    static let configuration = CommandConfiguration(
        version: Forgery.version,
        subcommands: [Status.self, Sync.self, Clone.self],
        defaultSubcommand: Status.self
    )
}
