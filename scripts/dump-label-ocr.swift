#!/usr/bin/swift
// Debug dump: run the app's OCR configuration over label photos and emit
// fixture transcripts for LabelParserTests.
//
//   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
//     swift scripts/dump-label-ocr.swift photo.jpg > fixture.json
//
// Mirrors LabelScan.swift: RecognizeTextRequest, .accurate, language
// correction OFF (correction mangles "0g" → "Og" and unit strings).
// Boxes are Vision-normalized rects, origin lower-left — the exact input
// LabelParser sees on device.

import Foundation
import Vision

struct DumpObservation: Codable {
    let text: String
    let x: Double
    let y: Double
    let w: Double
    let h: Double
}

struct Dump: Codable {
    let image: String
    let observations: [DumpObservation]
}

let paths = Array(CommandLine.arguments.dropFirst())
guard !paths.isEmpty else {
    FileHandle.standardError.write(Data("usage: dump-label-ocr.swift <image>...\n".utf8))
    exit(64)
}

var dumps: [Dump] = []
for path in paths {
    let url = URL(fileURLWithPath: path)
    var request = RecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = false
    request.automaticallyDetectsLanguage = true

    let results = try await request.perform(on: url)
    let observations = results.compactMap { observation -> DumpObservation? in
        guard let candidate = observation.topCandidates(1).first else { return nil }
        let rect = observation.boundingBox.cgRect
        return DumpObservation(
            text: candidate.string,
            x: Double(rect.origin.x), y: Double(rect.origin.y),
            w: Double(rect.width), h: Double(rect.height))
    }
    dumps.append(Dump(image: url.lastPathComponent, observations: observations))
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
let payload = dumps.count == 1 ? try encoder.encode(dumps[0]) : try encoder.encode(dumps)
print(String(decoding: payload, as: UTF8.self))
