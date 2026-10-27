#if SUMI
import Foundation

/// A catalog may enable a reviewed connector already compiled into this app.
/// It cannot choose an executable, class name, endpoint or arbitrary runner.
enum HonbakoNativeSourceDescriptor {
    static let mangaDexRunnerID = "honbako.mangadex.rest.v1"

    static func supports(_ info: ExternalSourceInfo) -> Bool {
        info.nativeRunner == mangaDexRunnerID && info.id == HonbakoMangaDexRunner.sourceKey && info.version == 1
    }
}
#endif
