// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import SwiftVideo

@Suite struct EffectRegistryTests {
    private let id = EffectIdentifier("test.channel-rotation")

    private func project(_ reference: EffectReference) throws -> VideoProject {
        VideoProject(tracks: [MediaTrack(clips: [MediaClip.text("Title", duration: try VideoTime(value: 1, timescale: 1))])
            .filter(.custom(reference))])
    }

    @Test func referencesRoundTripAndResolveDefaultsWithoutChangingTheProject() throws {
        let definition = VisualEffectDefinition(id, parameters: [
            "amount": EffectParameter(.number, defaultValue: .number(0.5), range: 0...1),
            "color": EffectParameter(.vector(3), range: 0...1),
            "enabled": EffectParameter(.boolean, defaultValue: .boolean(true)),
            "label": EffectParameter(.text, defaultValue: .text("sample"))
        ]).android { _ in AndroidVisualEffect(fragmentShader: "sample") }
        let registry = try EffectRegistry(visual: [definition])
        let reference = EffectReference(id, parameters: ["color": .vector([0, 0.5, 1])])
        let original = try project(reference)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(VideoProject.self, from: data)
        #expect(decoded == original)
        try decoded.validate()
        try registry.validate(decoded, for: .android)
        let (_, values) = try registry.resolve(reference, for: .android)
        #expect(values == ["amount": .number(0.5), "color": .vector([0, 0.5, 1]), "enabled": .boolean(true), "label": .text("sample")])
        #expect(reference.parameters.count == 1)
        #expect(!String(decoding: data, as: UTF8.self).contains("fragmentShader"))
        #expect(registry.supportedPlatforms(for: id) == [.android])
        #expect(registry.supportedPlatforms(for: EffectIdentifier(id.name, version: 2)).isEmpty)
    }

    @Test func registryRejectsMissingVersionsPlatformsAndDuplicateRegistrations() throws {
        let definition = VisualEffectDefinition(id).android { _ in AndroidVisualEffect(fragmentShader: "sample") }
        let registry = try EffectRegistry(visual: [definition])
        #expect(throws: VideoError.self) { try EffectRegistry(visual: [definition, definition]) }
        #expect(throws: VideoError.self) { try registry.validate(project(EffectReference(id)), for: .apple) }
        #expect(throws: VideoError.self) { try registry.validate(project(EffectReference(EffectIdentifier(id.name, version: 2))), for: .android) }
        #expect(throws: VideoError.self) { try EffectRegistry.empty.validate(project(EffectReference(id)), for: .android) }
        let twoVersions = try EffectRegistry(visual: [definition, VisualEffectDefinition(EffectIdentifier(id.name, version: 2))])
        #expect(twoVersions.supportedPlatforms(for: id) == [.android])
    }

    @Test func parameterValidationRejectsMissingUnknownWrongTypeAndOutOfRangeValues() throws {
        let definition = VisualEffectDefinition(id, parameters: ["amount": EffectParameter(.number, range: 0...1)])
            .android { _ in AndroidVisualEffect(fragmentShader: "sample") }
        let registry = try EffectRegistry(visual: [definition])
        for values: [String: EffectValue] in [[:], ["other": .number(1)], ["amount": .boolean(true)],
                                            ["amount": .number(-0.1)], ["amount": .number(1.1)], ["amount": .number(.nan)]] {
            #expect(throws: VideoError.self) { try registry.validate(project(EffectReference(id, parameters: values)), for: .android) }
        }
        for value in [0.0, 1.0] {
            try registry.validate(project(EffectReference(id, parameters: ["amount": .number(value)])), for: .android)
        }
        let vector = VisualEffectDefinition(id, parameters: ["color": EffectParameter(.vector(3), range: 0...1)])
        #expect(throws: VideoError.self) { try vector.resolve(EffectReference(id, parameters: ["color": .vector([0, 1])])) }
        #expect(throws: VideoError.self) { try vector.resolve(EffectReference(id, parameters: ["color": .vector([0, 1, 2])])) }
    }

