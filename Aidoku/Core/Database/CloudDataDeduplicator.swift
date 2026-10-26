import CoreData

/// CloudKit cannot enforce uniqueness. Merge the user data and relationships of
/// duplicate logical records before removing the extra record.
enum CloudDataDeduplicator {
    static func deduplicate(
        objectID: NSManagedObjectID,
        context: NSManagedObjectContext,
        stableKey: (NSManagedObjectID) -> String = { $0.uriRepresentation().absoluteString }
    ) {
        guard let object = try? context.existingObject(with: objectID), !object.isDeleted,
              let predicate = identityPredicate(for: object), let entityName = object.entity.name else { return }
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        request.predicate = predicate
        guard let objects = try? context.fetch(request), objects.count > 1 else { return }
        // A CloudKit record name is stable across devices; object IDs are a
        // fallback for local records that have not been exported yet.
        let ordered = objects.sorted { stableKey($0.objectID) < stableKey($1.objectID) }
        guard let survivor = ordered.first else { return }
        for duplicate in ordered.dropFirst() where !duplicate.isDeleted {
            merge(duplicate, into: survivor, context: context, stableKey: stableKey)
            context.delete(duplicate)
        }
    }

    private static func identityPredicate(for object: NSManagedObject) -> NSPredicate? {
        switch object {
            case let manga as MangaObject:
                NSPredicate(format: "sourceId == %@ AND id == %@", manga.sourceId, manga.id)
            case let category as CategoryObject:
                NSPredicate(format: "title == %@ AND group == %@", category.title ?? "", NSNumber(value: category.group))
            case let chapter as ChapterObject:
                NSPredicate(format: "sourceId == %@ AND mangaId == %@ AND id == %@", chapter.sourceId, chapter.mangaId, chapter.id)
            case let history as HistoryObject:
                NSPredicate(format: "sourceId == %@ AND mangaId == %@ AND chapterId == %@", history.sourceId, history.mangaId, history.chapterId)
            case let library as LibraryMangaObject:
                library.manga.map {
                    NSPredicate(format: "manga.sourceId == %@ AND manga.id == %@", $0.sourceId, $0.id)
                }
            case let track as TrackObject:
                NSPredicate(format: "id == %@ AND trackerId == %@ AND sourceId == %@ AND mangaId == %@",
                            track.id ?? "", track.trackerId ?? "", track.sourceId ?? "", track.mangaId ?? "")
            default:
                nil
        }
    }

    private static func merge(
        _ duplicate: NSManagedObject,
        into survivor: NSManagedObject,
        context: NSManagedObjectContext,
        stableKey: (NSManagedObjectID) -> String
    ) {
        switch (survivor, duplicate) {
            case let (target as HistoryObject, source as HistoryObject):
                mergeHistory(source, into: target)
            case let (target as LibraryMangaObject, source as LibraryMangaObject):
                mergeLibrary(source, into: target)
            case let (target as MangaObject, source as MangaObject):
                for chapter in source.chapters?.allObjects as? [ChapterObject] ?? [] {
                    chapter.manga = target
                }
                if let sourceLibrary = source.libraryObject {
                    if let targetLibrary = target.libraryObject {
                        let pair = ordered(targetLibrary, sourceLibrary, stableKey: stableKey)
                        mergeLibrary(pair.remove, into: pair.keep)
                        pair.remove.manga = nil
                        pair.keep.manga = target
                        context.delete(pair.remove)
                    } else {
                        sourceLibrary.manga = target
                    }
                }
                if target.fileInfo == nil { target.fileInfo = source.fileInfo }
                mergeMangaMetadata(source, into: target)
            case let (target as ChapterObject, source as ChapterObject):
                if target.manga == nil { target.manga = source.manga }
                if let sourceHistory = source.history {
                    if let targetHistory = target.history {
                        let pair = ordered(targetHistory, sourceHistory, stableKey: stableKey)
                        mergeHistory(pair.remove, into: pair.keep)
                        pair.remove.chapter = nil
                        pair.keep.chapter = target
                        context.delete(pair.remove)
                    } else {
                        sourceHistory.chapter = target
                    }
                }
                if let sourceUpdate = source.mangaUpdate {
                    if let targetUpdate = target.mangaUpdate {
                        let pair = ordered(targetUpdate, sourceUpdate, stableKey: stableKey)
                        pair.keep.viewed = pair.keep.viewed || pair.remove.viewed
                        pair.keep.date = [pair.keep.date, pair.remove.date].compactMap { $0 }.max()
                        pair.remove.chapter = nil
                        pair.keep.chapter = target
                        context.delete(pair.remove)
                    } else {
                        sourceUpdate.chapter = target
                    }
                }
                if target.fileInfo == nil { target.fileInfo = source.fileInfo }
                for name in ["title", "scanlator", "url", "thumbnail", "chapter", "volume", "dateUploaded"]
                    where target.value(forKey: name) == nil {
                    target.setValue(source.value(forKey: name), forKey: name)
                }
            case let (target as CategoryObject, source as CategoryObject):
                for library in source.libraryObjects?.allObjects as? [LibraryMangaObject] ?? [] {
                    library.addToCategories(target)
                }
                if target.data == nil { target.data = source.data }
            default:
                break
        }
    }

