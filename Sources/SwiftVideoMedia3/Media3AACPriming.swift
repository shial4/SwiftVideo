// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

#if SKIP
import Foundation
import android.net.Uri
import java.io.RandomAccessFile

/// Apple's legacy Core Media AAC convention, before explicit roll sample groups.
/// Only recognizes a complete waveform, optionally preceded by an empty edit.
/// Other encoders, explicit timing, fragmented files, and complex edits are left
/// to Media3. See Apple's QuickTime "Using track structures to represent encoder
/// delay explicitly" specification. This is not a default delay for arbitrary AAC.
// SKIP @nobridge
public final class Media3AACPriming {
    public let delayFrames: Int
    public let paddingFrames: Int
    public let startUs: Int64
    public let endUs: Int64

    private init(delayFrames: Int, paddingFrames: Int, startUs: Int64, endUs: Int64) {
        self.delayFrames = delayFrames
        self.paddingFrames = paddingFrames
        self.startUs = startUs
        self.endUs = endUs
    }

    public static func inspect(source: String, trackID: Int, sampleRate: Int, profile: Int) -> Media3AACPriming? {
        let uri = Uri.parse(source)
        guard uri.getScheme() == "file", let path = uri.getPath(), profile == 2, sampleRate > 0 else { return nil }
        do {
            let file = RandomAccessFile(path, "r")
            defer { file.close() }
            let reader = AACMovieReader(file: file)
            return try reader.inspect(trackID: trackID, sampleRate: sampleRate)
        } catch { return nil }
    }

    private final class AACMovieReader {
        struct Box {
            let type: Int
            let body: Int64
            let end: Int64
        }
        let file: RandomAccessFile
        init(file: RandomAccessFile) { self.file = file }

        func inspect(trackID: Int, sampleRate: Int) throws -> Media3AACPriming? {
            let root = try boxes(start: 0, end: file.length())
            guard !root.contains(where: { $0.type == 0x6D6F6F66 }), // moof
                  let movie = root.first(where: { $0.type == 0x6D6F6F76 }), // moov
                  movie.end - movie.body <= 4 * 1024 * 1024 else { return nil }
            // iTunes metadata is already interpreted by Media3 and takes precedence.
            let bytes = kotlin.ByteArray(Int(movie.end - movie.body))
            file.seek(movie.body); file.readFully(bytes)
            let tag = [105, 84, 117, 110, 83, 77, 80, 66] // iTunSMPB
            if bytes.size >= tag.count {
                for offset in 0...(bytes.size - tag.count) {
                    if tag.indices.allSatisfy({ (Int(bytes[offset + $0]) & 255) == tag[$0] }) { return nil }
                }
            }
            let children = try boxes(start: movie.body, end: movie.end)
            guard !children.contains(where: { $0.type == 0x6D766578 }), // mvex
                  let header = children.first(where: { $0.type == 0x6D766864 }) else { return nil } // mvhd
            let movieScale = try timescale(header)
            guard movieScale > 0 else { return nil }
            for track in children where track.type == 0x7472616B { // trak
                let parts = try boxes(start: track.body, end: track.end)
                guard let tkhd = parts.first(where: { $0.type == 0x746B6864 }) else { continue }
                let version = try byte(tkhd, offset: 0)
                guard version <= 1, try uint(tkhd, offset: version == 1 ? 20 : 12) == Int64(trackID) else { continue }
                guard let mdia = parts.first(where: { $0.type == 0x6D646961 }),
                      let edts = parts.first(where: { $0.type == 0x65647473 }) else { return nil }
                return try timing(media: mdia, edits: edts, movieScale: movieScale, sampleRate: sampleRate)
            }
            return nil
        }

