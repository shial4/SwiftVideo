# Rendering fixtures

`music.m4a` is the AAC counterpart of the existing `music.wav` test tone. It was
encoded with `AVAssetExportSession`, `AVAssetExportPresetAppleM4A`, and output type
`.m4a`. Its SHA-256 is
`87fa8e65c82d1e35d45dbad0dc1e51c8561f24f319dcbceef92bc07a1ed6a49a`.
The preview trim regression compares PCM and compressed input at zero, 250 ms,
250.001 ms, and 300 ms, then seeks to 1731 ms and resumes. Expected fade timing
and the 0.01 RMS tolerance are unchanged. The preview cache decodes compressed
sources once, retains their initial track offset, and reuses PCM across seeks.
An independent AVAudioFile decode of both fixtures, weighting each sample by the
expected linear envelope, agrees with the analytic RMS values within 0.00005.

`red-with-music.mp4` and `red-with-offset-music.mp4` combine the existing red
video and AAC tone with `AVMutableComposition` and
`AVAssetExportPresetPassthrough`. The one-second video is repeated to cover the
two-second audio, starting at zero or 250 ms respectively. Their SHA-256 values
are `cab0f0293db42b82fd2cc1880cef8613100d957e3debf521aa036692114c2da2`
and `dc702173ddd9009b2ec274394be522be7799328cd5a16f7e9360a40d2ac8638c`.
An independent `AVAssetReaderAudioMixOutput` decode produces 96,000 and 108,000
stereo frames at 48 kHz. The offset fixture begins with exactly 12,000 silent
frames; the other begins immediately with the tone. This timeline-aware check
also confirms the original M4A contains exactly 96,000 frames.

The cache tests check source reuse, exact frame counts, starting silence or
audio, byte-preserving source ownership, cancellation, and quota failure cleanup.
The preview lifecycle test releases during preparation and checks scratch-folder
removal. The cache currently decodes complete sources with a cumulative 64 MiB
limit. It is used by the alpha library preview session, not yet by the app.

The Media3 1.12.0-alpha02 API 33 diagnostic run executes 50 tests with six
remaining issues: four video-color assertions and two baseline paused-seek
controls. Production preview uses `DefaultGlFrameProcessor` and passes continuous
video playback after a gap, including all four gap/source-trim cases. All 16 audio
trim/seek cases pass across raw PCM, standalone
AAC, embedded AAC, and delayed embedded AAC. Cache onset, exact frame counts,
source reuse, quota and cancellation cleanup, and release during preparation
also pass. The cache's 0.001 RMS and preview's 0.01 RMS tolerances are unchanged.

`AACFixtureReference` contains timeline-correct RMS values independently measured
with Apple's asset reader. `aacReferencesMatchAppleTimeline` verifies them on the
host, including exact sample counts and silence before the 250 ms offset. Using
Android's uncorrected MP4 decode as a reference would include the priming error
being fixed and compare different parts of the waveform.