    @Test func invalidSchemasAndSerializedReferencesFailBeforeRendering() throws {
        for invalidID in [EffectIdentifier(""), EffectIdentifier("spaces are invalid"), EffectIdentifier("effect", version: 0),
                          EffectIdentifier(String(repeating: "a", count: 201))] {
            #expect(throws: VideoError.self) { try EffectRegistry(visual: [VisualEffectDefinition(invalidID)]) }
            #expect(throws: VideoError.self) { try project(EffectReference(invalidID)).validate() }
        }
        for schema in [EffectParameter(.number, defaultValue: .number(2), range: 0...1),
                       EffectParameter(.number, defaultValue: .text("bad")), EffectParameter(.vector(0)),
                       EffectParameter(.vector(17)), EffectParameter(.text, range: 0...1),
                       EffectParameter(.number, range: 0...Double.infinity)] {
            #expect(throws: VideoError.self) { try EffectRegistry(visual: [VisualEffectDefinition(id, parameters: ["value": schema])]) }
        }
        #expect(throws: VideoError.self) { try EffectRegistry(visual: [VisualEffectDefinition(id, parameters: ["": EffectParameter(.boolean)])]) }
        for parameters: [String: EffectValue] in [["": .boolean(true)], ["v": .vector([])], ["v": .vector([.infinity])],
                                                 ["v": .vector(Array(repeating: 1, count: 17))]] {
            #expect(throws: VideoError.self) { try project(EffectReference(id, parameters: parameters)).validate() }
        }
    }

    @Test func androidPlanResolvesCustomClipAndTrackFiltersInAuthoredOrder() throws {
        let definition = VisualEffectDefinition(id, parameters: ["amount": EffectParameter(.number, defaultValue: .number(0.5))])
            .android { values in
                guard case .number(let amount) = values["amount"] else { throw VideoError.invalidProject("Missing amount") }
                return AndroidVisualEffect(fragmentShader: "sample", uniforms: ["uAmount": [Float(amount)]])
            }
        let registry = try EffectRegistry(visual: [definition])
        let clip = MediaClip.text("Title", duration: try VideoTime(value: 1, timescale: 1))
            .filter(.brightness(0.1)).filter(.custom(EffectReference(id, parameters: ["amount": .number(0.25)])))
        let project = VideoProject(tracks: [MediaTrack(clips: [clip]).filter(.custom(EffectReference(id))).filter(.sepia(0.2))])
        let plan = try AndroidRenderPlan(project: project, settings: ExportSettings(), effects: registry)
        #expect(plan.clips[0].filters.map(\.kind) == ["brightness", "custom", "custom", "sepia"])
        #expect(plan.clips[0].filters[1].shader?.uniforms == ["uAmount": [0.25]])
        #expect(plan.clips[0].filters[2].shader?.uniforms == ["uAmount": [0.5]])
        #expect(throws: VideoError.self) { try AndroidRenderPlan(project: project, settings: ExportSettings()) }
        let capabilities = RendererCapabilities(name: "Built-ins", features: [.text, .filters], codecs: [.h264], containers: [.mp4])
        #expect(throws: VideoError.self) { try capabilities.validate(project, settings: ExportSettings()) }
    }

    @Test func shaderValidationRejectsMalformedUniformsAndEmptySource() throws {
        for shader in [AndroidVisualEffect(fragmentShader: " \n"),
                       AndroidVisualEffect(fragmentShader: "shader", uniforms: ["": [1]]),
                       AndroidVisualEffect(fragmentShader: "shader", uniforms: ["uTexSampler": [0]]),
                       AndroidVisualEffect(fragmentShader: "shader", uniforms: ["uTexelSize": [1, 1]]),
                       AndroidVisualEffect(fragmentShader: "shader", uniforms: ["value": []]),
                       AndroidVisualEffect(fragmentShader: "shader", uniforms: ["value": [.nan]]),
                       AndroidVisualEffect(fragmentShader: "shader", uniforms: ["value": [1, 2, 3, 4, 5]])] {
            #expect(throws: VideoError.self) { try shader.validate() }
        }
    }
}
