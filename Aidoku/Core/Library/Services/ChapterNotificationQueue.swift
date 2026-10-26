//
//  ChapterNotificationQueue.swift
//  Aidoku
//

import AidokuRunner
import CryptoKit
import Foundation

struct ChapterNotificationSummary: Codable, Equatable, Sendable {
    let mangaIdentifier: MangaIdentifier
    let mangaTitle: String
    let chapterKeys: [String]

    var chapterCount: Int { chapterKeys.count }

    var chapterIdentifiers: [ChapterIdentifier] {
        chapterKeys.map {
            .init(sourceKey: mangaIdentifier.sourceKey, mangaKey: mangaIdentifier.mangaKey, chapterKey: $0)
        }
    }

    static func notificationIdentifier(for summaries: [Self]) -> String {
        let identifiers = Set(summaries.flatMap(\.chapterIdentifiers)).sorted {
            [$0.sourceKey, $0.mangaKey, $0.chapterKey].lexicographicallyPrecedes([$1.sourceKey, $1.mangaKey, $1.chapterKey])
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = (try? encoder.encode(identifiers)) ?? Data()
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return "newChapters.\(hash)"
    }
}

struct ChapterNotificationQueue: Codable, Sendable {
    private(set) var pending: [ChapterNotificationSummary] = []
    private(set) var delivered: [ChapterIdentifier] = []

    mutating func enqueue(_ summaries: [ChapterNotificationSummary]) {
        let deliveredKeys = Set(delivered)
        for summary in summaries {
            let keys = summary.chapterIdentifiers.filter { !deliveredKeys.contains($0) && !$0.chapterKey.isEmpty }.map(\.chapterKey)
            guard !keys.isEmpty else { continue }
            if let index = pending.firstIndex(where: { $0.mangaIdentifier == summary.mangaIdentifier }) {
                pending[index] = .init(
                    mangaIdentifier: summary.mangaIdentifier,
                    mangaTitle: summary.mangaTitle,
                    chapterKeys: Array(Set(pending[index].chapterKeys + keys)).sorted()
                )
            } else {
                pending.append(.init(
                    mangaIdentifier: summary.mangaIdentifier,
                    mangaTitle: summary.mangaTitle,
                    chapterKeys: Array(Set(keys)).sorted()
                ))
            }
        }
    }

    mutating func markDelivered(_ summaries: [ChapterNotificationSummary]) {
        let identifiers = Set(summaries.flatMap(\.chapterIdentifiers))
        let previous = Set(delivered)
        delivered.append(contentsOf: identifiers.subtracting(previous).sorted {
            [$0.sourceKey, $0.mangaKey, $0.chapterKey].lexicographicallyPrecedes([$1.sourceKey, $1.mangaKey, $1.chapterKey])
        })
        // Bound persistent deduplication history without discarding undelivered alerts.
        delivered = Array(delivered.suffix(10_000))
        pending = pending.compactMap { summary in
            let keys = summary.chapterIdentifiers.filter { !identifiers.contains($0) }.map(\.chapterKey)
            guard !keys.isEmpty else { return nil }
            return .init(mangaIdentifier: summary.mangaIdentifier, mangaTitle: summary.mangaTitle, chapterKeys: keys)
        }
    }

    mutating func discard(mangaIdentifier: MangaIdentifier) {
        pending.removeAll { $0.mangaIdentifier == mangaIdentifier }
    }

    mutating func clearPending() {
        pending.removeAll()
    }
}

enum ChapterNotificationPolicy {
    static func matchesFilters(
        _ chapter: AidokuRunner.Chapter,
        languageFilter: String?,
        scanlatorFilter: [String]
    ) -> Bool {
        guard languageFilter == nil || chapter.language == languageFilter else { return false }
        guard !scanlatorFilter.isEmpty else { return true }
        guard let scanlators = chapter.scanlators, !scanlators.isEmpty else {
            return scanlatorFilter.contains("")
        }
        return scanlatorFilter.contains(where: scanlators.contains)
    }

    static func eligibleChapterKeys(
        _ chapters: [AidokuRunner.Chapter],
        hasExistingChapters: Bool,
        languageFilter: String?,
        scanlatorFilter: [String]
    ) -> [String] {
        // The first successful chapter fetch establishes a baseline, not a backlog alert.
        guard hasExistingChapters else { return [] }
        return Array(Set(chapters.filter { chapter in
            !chapter.locked
                && matchesFilters(chapter, languageFilter: languageFilter, scanlatorFilter: scanlatorFilter)
        }.map(\.key))).sorted()
    }
}
