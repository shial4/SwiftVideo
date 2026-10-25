// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import SwiftVideoEditor

@main
struct EditorLauncher: App {
    var body: some Scene {
        WindowGroup { SwiftVideoEditorRootView() }
            #if os(macOS)
            .defaultSize(width: 1280, height: 820)
            #endif
    }
}
