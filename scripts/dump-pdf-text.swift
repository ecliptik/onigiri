#!/usr/bin/swift
// Debug dump: extract a PDF's text layer as positioned runs and emit
// fixture transcripts for MenuTableParserTests.
//
//   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
//     swift scripts/dump-pdf-text.swift menu.pdf > fixture.json
//   ... --page 2        just that page (1-based)
//
// MIRRORS Onigiri/Models/MenuDocument.swift — extraction here and there
// must stay identical, exactly as dump-label-ocr.swift mirrors
// LabelScan.swift. A fixture captured here is the input the parser sees
// on device; if these drift, the tests stop testing the shipping path.
//
// Boxes come out Vision-normalized: origin lower-left, unit square. PDF
// page space already has that origin, so this is a divide by the page
// bounds and nothing else.
//
// WHY selectionsByLine AND NOT characterBounds. The obvious approach —
// walk 0..<numberOfCharacters, take each glyph's box, group them into
// runs — does not survive contact with a real print-design PDF.
// `characterBounds(at:)` on the CAVA guide reports the "i" in
// "Spicy" as 68 pt wide and hands back ZERO-HEIGHT boxes for 185 of
// 2,133 glyphs (every "f" among them), so runs both mis-measure and
// silently lose letters. `selectionsByLine()` returns each positioned
// text run with correct text and correct bounds — which is already the
// granularity a table needs, one run per cell.

import Foundation
import PDFKit

struct DumpObservation: Codable {
    let text: String
    let x: Double
    let y: Double
    let w: Double
    let h: Double
}

struct DumpPage: Codable {
    let page: Int
    let observations: [DumpObservation]
}

struct Dump: Codable {
    let document: String
    let pages: [DumpPage]
}

func runs(on page: PDFPage) -> [DumpObservation] {
    let bounds = page.bounds(for: .mediaBox)
    guard bounds.width > 0, bounds.height > 0,
          let whole = page.selection(for: bounds) else { return [] }
    return whole.selectionsByLine().compactMap { line in
        let text = (line.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let rect = line.bounds(for: page)
        guard rect.width.isFinite, rect.height.isFinite, rect.height > 0 else { return nil }
        return DumpObservation(
            text: text,
            x: Double((rect.minX - bounds.minX) / bounds.width),
            y: Double((rect.minY - bounds.minY) / bounds.height),
            w: Double(rect.width / bounds.width),
            h: Double(rect.height / bounds.height))
    }
}

var arguments = Array(CommandLine.arguments.dropFirst())
var wanted: Int?
if let flag = arguments.firstIndex(of: "--page"), flag + 1 < arguments.count {
    wanted = Int(arguments[flag + 1])
    arguments.removeSubrange(flag...(flag + 1))
}
guard let path = arguments.first else {
    FileHandle.standardError.write(Data("usage: dump-pdf-text.swift <pdf> [--page N]\n".utf8))
    exit(64)
}
let url = URL(fileURLWithPath: path)
guard let document = PDFDocument(url: url) else {
    FileHandle.standardError.write(Data("could not open \(path)\n".utf8))
    exit(65)
}

var pages: [DumpPage] = []
for number in 0..<document.pageCount {
    if let wanted, wanted != number + 1 { continue }
    guard let page = document.page(at: number) else { continue }
    pages.append(DumpPage(page: number + 1, observations: runs(on: page)))
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
let payload = try encoder.encode(Dump(document: url.lastPathComponent, pages: pages))
print(String(decoding: payload, as: UTF8.self))
