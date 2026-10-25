<!-- Copyright 2026 Software Deck Pty Ltd; SPDX-License-Identifier: Apache-2.0 -->
# Integrate SwiftVideo

[Documentation index](README.md) | [Quick start and SwiftPM manifest](../README.md#install) | [API reference](APIReference.md)

SwiftVideo 0.0.1 exposes a native Swift API. Apple apps and Skip Fuse modules use it directly. Kotlin and Skip Lite callers need an application-owned native Swift wrapper with a generated bridge.

## Swift Package Manager

Add the dependency to your package's `dependencies` array:

```swift
.package(url: "https://github.com/shial4/SwiftVideo.git", from: "0.0.1")
```

Add the product to the consuming target's `dependencies` array:

```swift
.product(name: "SwiftVideo", package: "SwiftVideo")
```

Use `import SwiftVideo` in source files. The [complete manifest](../README.md#install) targets Swift 6.3+, iOS 17+, and macOS 14+. Android also requires the runtime and build integration described below.

## Native iOS and macOS

In an Xcode app, choose **File > Add Package Dependencies**, enter `https://github.com/shial4/SwiftVideo.git`, select a version starting at `0.0.1`, and add the **SwiftVideo** product to the app target. A package-based feature can use the manifest entries above instead.

SwiftUI, UIKit, and AppKit callers use the same API:

1. Obtain readable media URLs from your app's import layer. Keep source files and any required security-scoped access alive until export finishes.
2. Build a `VideoProject` with tracks and clips. See the [title export](../README.md#quick-start) or [composition recipes](Recipes.md).
3. Call `try await exporter.export(project, to: outputURL)` from an async context. The destination must not already exist.
4. Present the resulting URL with your app's player or share UI.

Retain the export task if the user can cancel it. Progress callbacks are `@Sendable`; update observable UI state through `MainActor`. The [SwiftUI export model](Recipes.md#cancellable-export-from-swiftui) includes progress, cancellation, and error handling. In UIKit, start a `Task` from an action and make UI changes on the main actor.

Use Xcode's Swift toolchain for Apple builds. SwiftPM resolves the package's declared dependencies, but Apple-only use does not require an Android SDK, JDK, emulator, or Android application context. The Apple renderer uses AVFoundation and Metal-backed Core Image.

## Skip for iOS and Android

Use a **native Skip Fuse module** for code that imports SwiftVideo. Add the SwiftPM dependency and product above to your existing shared `Package.swift`, preserving the Skip plugins and dependencies created for your app. Set the shared target's minimum Apple platforms to iOS 17/macOS 14 or newer and the Android app's minimum SDK to at least 28.

The consuming module's `Sources/<Target>/Skip/skip.yml` uses:

```yaml
skip:
  mode: 'native'
```

Both platforms can now compile the same `import SwiftVideo`, project builders, editing operations, and async export calls. SwiftVideo's Android backend invokes its Swift-authored Media3 service through generated JNI bridges.

Keep the generated Skip app launcher and build integration. It initializes the Android context and packages the generated JVM modules, Swift shared libraries, and resources. A standalone Swift Android executable does not supply that application environment.

Use your existing matching Swift toolchain/Android SDK and Skip installation. Follow [Skip's setup documentation](https://skip.dev/docs/gettingstarted/) when setting up a new machine. Our [example manifest](../Example/Package.swift), [module configuration](../Example/Sources/SwiftVideoEditor/Skip/skip.yml), and [example build instructions](../Example/README.md) show the complete working app arrangement. Add shared dependencies in `Package.swift`, so both platform builds see them.

### Calling from Skip Lite

The public SwiftVideo module has bridging disabled; its result-builder API is intended for compiled Swift. Keep composition code in a native Fuse wrapper and expose only the operations the Lite app needs. Enable bridging on that wrapper and use Skip's default Swift-compatible bridge types for a transpiled caller. The [wrapper pattern below](#native-android-and-kotlin) also applies, with `bridging: true` in place of the Kotlin-specific options. See [Skip's module and bridging modes](https://skip.dev/docs/modes/).

## Native Android and Kotlin

This is an adapter integration, not a published SwiftVideo Maven dependency. Version 0.0.1 does not ship a Kotlin facade or prebuilt AARs. You build and own the small public wrapper; SwiftVideo owns the composition and export implementation. The walkthrough below illustrates that boundary and must be built and tested with your Android app.

### 1. Create a native wrapper

With Skip and its Android build prerequisites already available, create a framework:

```sh
skip init --native-model --kotlincompat --swift-package-version 6.3 --no-build video-export-kit VideoExportKit
cd video-export-kit
```

Add the SwiftVideo dependency and product from [Swift Package Manager](#swift-package-manager) to the generated manifest. Keep its dynamic library product, Skip dependencies, and `skipstone` plugin. The generated `Sources/VideoExportKit/Skip/skip.yml` enables native Swift and Kotlin-compatible wrappers:

```yaml
skip:
  mode: 'native'
  bridging:
    enabled: true
    options: 'kotlincompat'
```

This configuration is generated by Skip 1.9.19. Use the template supplied by your installed Skip version when adopting newer tooling. [Kotlin compatibility](https://skip.dev/docs/modes/#kotlin-compatibility-option) maps supported Swift types to Kotlin/Java types; [bridging support](https://skip.dev/docs/bridging/) covers async functions and actors.

### 2. Expose an export operation

Add this Swift source to the wrapper target. Keep SwiftVideo types inside the implementation so the generated Kotlin API only needs strings and integers:

```swift
import Foundation
import SwiftVideo

public actor VideoExportService {
    private let exporter = VideoExporter()

    public init() {}

    public func export(inputPath: String, outputPath: String,
                       durationSeconds: Int, title: String) async throws -> String {
        let duration = try VideoTime(value: Int64(durationSeconds), timescale: 1)
        let project = VideoProject {
            MediaTrack("Footage") {
                MediaClip.video(URL(fileURLWithPath: inputPath), duration: duration)
            }
            MediaTrack("Title") {
                MediaClip.text(title, duration: duration, style: TextStyle(fontSize: 96))
                    .zIndex(1)
                    .transform(VisualTransform(y: 0.8, width: 0.9, height: 0.15))
            }
        }
        let destination = URL(fileURLWithPath: outputPath)
        try await exporter.export(
            project, to: destination,
            settings: ExportSettings(resolution: VideoSize(width: 1280, height: 720))
        )
        return destination.path
    }

    public func cancel() async {
        await exporter.cancel()
    }
}
```

Supply a positive duration within the source video and an unused `.mp4` output path. For Android picker `content://` URIs, copy the selected media into an app-owned file before using this file-path API. Keep the service instance for the export's lifetime; it supports one export at a time. Call its `cancel()` operation when your UI cancels the export.

### 3. Package for your Gradle app

From the wrapper project, export a development build:

```sh
skip export --debug -d dist
```

Skip exports Android library archives and a Gradle project. Use the generated project as the reference when adding the wrapper to your Android Studio app. Include the wrapper's dependency AARs, native `.so` libraries for the device ABIs you support, and Maven dependencies declared by the generated modules, including Media3. A local AAR by itself does not resolve the complete dependency graph.

Preserve the generated manifest metadata, including `SKIP_BRIDGE_MODULES`, and resource packaging so the runtime can load the native modules. Choose release builds and the required architectures for distribution; the [Skip deployment guide](https://skip.dev/docs/deployment/) explains export options. The consumer app must target Android API 28 or later.

### 4. Initialize and call from Kotlin

Initialize Skip once in your Android `Application.onCreate`, before calling the wrapper:

```kotlin
class VideoApplication : android.app.Application() {
    override fun onCreate() {
        super.onCreate()
        skip.foundation.ProcessInfo.launch(context = this)
    }
}
```

Register this application class in your app's manifest, or add the initialization to its existing `Application` subclass. A generated Skip app already performs initialization; it does not need a second call.

Import `VideoExportService` from the wrapper's generated Kotlin package. For a module named `VideoExportKit`, the default package is `video.export.kit`. Its async Swift method is exposed as a Kotlin suspend function:

```kotlin
import java.io.File
import video.export.kit.VideoExportService

class VideoExports {
    private val service = VideoExportService()

    suspend fun addTitle(input: File, output: File): String =
        service.export(
            inputPath = input.absolutePath,
            outputPath = output.absolutePath,
            durationSeconds = 5,
            title = "Your story"
        )

    suspend fun cancel() = service.cancel()
}
```

Call `addTitle` from a lifecycle-owned coroutine and surface failures in your app's UI. Wire cancellation to the wrapper's explicit `cancel()` method. The returned path is ready for your native Android player or sharing flow after the suspend call succeeds. This wrapper adds a title; extend its Swift implementation with the [image, picture-in-picture, and caption recipes](Recipes.md) as your app needs them.

## Choose preview and export settings

Use a small output for frequent previews and the delivery resolution for final exports. Preserve the source media for the operation's duration, reuse an exporter for sequential work, and cancel superseded previews. See [performance guidance](Guide.md#rendering-and-performance), [platform limits](Guide.md#platform-architecture-and-limits), and [tests and coverage](Testing.md).
