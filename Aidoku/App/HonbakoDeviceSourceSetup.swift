#if SUMI && DEBUG
import AidokuRunner
import Foundation

/// A developer-tool operation for an explicitly requested personal-device
/// setup. Ordinary launches and release builds never install source lists.
@MainActor
enum HonbakoDeviceSourceSetup {
    private struct Receipt: Encodable {
        let processID = ProcessInfo.processInfo.processIdentifier
        let requested: [String]
        var phase = "installing"
        var installedVersions: [String: Int] = [:]
        var languages: [String: [String]] = [:]
        var catalogResultCounts: [String: Int] = [:]
        var failures: [String: String] = [:]
    }

    static func runIfRequested() async {
        let arguments = ProcessInfo.processInfo.arguments
        guard let list = arguments.first(where: { $0.hasPrefix("--honbako-source-list=") }),
              let requested = arguments.first(where: { $0.hasPrefix("--honbako-add-sources=") }),
              let url = URL(string: String(list.dropFirst("--honbako-source-list=".count))),
              url.scheme == "https", url.host != nil else { return }
        let keys = Set(requested.dropFirst("--honbako-add-sources=".count)
            .split(separator: ",").map(String.init))
        guard !keys.isEmpty, keys.count <= 20,
              keys.allSatisfy({ $0.range(of: #"^[a-z0-9-]+\.[a-z0-9.-]+$"#, options: .regularExpression) != nil }) else { return }

        var receipt = Receipt(requested: keys.sorted())
        write(receipt)
        let manager = SourceManager.shared
        await manager.waitForSourcesLoad()
        if await manager.getSourceListURLs().contains(url) {
            await manager.startSourceListsReload()
            await manager.waitForSourceListsLoad()
        } else if !(await manager.addSourceList(url: url)) {
            receipt.phase = "failed"
            receipt.failures["catalog"] = "The requested source catalog could not be loaded."
            write(receipt)
            return
        }

        if let (completed, _) = await manager.installExternalSources(keys: keys) {
            for await _ in completed { /* The final inventory is authoritative. */ }
        }
        for key in keys.sorted() {
            await manager.enable(sourceKey: key)
            guard let source = await manager.source(for: key) else {
                receipt.failures[key] = "The source package could not be installed or loaded."
                continue
            }
            receipt.installedVersions[key] = source.version
            receipt.languages[key] = source.languages
        }
        receipt.phase = "checking"
        write(receipt)

        // One public catalog request per chosen source. No chapters, pages,
        // library entries, reading history or paid model requests are created.
        if arguments.contains("--honbako-check-sources") {
            for key in keys.sorted() {
                guard let source = await manager.source(for: key) else { continue }
                do {
                    let listings = try await source.getListings()
                    let result: AidokuRunner.MangaPageResult
                    if let listing = listings.first {
                        result = try await source.getMangaList(listing: listing, page: 1)
                    } else {
                        result = try await source.getSearchMangaList(query: nil, page: 1, filters: [])
                    }
                    receipt.catalogResultCounts[key] = result.entries.count
                    if result.entries.isEmpty { receipt.failures[key] = "This source returned an empty catalog." }
                } catch {
                    // Provider errors can contain URLs or credentials. The
                    // receipt records only the operation, never those values.
                    receipt.failures[key] = "The source loaded, but its public catalog could not be reached."
                }
                write(receipt)
            }
        }
        receipt.phase = "finished"
        write(receipt)
        await SumiCatalogBootstrap.shared.prepare()
    }

    private static func write(_ receipt: Receipt) {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        do {
            try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(receipt).write(to: caches.appendingPathComponent("HonbakoSourceSetup.json"), options: .atomic)
        } catch {
            LogManager.logger.error("Honbako device setup receipt could not be saved.")
        }
    }
}
#endif
