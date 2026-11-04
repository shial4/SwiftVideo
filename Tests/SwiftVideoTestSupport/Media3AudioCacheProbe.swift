// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

#if !SKIP_BRIDGE
import Foundation
#if SKIP
import SwiftVideoMedia3
import java.io.File
import org.json.JSONArray
import org.json.JSONObject
#endif

public final class Media3AudioCacheProbe {
    public static func legacyTiming(source: String, trackID: Int, profile: Int) -> [Int64] {
        #if SKIP
        guard let timing = Media3AACPriming.inspect(source: source, trackID: trackID, sampleRate: 48000, profile: profile) else { return [] }
        return [Int64(timing.delayFrames), Int64(timing.paddingFrames), timing.startUs, timing.endUs]
        #else
        return []
        #endif
    }

    public static func prepare(source: String, directory: String, maximumBytes: Int64, cancelAfterCheck: Int,
                               sourceStartUs: Int64 = 0, durationUs: Int64 = 2_000_000,
                               secondSourceStartUs: Int64? = nil) throws -> [String] {
        #if SKIP
        let clips = JSONArray()
        for start in [sourceStartUs, secondSourceStartUs ?? sourceStartUs] {
            clips.put(JSONObject().put("kind", "audio").put("muted", false).put("url", source)
                .put("sourceStartUs", start).put("durationUs", durationUs).put("sourceDurationUs", durationUs))
        }
        let plan = JSONObject().put("clips", clips)
        let original = plan.toString()
        // Negative requests the production disk-budget policy for integration tests.
        let cache = Media3PreviewAudioCache(folder: File(directory), maximumBytes: maximumBytes < 0 ? nil : maximumBytes)
        var checks = 0
        let prepared = try cache.prepare(plan, cancelled: {
            checks += 1
            return cancelAfterCheck > 0 && checks >= cancelAfterCheck
        })
        let repeated = try cache.prepare(plan, cancelled: { false })
        guard plan.toString() == original else { throw IllegalStateException("Preparation mutated its input") }
        return [prepared.getJSONArray("clips").getJSONObject(0).getString("audioURL"),
                prepared.getJSONArray("clips").getJSONObject(1).getString("audioURL"),
                repeated.getJSONArray("clips").getJSONObject(0).getString("audioURL")]
        #else
        return []
        #endif
    }
}
#endif