        private func timing(media: Box, edits: Box, movieScale: Int64, sampleRate: Int) throws -> Media3AACPriming? {
            let parts = try boxes(start: media.body, end: media.end)
            guard let handler = parts.first(where: { $0.type == 0x68646C72 }), // hdlr
                  try uint(handler, offset: 8) == Int64(0x736F756E), // soun
                  handler.end - handler.body == Int64(41) else { return nil }
            let name = [67, 111, 114, 101, 32, 77, 101, 100, 105, 97, 32, 65, 117, 100, 105, 111, 0]
            for index in name.indices where try byte(handler, offset: Int64(24 + index)) != name[index] { return nil }
            guard let mdhd = parts.first(where: { $0.type == 0x6D646864 }),
                  let minf = parts.first(where: { $0.type == 0x6D696E66 }),
                  let stbl = try boxes(start: minf.body, end: minf.end).first(where: { $0.type == 0x7374626C }) else { return nil }
            let samples = try boxes(start: stbl.body, end: stbl.end)
            guard !samples.contains(where: { $0.type == 0x73677064 || $0.type == 0x73626770 }), // sgpd, sbgp
                  let elst = try boxes(start: edits.body, end: edits.end).first(where: { $0.type == 0x656C7374 }) else { return nil }
            let version = try byte(elst, offset: 0)
            let count = try uint(elst, offset: 4)
            guard version <= 1, count == Int64(1) || count == Int64(2) else { return nil }
            let stride: Int64 = version == 1 ? 20 : 12
            guard elst.end - elst.body == 8 + stride * count else { return nil }
            var start: Int64 = 0
            var length: Int64 = 0
            for index in 0..<Int(count) {
                let offset = 8 + Int64(index) * stride
                let duration = version == 1 ? try long(elst, offset: offset) : try uint(elst, offset: offset)
                let mediaTime: Int64
                if version == 1 { mediaTime = try long(elst, offset: offset + 8, allowNegative: true) }
                else {
                    let unsigned = try uint(elst, offset: offset + 4)
                    mediaTime = unsigned >= 0x8000_0000 ? unsigned - 0x1_0000_0000 : unsigned
                }
                guard duration > 0, try uint(elst, offset: offset + stride - 4) == Int64(0x00010000) else { return nil }
                if count == Int64(2) && index == 0 {
                    guard mediaTime == Int64(-1) else { return nil }
                    start = duration
                } else {
                    guard mediaTime == Int64(0) else { return nil }
                    length = duration
                }
            }
            let scale = try timescale(mdhd)
            let mediaVersion = try byte(mdhd, offset: 0)
            let mediaDuration = mediaVersion == 1 ? try long(mdhd, offset: 24) : try uint(mdhd, offset: 16)
            guard scale > 0 else { return nil }
            let totalFrames = Double(mediaDuration) * Double(sampleRate) / Double(scale)
            let contentFrames = Double(length) * Double(sampleRate) / Double(movieScale)
            let padding = totalFrames - 2112 - contentFrames
            let startUs = Double(start) * 1_000_000 / Double(movieScale)
            let endUs = startUs + Double(length) * 1_000_000 / Double(movieScale)
            // A complete waveform has less than one AAC packet of remainder.
            // A larger value is an edited range, not encoder padding, and must
            // not become a potentially huge decoder padding buffer.
            guard padding >= 0, padding < 1024,
                  abs(padding - padding.rounded()) < 0.000_001,
                  endUs < Double(Int64.max) else { return nil }
            return Media3AACPriming(delayFrames: 2112, paddingFrames: Int(padding.rounded()),
                                   startUs: Int64(startUs.rounded()), endUs: Int64(endUs.rounded()))
        }

        private func boxes(start: Int64, end: Int64) throws -> [Box] {
            var result: [Box] = []
            var position = start
            while position < end {
                guard end - position >= 8, result.count < 4096 else { throw IllegalArgumentException("Invalid MP4 boxes") }
                file.seek(position)
                var size = Int64(file.readInt()) & 0xFFFF_FFFF
                let type = file.readInt()
                var header: Int64 = 8
                if size == Int64(1) {
                    guard end - position >= 16 else { throw IllegalArgumentException("Truncated MP4 box") }
                    size = file.readLong(); header = 16
                } else if size == Int64(0) { size = end - position }
                guard size >= header, size <= end - position else { throw IllegalArgumentException("Invalid MP4 box size") }
                result.append(Box(type: type, body: position + header, end: position + size))
                position += size
            }
            return result
        }

        private func timescale(_ box: Box) throws -> Int64 {
            let version = try byte(box, offset: 0)
            guard version <= 1 else { throw IllegalArgumentException("Unsupported MP4 time header") }
            return try uint(box, offset: version == 1 ? 20 : 12)
        }

        private func byte(_ box: Box, offset: Int64) throws -> Int {
            try position(box, offset: offset, size: 1)
            return file.readUnsignedByte()
        }

        private func uint(_ box: Box, offset: Int64) throws -> Int64 {
            try position(box, offset: offset, size: 4)
            return Int64(file.readInt()) & 0xFFFF_FFFF
        }

        private func long(_ box: Box, offset: Int64, allowNegative: Bool = false) throws -> Int64 {
            try position(box, offset: offset, size: 8)
            let value = file.readLong()
            guard allowNegative || value >= 0 else { throw IllegalArgumentException("MP4 time overflow") }
            return value
        }

        private func position(_ box: Box, offset: Int64, size: Int64) throws {
            guard offset >= 0, size <= box.end - box.body, offset <= box.end - box.body - size else {
                throw IllegalArgumentException("Truncated MP4 field")
            }
            file.seek(box.body + offset)
        }
    }
}
#endif
