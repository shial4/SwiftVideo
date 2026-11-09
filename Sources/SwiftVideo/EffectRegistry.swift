// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// An exact, app-owned effect version. Changing an effect's behavior requires a new version.
public struct EffectIdentifier: Hashable, Codable, Sendable {
    public let name: String
    public let version: Int

    public init(_ name: String, version: Int = 1) { self.name = name; self.version = version }

    func validate() throws {
        guard !name.isEmpty, name.utf8.count <= 200, version > 0,
              name.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || [45, 46, 95].contains($0) }) else {
            throw VideoError.invalidProject("Effect identifiers require an ASCII name (letters, digits, '.', '-' or '_') and a positive version.")
        }
    }
}

public enum EffectValue: Hashable, Codable, Sendable {
    case number(Double), vector([Double]), boolean(Bool), text(String)

    func validate() throws {
        switch self {
        case .number(let value):
            guard value.isFinite else { throw VideoError.invalidProject("Effect numbers must be finite.") }
        case .vector(let values):
            guard !values.isEmpty, values.count <= 16, values.allSatisfy(\.isFinite) else {
                throw VideoError.invalidProject("Effect vectors require 1...16 finite components.")
            }
        case .boolean, .text: break
        }
    }
}

/// Project files contain references and data, never executable effect implementations.
public struct EffectReference: Hashable, Codable, Sendable {
    public let id: EffectIdentifier
    public let parameters: [String: EffectValue]

    public init(_ id: EffectIdentifier, parameters: [String: EffectValue] = [:]) {
        self.id = id; self.parameters = parameters
    }

    func validate() throws {
        try id.validate()
        for (name, value) in parameters {
            guard !name.isEmpty else { throw VideoError.invalidProject("Effect parameter names cannot be empty.") }
            try value.validate()
        }
    }
}

public struct EffectParameter: Hashable, Codable, Sendable {
    public enum Kind: Hashable, Codable, Sendable { case number, vector(Int), boolean, text }
    public let kind: Kind
    public let defaultValue: EffectValue?
    /// Inclusive bounds for numbers and every component of a vector.
    public let range: ClosedRange<Double>?

    public init(_ kind: Kind, defaultValue: EffectValue? = nil, range: ClosedRange<Double>? = nil) {
        self.kind = kind; self.defaultValue = defaultValue; self.range = range
    }

    func validate(_ value: EffectValue, name: String) throws {
        try value.validate()
        let numbers: [Double]
        switch (kind, value) {
        case (.number, .number(let value)): numbers = [value]
        case (.vector(let count), .vector(let values)) where count == values.count: numbers = values
        case (.boolean, .boolean), (.text, .text): numbers = []
        default: throw VideoError.invalidProject("Effect parameter '\(name)' has the wrong type or vector size.")
        }
        if let range, !numbers.allSatisfy(range.contains) {
            throw VideoError.invalidProject("Effect parameter '\(name)' is outside its permitted range.")
        }
    }

    func validateSchema(name: String) throws {
        guard !name.isEmpty else { throw VideoError.invalidProject("Effect parameter names cannot be empty.") }
        if case .vector(let count) = kind, !(1...16).contains(count) {
            throw VideoError.invalidProject("Effect vector schemas require 1...16 components.")
        }
        if let range {
            guard range.lowerBound.isFinite, range.upperBound.isFinite else {
                throw VideoError.invalidProject("Effect parameter bounds must be finite.")
            }
            switch kind {
            case .number, .vector: break
            case .boolean, .text: throw VideoError.invalidProject("Only numeric effect parameters support ranges.")
            }
        }
        if let defaultValue { try validate(defaultValue, name: name) }
    }
}

public enum EffectPlatform: String, Codable, Sendable, CaseIterable { case apple, android }

/// Factories are trusted application code. Each export creates independent processor instances.
public struct VisualEffectDefinition: Sendable {
    public let id: EffectIdentifier
    public let parameters: [String: EffectParameter]
    var androidFactory: (@Sendable ([String: EffectValue]) throws -> AndroidVisualEffect)?
    #if canImport(CoreImage)
    var appleFactory: (@Sendable ([String: EffectValue]) throws -> any AppleVisualEffectProcessor)?
    #endif

    public init(_ id: EffectIdentifier, parameters: [String: EffectParameter] = [:]) {
        self.id = id; self.parameters = parameters
    }

    public func android(_ factory: @escaping @Sendable ([String: EffectValue]) throws -> AndroidVisualEffect) -> Self {
        var copy = self; copy.androidFactory = factory; return copy
    }

    public var supportedPlatforms: Set<EffectPlatform> {
        var result: Set<EffectPlatform> = []
        if androidFactory != nil { result.insert(.android) }
        #if canImport(CoreImage)
        if appleFactory != nil { result.insert(.apple) }
        #endif
        return result
    }

    func resolve(_ reference: EffectReference) throws -> [String: EffectValue] {
        try reference.validate()
        guard reference.parameters.keys.allSatisfy({ parameters[$0] != nil }) else {
            throw VideoError.invalidProject("Unknown parameter for effect '\(id.name)' version \(id.version).")
        }
        var resolved: [String: EffectValue] = [:]
        for (name, schema) in parameters {
            guard let value = reference.parameters[name] ?? schema.defaultValue else {
                throw VideoError.invalidProject("Missing required effect parameter '\(name)'.")
            }
            try schema.validate(value, name: name)
            resolved[name] = value
        }
        return resolved
    }
}

/// Immutable and safe to share between exporters. Registration never changes global state.
public struct EffectRegistry: Sendable {
    private let visual: [EffectIdentifier: VisualEffectDefinition]
    public static let empty = EffectRegistry(registeredVisual: [:])

    private init(registeredVisual: [EffectIdentifier: VisualEffectDefinition]) { visual = registeredVisual }

    public init(visual definitions: [VisualEffectDefinition]) throws {
        var registered: [EffectIdentifier: VisualEffectDefinition] = [:]
        for definition in definitions {
            try definition.id.validate()
            for (name, schema) in definition.parameters { try schema.validateSchema(name: name) }
            guard registered.updateValue(definition, forKey: definition.id) == nil else {
                throw VideoError.invalidProject("Duplicate effect '\(definition.id.name)' version \(definition.id.version).")
            }
        }
        visual = registered
    }

    public func supportedPlatforms(for id: EffectIdentifier) -> Set<EffectPlatform> {
        visual[id]?.supportedPlatforms ?? []
    }

    public func validate(_ project: VideoProject, for platform: EffectPlatform) throws {
        for clip in try project.renderClips() {
            for case .custom(let reference) in clip.filters { _ = try resolve(reference, for: platform) }
        }
    }

    func resolve(_ reference: EffectReference, for platform: EffectPlatform) throws -> (VisualEffectDefinition, [String: EffectValue]) {
        try reference.validate()
        guard let definition = visual[reference.id] else {
            throw VideoError.unsupportedFeature("Effect '\(reference.id.name)' version \(reference.id.version) is not registered.")
        }
        let parameters = try definition.resolve(reference)
        guard definition.supportedPlatforms.contains(platform) else {
            throw VideoError.unsupportedFeature("Effect '\(reference.id.name)' version \(reference.id.version) has no \(platform.rawValue) implementation.")
        }
        return (definition, parameters)
    }
}
