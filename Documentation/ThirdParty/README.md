<!-- Copyright 2026 Software Deck Pty Ltd; SPDX-License-Identifier: Apache-2.0 -->
# Third-party dependencies for 0.0.1

SwiftVideo's Apache 2.0 license applies to first-party work. The dependencies below retain their own licenses and copyrights. License texts are copied verbatim. Source links identify the exact resolved revisions, including corresponding source for MPL-covered components. No dependency sources are modified.

| Swift package | Resolved version | License | Corresponding source |
| --- | --- | --- | --- |
| skip | 1.9.19 | [License](skip-LICENSE.txt) | [5693198fd045](https://github.com/skiptools/skip/tree/5693198fd045a8ba1abf3e18405584ec3184fd0c) |
| skip-android-bridge | 0.7.4 | [License](skip-android-bridge-LICENSE.txt) | [19e85888165f](https://github.com/skiptools/skip-android-bridge/tree/19e85888165f952421b11d90f11793b33d2d75a4) |
| skip-av | 0.7.2 | [License](skip-av-LICENSE.txt) | [aa2935e0c9bf](https://github.com/skiptools/skip-av/tree/aa2935e0c9bf4162742306e04b6705081569546e) |
| skip-bridge | 0.18.0 | [License](skip-bridge-LICENSE.txt) | [83866d718c09](https://github.com/skiptools/skip-bridge/tree/83866d718c09ca508f499744fc8896a891074a3f) |
| skip-foundation | 1.4.8 | [License](skip-foundation-LICENSE.txt) | [8b50c7dc6161](https://github.com/skiptools/skip-foundation/tree/8b50c7dc61610f0bfff5512db4ea628554003bfa) |
| skip-fuse | 1.0.3 | [License](skip-fuse-LICENSE.txt) | [8b69bb0b5be7](https://github.com/skiptools/skip-fuse/tree/8b69bb0b5be7df880b8f9b3d2eb6659909a5b5c5) |
| skip-fuse-ui | 1.19.1 | [License](skip-fuse-ui-LICENSE.txt) | [e4590b761658](https://github.com/skiptools/skip-fuse-ui/tree/e4590b7616589c21eca791a77914d1d062bc67fa) |
| skip-lib | 1.4.4 | [License](skip-lib-LICENSE.txt) | [f85cb3896c84](https://github.com/skiptools/skip-lib/tree/f85cb3896c84410fb20f9f921a5ccf3254c21843) |
| skip-model | 1.8.1 | [License](skip-model-LICENSE.txt) | [bd8a83dfe098](https://github.com/skiptools/skip-model/tree/bd8a83dfe098eff4626b974dd3f706d017e08d79) |
| skip-ui | 1.64.0 | [License](skip-ui-LICENSE.txt) | [d170d85b9b33](https://github.com/skiptools/skip-ui/tree/d170d85b9b337b82b630439c633aea2d0eb6ca3e) |
| skip-unit | 1.7.2 | [License](skip-unit-LICENSE.txt) | [fc58e058f3d2](https://github.com/skiptools/skip-unit/tree/fc58e058f3d25675e047a758281c39dba5d52570) |
| swift-android-native | 1.5.3 | [License](swift-android-native-LICENSE.txt) | [d757c18d7126](https://github.com/skiptools/swift-android-native/tree/d757c18d7126dea382534e6e4f484b29240f3545) |
| swift-jni | 0.5.1 | [License](swift-jni-LICENSE.txt) | [71385f88cfff](https://github.com/skiptools/swift-jni/tree/71385f88cfff14409fe105e27fcad3ebd44348d0) |

Android rendering also uses AndroidX Media3 Transformer and Effect 1.11.1 under Apache 2.0. Their POMs identify transitive dependencies; downstream applications must retain notices for the versions they resolve and distribute. [Media3 source](https://github.com/androidx/media/tree/1.11.1), [license](https://github.com/androidx/media/blob/1.11.1/LICENSE).

The example platform shells were produced by Skip 1.9.19. The Android shell is unmodified generated output. Its Gradle wrapper is Gradle project code under Apache 2.0: [Gradle license and notices](https://github.com/gradle/gradle/blob/v9.0.0/LICENSE).

The source release does not bundle Apple frameworks, Swift toolchains, Android SDK/NDK binaries, or dependency build products. A downstream binary distributor is responsible for the notices and source obligations of its complete resolved application. Regenerate this inventory with `swift Tools/DependencyNotices.swift` after resolving both packages.
