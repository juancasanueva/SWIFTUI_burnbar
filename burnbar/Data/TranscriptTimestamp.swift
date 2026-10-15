//
//  TranscriptTimestamp.swift
//  burnbar
//

import Foundation

/// ISO8601 timestamps as transcripts write them, with or without fractional seconds.
nonisolated enum TranscriptTimestamp {
    private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let wholeSecond = Date.ISO8601FormatStyle()

    static func date(from text: String) -> Date? {
        (try? fractional.parse(text)) ?? (try? wholeSecond.parse(text))
    }
}
