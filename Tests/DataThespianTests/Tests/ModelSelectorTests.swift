//
//  ModelSelectorTests.swift
//  DataThespian
//

import Foundation
import Testing

@testable import DataThespian

#if canImport(SwiftData)
  import SwiftData
#endif

/// `.model` lookups must resolve unsaved inserts and must return `nil` (never a placeholder)
/// for rows that are gone, the same way on every `Database`.
@Suite(.enabled(if: swiftDataIsAvailable()))
internal struct ModelSelectorTests {
  #if canImport(SwiftData)
    @Test(arguments: DatabaseKind.allCases)
    internal func unsavedInsertResolvesByModel(kind: DatabaseKind) async throws {
      let container = try DatabaseKind.makeContainer(for: Parent.self, Child.self)
      let database = kind.makeDatabase(modelContainer: container)
      let parentID = UUID()

      let model = await database.insert { Parent(id: parentID) }

      let fetchedID = try await database.get(for: .model(model)) { $0.id }
      #expect(fetchedID == parentID)
      let found = try await database.getOptional(for: .model(model))
      #expect(found?.persistentIdentifier == model.persistentIdentifier)
    }

    @Test(arguments: DatabaseKind.allCases)
    internal func insertIfWithTransformResolvesUnsavedInsert(kind: DatabaseKind) async throws {
      let container = try DatabaseKind.makeContainer(for: Parent.self, Child.self)
      let database = kind.makeDatabase(modelContainer: container)
      let parentID = UUID()

      let insertedID = try await database.insertIf(
        { Parent(id: parentID) },
        notExist: { parent in
          let id = parent.id
          return .predicate(#Predicate<Parent> { $0.id == id })
        },
        with: { $0.id }
      )
      #expect(insertedID == parentID)
    }

    @Test(arguments: DatabaseKind.allCases)
    internal func savedModelResolvesByModel(kind: DatabaseKind) async throws {
      let container = try DatabaseKind.makeContainer(for: Parent.self, Child.self)
      let database = kind.makeDatabase(modelContainer: container)
      let parentID = UUID()
      _ = await database.insert { Parent(id: parentID) }
      try await database.save()

      let models = try await database.fetch(for: .all(Parent.self))
      let model = try #require(models.first)
      let fetchedID = try await database.get(for: .model(model)) { $0.id }
      #expect(fetchedID == parentID)
    }

    @Test(arguments: DatabaseKind.allCases)
    internal func updateByModelIsSaved(kind: DatabaseKind) async throws {
      let container = try DatabaseKind.makeContainer(for: Parent.self, Child.self)
      let database = kind.makeDatabase(modelContainer: container)
      let model = try await database.insertAndSave { Parent(id: UUID()) }

      try await database.update(for: .model(model)) { $0.name = "updated" }
      try await database.save()

      let names = try ModelContext(container).fetch(FetchDescriptor<Parent>()).map(\.name)
      #expect(names == ["updated"])
    }

    @Test(arguments: DatabaseKind.allCases)
    internal func modelDeletedInSameContextResolvesToNil(kind: DatabaseKind) async throws {
      let container = try DatabaseKind.makeContainer(for: Parent.self, Child.self)
      let database = kind.makeDatabase(modelContainer: container)
      _ = await database.insert { Parent(id: UUID()) }
      try await database.save()
      let model = try #require(try await database.fetch(for: .all(Parent.self)).first)

      try await database.delete(.model(model))
      // Deleted but not yet saved.
      #expect(try await database.getOptional(for: .model(model)) { $0 != nil } == false)

      try await database.save()
      #expect(try await database.getOptional(for: .model(model)) { $0 != nil } == false)
      await #expect(throws: QueryError<Parent>.self) {
        try await database.get(for: .model(model))
      }

      // Deleting it again is a no-op and the next save succeeds.
      try await database.delete(.model(model))
      try await database.save()
      #expect(try await database.fetch(for: .all(Parent.self)) { $0.count } == 0)
    }

    @Test(arguments: DatabaseKind.allCases)
    internal func modelDeletedByAnotherContextResolvesToNil(kind: DatabaseKind) async throws {
      let container = try DatabaseKind.makeContainer(for: Parent.self, Child.self)
      let database = kind.makeDatabase(modelContainer: container)
      _ = await database.insert { Parent(id: UUID()) }
      try await database.save()
      // Fetching registers the instance in the database's context.
      let model = try #require(try await database.fetch(for: .all(Parent.self)).first)
      #expect(try await database.getOptional(for: .model(model)) { $0 != nil } == true)

      let otherContext = ModelContext(container)
      try otherContext.delete(model: Parent.self)
      try otherContext.save()

      // Before the fix the registered (stale) instance or a model(for:) placeholder came back,
      // and reading any property of it trapped.
      #expect(try await database.getOptional(for: .model(model)) { $0 != nil } == false)
      await #expect(throws: QueryError<Parent>.self) {
        try await database.get(for: .model(model)) { $0.id }
      }
      await #expect(throws: QueryError<Parent>.self) {
        try await database.update(for: .model(model)) { $0.id = UUID() }
      }
    }

    @Test(arguments: DatabaseKind.allCases)
    internal func modelFromFreshContextForDeletedRowResolvesToNil(kind: DatabaseKind) async throws {
      let container = try DatabaseKind.makeContainer(for: Parent.self, Child.self)
      let writer = kind.makeDatabase(modelContainer: container)
      _ = await writer.insert { Parent(id: UUID()) }
      try await writer.save()
      let model = try #require(try await writer.fetch(for: .all(Parent.self)).first)
      try await writer.delete(.all(Parent.self))
      try await writer.save()

      // A database whose context never registered the instance.
      let reader = kind.makeDatabase(modelContainer: container)
      #expect(try await reader.getOptional(for: .model(model)) { $0 != nil } == false)
      await #expect(throws: QueryError<Parent>.self) {
        try await reader.get(for: .model(model))
      }

      let context = ModelContext(container)
      #expect(try context.getOptional(model) == nil)
    }
  #endif
}
