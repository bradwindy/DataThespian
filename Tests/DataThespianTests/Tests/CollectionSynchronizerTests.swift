//
//  CollectionSynchronizerTests.swift
//  DataThespian
//

import Foundation
import Testing

@testable import DataThespian

#if canImport(SwiftData)
  import SwiftData
#endif

@Suite(.enabled(if: swiftDataIsAvailable()))
internal struct CollectionSynchronizerTests {
  #if canImport(SwiftData)
    private struct SynchronizeFailure: Error {}

    private enum ParentSynchronizer: CollectionSynchronizer {
      typealias PersistentModelType = Parent
      typealias DataType = ParentData
      typealias ID = UUID

      static var dataKey: KeyPath<ParentData, UUID> { \ParentData.id }
      static var persistentModelKey: KeyPath<Parent, UUID> { \Parent.id }

      static func getSelector(from data: ParentData) -> DataThespian.Selector<Parent>.Get {
        let id = data.id
        return .predicate(#Predicate<Parent> { $0.id == id })
      }

      static func persistentModel(from data: ParentData) -> Parent {
        let parent = Parent(id: data.id)
        parent.name = data.name
        return parent
      }

      static func synchronize(_ persistentModel: Parent, with data: ParentData) throws {
        if data.name == "fail" {
          throw SynchronizeFailure()
        }
        persistentModel.name = data.name
      }
    }

    private typealias Difference = DataThespian.CollectionDifference<Parent, ParentData>

    private static func seed(_ ids: [UUID], in database: any Database) async throws {
      try await database.withModelContext { context in
        for id in ids {
          context.insert(Parent(id: id))
        }
        try context.save()
      }
    }

    @Test(arguments: DatabaseKind.allCases)
    internal func synchronizeAppliesInsertsUpdatesAndDeletes(kind: DatabaseKind) async throws {
      let container = try DatabaseKind.makeContainer(for: Parent.self, Child.self)
      let database = kind.makeDatabase(modelContainer: container)
      let ids = (0..<4).map { _ in UUID() }
      try await Self.seed([ids[0], ids[1], ids[2]], in: database)
      let data = [
        ParentData(id: ids[1], name: "b"),
        ParentData(id: ids[2], name: "c"),
        ParentData(id: ids[3], name: "d"),
      ]

      let insertedIDs = try await database.withModelContext { context in
        let parents = try context.fetch(FetchDescriptor<Parent>())
        let difference = Difference(
          persistentModels: parents, data: data, persistentModelKeyPath: \.id, dataKeyPath: \.id
        )
        let inserted = try ParentSynchronizer.synchronizeDifference(difference, using: context)
        try context.save()
        return inserted.map(\.id)
      }
      #expect(insertedIDs == [ids[3]])

      let verify = ModelContext(container)
      let stored = try verify.fetch(FetchDescriptor<Parent>())
      let namesByID = Dictionary(uniqueKeysWithValues: stored.map { ($0.id, $0.name) })
      #expect(namesByID == [ids[1]: "b", ids[2]: "c", ids[3]: "d"])
    }

    /// A throwing `synchronize` used to leave the deletes, inserts and earlier updates pending,
    /// where the next unrelated save committed them.
    @Test(arguments: DatabaseKind.allCases)
    internal func failedSynchronizeLeavesNoPendingChanges(kind: DatabaseKind) async throws {
      let container = try DatabaseKind.makeContainer(for: Parent.self, Child.self)
      let database = kind.makeDatabase(modelContainer: container)
      let ids = (0..<4).map { _ in UUID() }
      try await Self.seed([ids[0], ids[1], ids[2]], in: database)
      let data = [
        ParentData(id: ids[1], name: "b"),
        ParentData(id: ids[2], name: "fail"),
        ParentData(id: ids[3], name: "d"),
      ]

      let hasChanges = try await database.withModelContext { context in
        let parents = try context.fetch(FetchDescriptor<Parent>())
        let difference = Difference(
          persistentModels: parents, data: data, persistentModelKeyPath: \.id, dataKeyPath: \.id
        )
        #expect(throws: SynchronizeFailure.self) {
          _ = try ParentSynchronizer.synchronizeDifference(difference, using: context)
        }
        return context.hasChanges
      }
      #expect(hasChanges == false)

      try await database.save()
      let storedIDs = try ModelContext(container).fetch(FetchDescriptor<Parent>()).map(\.id)
      #expect(Set(storedIDs) == Set([ids[0], ids[1], ids[2]]))
    }

    /// Update targets used to be found again through `getSelector(from:)`, a store-wide
    /// lookup that could pick a different row with the same key than the one compared.
    @Test(arguments: DatabaseKind.allCases)
    internal func synchronizeUpdatesTheComparedModel(kind: DatabaseKind) async throws {
      let container = try DatabaseKind.makeContainer(for: Parent.self, Child.self)
      let database = kind.makeDatabase(modelContainer: container)
      let sharedID = UUID()

      let names = try await database.withModelContext { context in
        let compared = Parent(id: sharedID)
        compared.name = "compared"
        let other = Parent(id: sharedID)
        other.name = "other"
        context.insert(other)
        context.insert(compared)
        try context.save()

        let difference = Difference(
          persistentModels: [compared],
          data: [ParentData(id: sharedID, name: "updated")],
          persistentModelKeyPath: \.id,
          dataKeyPath: \.id
        )
        _ = try ParentSynchronizer.synchronizeDifference(difference, using: context)
        return (compared.name, other.name)
      }
      #expect(names.0 == "updated")
      #expect(names.1 == "other")
    }

    /// A selector miss used to hit `assertionFailure()` in debug and was skipped silently in
    /// release.
    @Test(arguments: DatabaseKind.allCases)
    internal func missingUpdateTargetThrows(kind: DatabaseKind) async throws {
      let container = try DatabaseKind.makeContainer(for: Parent.self, Child.self)
      let database = kind.makeDatabase(modelContainer: container)
      let keptID = UUID()
      try await Self.seed([keptID], in: database)

      let hasChanges = try await database.withModelContext { context in
        let kept = try #require(try context.fetch(FetchDescriptor<Parent>()).first)
        let difference = Difference(
          inserts: [ParentData(id: UUID())],
          modelsToDelete: [Model(kept)],
          updates: [ParentData(id: UUID(), name: "missing")]
        )
        #expect(throws: QueryError<Parent>.self) {
          _ = try ParentSynchronizer.synchronizeDifference(difference, using: context)
        }
        return context.hasChanges
      }
      #expect(hasChanges == false)
      #expect(try ModelContext(container).fetchCount(FetchDescriptor<Parent>()) == 1)
    }

    @Test(arguments: DatabaseKind.allCases)
    internal func deletedUpdateTargetThrows(kind: DatabaseKind) async throws {
      let container = try DatabaseKind.makeContainer(for: Parent.self, Child.self)
      let database = kind.makeDatabase(modelContainer: container)
      let id = UUID()
      try await Self.seed([id], in: database)

      try await database.withModelContext { context in
        let parents = try context.fetch(FetchDescriptor<Parent>())
        let difference = Difference(
          persistentModels: parents,
          data: [ParentData(id: id, name: "updated")],
          persistentModelKeyPath: \.id,
          dataKeyPath: \.id
        )

        let otherContext = ModelContext(context.container)
        try otherContext.delete(model: Parent.self)
        try otherContext.save()

        #expect(throws: QueryError<Parent>.self) {
          _ = try ParentSynchronizer.synchronizeDifference(difference, using: context)
        }
      }
    }
  #endif
}
