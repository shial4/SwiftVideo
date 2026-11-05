// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

struct FileCoverage: Codable {
    let file: String
    let covered: Int
    let executable: Int
}
struct CoverageReport: Codable {
    let suite: String
    let files: [FileCoverage]
    let covered: Int
    let executable: Int
    let linePercent: Double
}
struct CoverageInput: Decodable {
    struct XcodeTarget: Decodable {
        struct File: Decodable {
            let path: String
            let coveredLines: Int
            let executableLines: Int
        }
        let files: [File]
    }
    struct LLVMReport: Decodable {
        struct File: Decodable {
            struct Summary: Decodable {
                struct Lines: Decodable { let covered: Int; let count: Int }
                let lines: Lines
            }
            let filename: String
            let summary: Summary
        }
        let files: [File]
    }
    let targets: [XcodeTarget]?
    let data: [LLVMReport]?
}
final class JacocoReader: NSObject, XMLParserDelegate {
    var source: String?
    var files: [FileCoverage] = []
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if name == "sourcefile" { source = attributes["name"] }
        if name == "counter", let source, attributes["type"] == "LINE",
           let covered = Int(attributes["covered"] ?? ""), let missed = Int(attributes["missed"] ?? "") {
            files.append(FileCoverage(file: "Sources/SwiftVideoMedia3/" + source, covered: covered, executable: covered + missed))
        }
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "sourcefile" { source = nil }
    }
}
guard CommandLine.arguments.count == 5, let minimum = Double(CommandLine.arguments[4]) else {
    print("Usage: swift Tools/Coverage.swift ios|android-core|android-media3 input output.json minimum-percent")
    exit(2)
}
let suite = CommandLine.arguments[1]
let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
var files: [FileCoverage] = []
func firstParty(_ path: String) -> String? {
    guard let range = path.range(of: "/Sources/SwiftVideo/") else { return nil }
    let relative = String(path[path.index(after: range.lowerBound)...])
    if suite == "android-core" && relative.hasSuffix("/AndroidVideoRenderer.swift") { return nil }
    return relative
}
if suite == "android-media3" {
    let reader = JacocoReader()
    let parser = XMLParser(data: data)
    parser.delegate = reader
    guard parser.parse() else { throw parser.parserError! }
    files = reader.files
} else {
    let input = try JSONDecoder().decode(CoverageInput.self, from: data)
    if suite == "ios", let targets = input.targets {
        for target in targets {
            for file in target.files {
                guard let name = firstParty(file.path) else { continue }
                files.append(FileCoverage(file: name, covered: file.coveredLines, executable: file.executableLines))
            }
        }
    } else if suite == "android-core" || suite == "ios" {
        for report in input.data ?? [] {
            for file in report.files {
                guard let name = firstParty(file.filename) else { continue }
                files.append(FileCoverage(file: name, covered: file.summary.lines.covered,
                                          executable: file.summary.lines.count))
            }
        }
    } else { fatalError("Unknown suite: \(suite)") }
}
guard !files.isEmpty else { fatalError("Coverage report contains no first-party files") }
// Xcode can report the same package sources through both object and product targets.
let grouped = Dictionary(grouping: files, by: \.file)
files = grouped.values.map { entries in
    let first = entries[0]
    precondition(entries.allSatisfy { $0.covered == first.covered && $0.executable == first.executable },
                 "Conflicting coverage for duplicate product source: \(first.file)")
    return first
}
let total = files.reduce(0) { $0 + $1.executable }
let covered = files.reduce(0) { $0 + $1.covered }
let percent = Double(covered) / Double(total) * 100
let result = CoverageReport(suite: suite, files: files.sorted { $0.file < $1.file }, covered: covered, executable: total, linePercent: percent)
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
let output = URL(fileURLWithPath: CommandLine.arguments[3])
try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
try encoder.encode(result).write(to: output)
print(String(format: "%@: %d/%d executable lines, %.2f%% (minimum %.1f%%)", suite, covered, total, percent, minimum))
if percent < minimum { exit(1) }
