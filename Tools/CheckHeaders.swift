// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let fixing = CommandLine.arguments.contains("--fix")
let roots = ["Sources", "Tests", "Examples", "Tools", ".github", "Example/Sources", "Example/Tests", "Example/Launcher", "Example/Darwin/Sources"]
var files = [root.appendingPathComponent("Package.swift"), root.appendingPathComponent("Example/Package.swift")]
for directory in roots {
    if let enumerator = FileManager.default.enumerator(at: root.appendingPathComponent(directory), includingPropertiesForKeys: nil) {
        for case let file as URL in enumerator where ["swift", "yml", "yaml"].contains(file.pathExtension) { files.append(file) }
    }
}
var missing: [String] = []
for file in files {
    var source = try String(contentsOf: file, encoding: .utf8)
    guard !source.contains("SPDX-License-Identifier: Apache-2.0") else { continue }
    let prefix = file.pathExtension == "swift" ? "//" : "#"
    let header = "\(prefix) Copyright 2026 Software Deck Pty Ltd\n\(prefix) SPDX-License-Identifier: Apache-2.0\n"
    if fixing {
        if source.hasPrefix("// swift-tools-version:"), let newline = source.firstIndex(of: "\n") {
            source.insert(contentsOf: header, at: source.index(after: newline))
        } else { source = header + "\n" + source }
        try source.write(to: file, atomically: true, encoding: .utf8)
    } else { missing.append(file.path.replacingOccurrences(of: root.path + "/", with: "")) }
}
if !missing.isEmpty {
    print("Missing Apache headers:\n" + missing.joined(separator: "\n"))
    exit(1)
}
print("Checked \(files.count) first-party Swift and workflow/configuration files.")
