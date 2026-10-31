@testable import Sumi
import CoreData
import Foundation
import Testing

struct HonbakoAutomationManagementTests {
    @Test("History pagination includes completed chapters outside the library without a recent-only cutoff")
    @MainActor
    func fullHistory() throws {
        let model = try #require(NSManagedObjectModel.mergedModel(from: [Bundle(for: CoreDataManager.self)])?.copy() as? NSManagedObjectModel)
        for entity in model.entities { entity.properties = entity.properties.filter { !($0 is NSDerivedAttributeDescription) } }
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        try coordinator.addPersistentStore(ofType: NSInMemoryStoreType, configurationName: nil, at: nil)
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        let now = Date.now
        for index in 0..<125 {
            let history = HistoryObject(context: context)
            history.sourceId = "removed-source"
            history.mangaId = "outside-library"
            history.chapterId = "chapter-\(index)"
            history.dateRead = now.addingTimeInterval(Double(-index - 1))
            history.progress = 12; history.total = 12; history.completed = true
        }
        try context.save()
        let first = try HonbakoAutomationHistory.page(offset: 0, limit: 100, before: now.ISO8601Format(), context: context)
        #expect(first.entries.count == 100)
        #expect(first.nextOffset == 100)
        let second = try HonbakoAutomationHistory.page(offset: try #require(first.nextOffset), limit: 100, before: first.before, context: context)
        #expect(second.entries.count == 25)
        #expect(second.nextOffset == nil)
        #expect(Set((first.entries + second.entries).map(\.chapterId)).count == 125)
        #expect(second.entries.allSatisfy { $0.completed && $0.page == 12 && $0.sourceId == "removed-source" })
    }

    @Test("Source commands validate their exact fields and keep credentials out of MCP")
    func sourceChanges() throws {
        typealias Change = HonbakoAutomationManagement.Change
        for action in ["install", "enable", "disable", "remove"] {
            try Change(action: action, sourceId: "source-id").validate()
        }
        try Change(action: "refresh_repositories").validate()
        try Change(action: "add_repository", repositoryURL: "https://owner.example/sources.json").validate()
        for text in ["http://owner.example/list", "https://user:secret@owner.example/list", "https://owner.example/list?token=secret", "https://owner.example/list#secret"] {
            #expect(Change.safeRepository(text) == nil)
        }
        #expect(throws: (any Error).self) { try Change(action: "install", sourceId: "source-id", repositoryURL: "https://owner.example").validate() }
        #expect(throws: (any Error).self) { try Change(action: "execute").validate() }
    }

    @Test("History jobs reject extra write commands, huge pages and missing snapshot boundaries")
    func jobScope() throws {
        typealias Models = HonbakoAutomationModels
        let payload = Models.Payload(limit: 100, offset: 0, before: Date.now.ISO8601Format())
        let job = Models.Job(id: UUID().uuidString, kind: "history.read", payload: payload, status: "queued", createdAt: Date.now.ISO8601Format())
        try HonbakoAutomationPolicy.validate(job)
        for edit in [Models.Payload(limit: 101, offset: 0, before: payload.before), Models.Payload(limit: 10, offset: 0),
                     Models.Payload(limit: 10, offset: 0, before: payload.before, change: .init(action: "refresh_repositories"))] {
            #expect(throws: (any Error).self) {
                try HonbakoAutomationPolicy.validate(.init(id: job.id, kind: job.kind, payload: edit, status: "queued", createdAt: job.createdAt))
            }
        }
    }
}
