// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum VideoError: Error, Sendable, Equatable, LocalizedError {
    case invalidTime(String)
    case timeOverflow
    case invalidProject(String)
    case missingTrack(UUID)
    case missingClip(UUID)
    case unsupportedFeature(String)
    case invalidMedia(String)
    case invalidExport(String)
    case destinationExists
    case exportInProgress
    case cancelled
    case renderingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidTime(let message), .invalidProject(let message), .unsupportedFeature(let message),
             .invalidMedia(let message), .invalidExport(let message), .renderingFailed(let message): message
        case .timeOverflow: "The requested time cannot be represented without overflow or rounding."
        case .missingTrack(let id): "Track \(id) does not exist."
        case .missingClip(let id): "Clip \(id) does not exist."
        case .destinationExists: "The export destination already exists."
        case .exportInProgress: "This exporter is already exporting a project."
        case .cancelled: "The export was cancelled."
        }
    }
}
