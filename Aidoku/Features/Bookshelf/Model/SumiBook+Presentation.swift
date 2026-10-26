#if SUMI
import SwiftUI

extension SumiBook {
    var editionLabel: String {
        switch sourceKey {
            case "en.weebcentral": "Weeb Central"
            case "multi.mangaplus": "MANGA Plus"
            case "multi.mangadex": "MangaDex"
            case "multi.webtoon": "WEBTOON"
            default: "Local edition"
        }
    }

    var presentation: BookPresentation {
        let index = title.utf8.reduce(0) { ($0 + Int($1)) % SumiTheme.accents.count }
        return BookPresentation(
            id: "\(manga.sourceKey):\(manga.key)", title: title,
            author: author ?? "", coverURL: coverURL,
            blurb: blurb ?? "", chapterLabel: chapterLabel,
            pageLabel: pageLabel, progress: progress, accentColor: SumiTheme.accents[index]
        )
    }
}
#endif
