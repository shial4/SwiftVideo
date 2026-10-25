// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

import Foundation
#if os(Android)
import SkipFuse
#else
import OSLog
#endif
import SwiftUI

/// A logger for the SwiftVideoEditor module.
let logger: Logger = Logger(subsystem: "com.softwaredeck.swiftvideo.editor", category: "SwiftVideoEditor")

/// The shared top-level view for the app, loaded from the platform-specific App delegates below.
///
/// The default implementation merely loads the `ContentView` for the app and logs a message.
/* SKIP @bridge */public struct SwiftVideoEditorRootView : View {
    /* SKIP @bridge */public init() {
    }

    public var body: some View {
        ContentView()
            #if os(macOS)
            .frame(minWidth: 1000, minHeight: 720)
            #endif
            .task {
                logger.info("Skip app logs are viewable in the Xcode console for iOS; Android logs can be viewed in Studio or using adb logcat")
            }
    }
}

/// Global application delegate functions.
///
/// These functions can update a shared observable object to communicate app state changes to interested views.
/* SKIP @bridge */public final class SwiftVideoEditorAppDelegate : Sendable {
    /* SKIP @bridge */public static let shared = SwiftVideoEditorAppDelegate()

    private init() {
    }

    /* SKIP @bridge */public func onInit() {
        logger.debug("onInit")
    }

    /* SKIP @bridge */public func onLaunch() {
        logger.debug("onLaunch")
    }

    /* SKIP @bridge */public func onResume() {
        logger.debug("onResume")
    }

    /* SKIP @bridge */public func onPause() {
        logger.debug("onPause")
    }

    /* SKIP @bridge */public func onStop() {
        logger.debug("onStop")
    }

    /* SKIP @bridge */public func onDestroy() {
        logger.debug("onDestroy")
    }

    /* SKIP @bridge */public func onLowMemory() {
        logger.debug("onLowMemory")
    }
}
