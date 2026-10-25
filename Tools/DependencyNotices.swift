// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

import Foundation

struct Lockfile: Decodable {
    struct Pin: Decodable {
        struct State: Decodable { let revision: String; let version: String? }
        let identity: String
        let location: String
        let state: State
    }
    let pins: [Pin]
}
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let output = root.appendingPathComponent("Documentation/ThirdParty")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
var pins: [String: Lockfile.Pin] = [:]
for path in ["Package.resolved", "Example/Package.resolved"] {
    for pin in try JSONDecoder().decode(Lockfile.self, from: Data(contentsOf: root.appendingPathComponent(path))).pins {
        if let existing = pins[pin.identity], existing.state.revision != pin.state.revision {
            throw NSError(domain: "Notices", code: 1, userInfo: [NSLocalizedDescriptionKey: "Conflicting revisions for \(pin.identity)"])
        }
        pins[pin.identity] = pin
    }
}
var rows: [String] = []
for pin in pins.values.sorted(by: { $0.identity < $1.identity }) {
    let checkouts = [".build-media3/checkouts", "Example/.build/checkouts"]
    var license: String?
    for checkout in checkouts {
        for name in ["LICENSE", "LICENSE.txt", "LICENSE.md", "COPYING"] {
            if let text = try? String(contentsOf: root.appendingPathComponent("\(checkout)/\(pin.identity)/\(name)"), encoding: .utf8) {
                license = text; break
            }
        }
        if license != nil { break }
    }
    guard let license else { fatalError("Missing license for \(pin.identity)") }
    let filename = "\(pin.identity)-LICENSE.txt"
    try license.write(to: output.appendingPathComponent(filename), atomically: true, encoding: .utf8)
    let repository = pin.location.hasSuffix(".git") ? String(pin.location.dropLast(4)) : pin.location
    rows.append("| \(pin.identity) | \(pin.state.version ?? "revision") | [License](\(filename)) | [\(pin.state.revision.prefix(12))](\(repository)/tree/\(pin.state.revision)) |")
}
let document = """
<!-- Copyright 2026 Software Deck Pty Ltd; SPDX-License-Identifier: Apache-2.0 -->
# Third-party dependencies for 0.0.1

SwiftVideo's Apache 2.0 license applies to first-party work. The dependencies below retain their own licenses and copyrights. License texts are copied verbatim. Source links identify the exact resolved revisions, including corresponding source for MPL-covered components. No dependency sources are modified.

| Swift package | Resolved version | License | Corresponding source |
| --- | --- | --- | --- |
\(rows.joined(separator: "\n"))

Android rendering also uses AndroidX Media3 Transformer and Effect 1.11.1 under Apache 2.0. Their POMs identify transitive dependencies; downstream applications must retain notices for the versions they resolve and distribute. [Media3 source](https://github.com/androidx/media/tree/1.11.1), [license](https://github.com/androidx/media/blob/1.11.1/LICENSE).

The example platform shells were produced by Skip 1.9.19. The Android shell is unmodified generated output. Its Gradle wrapper is Gradle project code under Apache 2.0: [Gradle license and notices](https://github.com/gradle/gradle/blob/v9.0.0/LICENSE).

The source release does not bundle Apple frameworks, Swift toolchains, Android SDK/NDK binaries, or dependency build products. A downstream binary distributor is responsible for the notices and source obligations of its complete resolved application. Regenerate this inventory with `swift Tools/DependencyNotices.swift` after resolving both packages.

"""
try document.write(to: output.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
print("Recorded \(pins.count) exact Swift package revisions and license texts.")
