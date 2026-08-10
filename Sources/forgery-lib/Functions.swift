import Foundation
import Subprocess
import System

/// Maximum bytes collected from a shell invocation's combined output (16MB).
private let maxShellOutput = 16 * 1024 * 1024

func shell(_ command: String, workingDirectory: String? = nil) async -> String {
    do {
        let result = try await Subprocess.run(
            .path("/bin/bash"),
            arguments: ["-c", command],
            workingDirectory: workingDirectory.map { FilePath($0) },
            output: .string(limit: maxShellOutput),
            error: .string(limit: maxShellOutput)
        )
        // The previous Process-based implementation merged stdout and stderr onto
        // one pipe and returned whatever came back, regardless of exit status.
        let combined = (result.standardOutput ?? "") + (result.standardError ?? "")
        return combined.trimmingCharacters(in: .whitespacesAndNewlines)
    } catch {
        return ""
    }
}
