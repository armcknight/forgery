import Foundation
import ShellKit

func shell(_ command: String, workingDirectory: String? = nil) -> String {
    let task = Process()
    task.launchPath = "/bin/bash"
    task.arguments = ["-c", command]

    if let workingDirectory = workingDirectory {
        task.currentDirectoryPath = workingDirectory
    }

    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe

    task.launch()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""

    return output.trimmingCharacters(in: .whitespacesAndNewlines)
}
