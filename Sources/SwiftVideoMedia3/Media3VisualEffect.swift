// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

#if !SKIP_BRIDGE
/// Opaque bridge for a trusted, application-created Media3 GL effect.
/// Native Swift transports this handle without accessing GL objects or frame pixels.
public final class Media3VisualEffect {
    #if SKIP
    // SKIP @nobridge
    public let effect: androidx.media3.effect.GlEffect

    // SKIP @nobridge
    public init(_ effect: androidx.media3.effect.GlEffect) { self.effect = effect }
    #else
    private init() {}
    #endif
}
#endif