    private static func ordered<T: NSManagedObject>(
        _ first: T, _ second: T, stableKey: (NSManagedObjectID) -> String
    ) -> (keep: T, remove: T) {
        stableKey(first.objectID) < stableKey(second.objectID) ? (first, second) : (second, first)
    }

    private static func mergeMangaMetadata(_ source: MangaObject, into target: MangaObject) {
        let sourceEdits = EditedKeys(rawValue: source.editedKeys)
        let targetEdits = EditedKeys(rawValue: target.editedKeys)
        let fields: [(String, EditedKeys)] = [
            ("title", .title), ("author", .authors), ("artist", .artists),
            ("desc", .description), ("tags", .tags), ("cover", .cover),
            ("url", .url), ("status", .status), ("nsfw", .contentRating),
            ("viewer", .viewer), ("neverUpdate", .neverUpdate)
        ]
        for (name, key) in fields {
            if sourceEdits.contains(key), !targetEdits.contains(key) {
                // A deliberate cleared value is an edit too.
                target.setValue(source.value(forKey: name), forKey: name)
            } else if !targetEdits.contains(key), target.value(forKey: name) == nil {
                target.setValue(source.value(forKey: name), forKey: name)
            }
        }
        if target.title.isEmpty, !targetEdits.contains(.title), !sourceEdits.contains(.title) {
            target.title = source.title
        }
        target.editedKeys = sourceEdits.union(targetEdits).rawValue
    }

    private static func mergeHistory(_ source: HistoryObject, into target: HistoryObject) {
        let sourceDate = source.dateRead ?? .distantPast
        let targetDate = target.dateRead ?? .distantPast
        // The latest deliberate action wins, including rereading an earlier page.
        // When timestamps tie, preserve the greater recorded progress.
        let sourceIsNewer = sourceDate > targetDate || (sourceDate == targetDate && (
            (source.completed && !target.completed) || (source.completed == target.completed && source.progress > target.progress)
        ))
        if sourceIsNewer {
            target.dateRead = source.dateRead
            target.completed = source.completed
            target.progress = source.progress
            target.total = source.total
            target.scrollPosition = source.scrollPosition
            if target.entity.attributesByName["readDeviceID"] != nil,
               source.entity.attributesByName["readDeviceID"] != nil {
                target.readDeviceID = source.readDeviceID
                target.readDeviceName = source.readDeviceName
            }
        }
        if target.chapter == nil { target.chapter = source.chapter }
        for session in source.sessions?.allObjects as? [ReadingSessionObject] ?? [] {
            session.history = target
        }
    }

    private static func mergeLibrary(_ source: LibraryMangaObject, into target: LibraryMangaObject) {
        target.dateAdded = min(target.dateAdded, source.dateAdded)
        target.lastOpened = max(target.lastOpened, source.lastOpened)
        target.lastUpdated = max(target.lastUpdated, source.lastUpdated)
        target.lastUpdatedChapters = max(target.lastUpdatedChapters, source.lastUpdatedChapters)
        target.lastRead = [target.lastRead, source.lastRead].compactMap { $0 }.max()
        target.lastChapter = [target.lastChapter, source.lastChapter].compactMap { $0 }.max()
        if target.manga == nil { target.manga = source.manga }
        for category in source.categories?.allObjects as? [CategoryObject] ?? [] {
            target.addToCategories(category)
        }
    }
}