`Media3AACPriming` recognizes the [legacy Core Media AAC convention](https://developer.apple.com/documentation/quicktime-file-format/using_track_structures_to_represent_encode_delay_explictly)
for local AAC-LC files with an exact Core Media audio handler, no explicit iTunes
or sample-group priming, and one media edit starting at zero, optionally preceded
by an empty edit. It reads at most 4 MiB of nonfragmented movie metadata, derives
the source offset and remainder, and accepts less than one AAC packet of padding.
The cache preserves all encoded preroll and removes the implicit 2112 frames
once during decoding. The source bytes and original render plan remain unchanged.
Unknown handlers, other profiles, explicit timing, malformed sizes, shifted or
shortened edits, and unsupported layouts retain Media3's existing handling.
The classification regression covers those boundaries. This remains a preview
alpha feature; it has not changed the app's preview implementation.

`PcmBoundaryExtractorsFactory`, now owned by `SwiftVideoMedia3`, splits PCM packet metadata at
the composition's source, end, and initial seek boundaries. It preserves the
sample bytes and compressed access units. This lets Media3 retain the portion of
a PCM packet after a cut instead of discarding the whole packet. The packet
contract check also verifies complete stereo frames, fractional cuts, trailing
data offsets, and the final-packet marker. The production session owns its cut
calculation; the probe delegates real-media playback to that same implementation.

`AndroidVideoPreview` is a native Swift owner of `Media3PreviewSession`. Export
and preview share validation, Codable serialization, composition construction,
and the native animation sampler. The session prepares off the UI thread and
owns its player, surfaces, decoded audio, and scratch files. It recreates the
player for paused seeks and coalesces rapid requests over 16 ms. Surface changes
preserve the requested position and playback intent; stale player errors cannot
fail a replacement player. The native-owner regression verifies unsupported and
empty-project rejection, early controls without a surface, and deinit cleanup.
The real pixel/audio check also covers rapid scrubbing and replacing the output
surface while paused or playing, end-of-timeline transport, and replay. The
continuous final-video frame assertion passes with the Media3 alpha frame
processor. App surface integration remains outstanding.

`bt709.mp4` is an original synthetic fixture from the editor's Android tests:
five seconds of 320x180 H.264 at 30 fps, with no audio. The right half is blue;
the left changes from red to green at 2.5 seconds. AVAssetWriter encoded immutable
sRGB BGRA buffers with explicit BT.709 primaries, transfer, and matrix tags.
Android's extractor and the Media3 decoder wrapper both report BT.709, limited
range, and SDR transfer (`[1, 2, 3]`). The MP4 container and H.264 SPS agree.

`Media3FrameDecoder` inspects decoded YUV planes through
[MediaCodec.getOutputImage](https://developer.android.com/reference/android/media/MediaCodec#getOutputImage(int)).
It honors crop, row/pixel strides, color standard, range, and nearest-frame timing,
and rejects unsupported formats. Absent or zero-valued metadata falls back to
the decoder's metadata, then the existing untagged SD fixtures' BT.601 limited
SDR convention. It is test-only Swift in the existing transpiled boundary.
The tagged-source test independently checks authored red, green, and blue values;
before/after equality through one decoder is not the only reference.

This replaces MediaMetadataRetriever pixel readback. On API 33, that API reported
blue 239 for a canonical export whose Y/Cb/Cr values are `[31, 239, 118]`, equivalent
to BT.709 blue about 252. Apple's independent raw decode and rendered frame agree
with the latter. Both the container and SPS specify BT.709 limited range.
Requesting ARGB_8888 did not correct the conversion. Direct YUV inspection removes
the three false preview/export blue failures without changing renderer code or
the eight-level channel tolerance. The mixed-media preview/export comparison now
passes all forward/backward sample positions, text placement, playback, and audio.

`imageExportPreservesPrimaryColors` checks red, green, and blue through four paths:
independent Media3 image export, a SwiftVideo image layer, generated background,
and a background with a later video segment. All twelve exports pass the same
eight-level tolerance; independent pre-encoder image samples agree within one
level. `decodedStillPreservesSourceColor` also passes for the tagged fixture's red
and green frames saved as PNG through the independent decoder.

A separate video-to-texture color discrepancy remains. Both SwiftVideo and the
independent `referenceMedia3PreservesDecodedColor` control change the red segment's
red channel from 253 to 230 and the green segment's red channel from 0 to 18 on
API 33. The control uses Media3 1.11.1 without SwiftVideo's project, render plan,
custom effects, or compositor. A readback effect forces processing and leaves
frames unchanged. Its pre-encoder texture samples are `[232, 0, 2]` and
`[19, 255, 8]`, so this error exists before encoding.

The source Y/Cb/Cr values `[62, 102, 239]` and `[171, 42, 26]` produce those texture
samples under BT.601 conversion despite explicit BT.709 input tags. Emulator
36.6.11 build 15507667 and Media3's
[SDR external-texture shader](https://github.com/androidx/media/blob/1.11.1/libraries/effect/src/main/res/raw/fragment_shader_transformation_sdr_external_es2.glsl)
are involved in that path. The
[emulator conversion source](https://android.googlesource.com/platform/hardware/google/gfxstream/+/refs/heads/main/host/gl/YUVConverter.cpp)
has metadata-dependent BT.601/BT.709 selection. This points to a decoder/graphics
metadata handoff; it does not establish the precise defect or physical-device
behavior. Earlier API 35 and forced `c2.android.avc.decoder` diagnostics reproduced
the video-color discrepancy. The permanent control uses the default decoder.

Keep the four video-color assertions active. Do not compensate every video with
a color filter or increase tolerance. Physical-device verification and a
production resolution remain outstanding. The alpha retains these known failures.
