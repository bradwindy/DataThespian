//
//  InsertAndSaveTests.swift
//  DataThespian
//

import Foundation
import Testing

@testable import DataThespian

#if canImport(SwiftData)
  import SwiftData
#endif

/// `insert(_:)` returns a `Model` built before any save, so it holds a temporary identifier
/// that stops resolving once the context saves. `insertAndSave(_:)` returns one that lasts.
@Suite(.enabled(if: swiftDataIsAvailable()))
internal struct InsertAndSaveTests {
  #if canImport(SwiftData)
    @Test(arguments: DatabaseKind.allCases)
    internal func insertAndSaveReturnsAPermanentModel(kind: DatabaseKind) async throws {
      let container = try DatabaseKind.makeContainer(for: Parent.self, Child.self)
      let database = kind.makeDatabase(modelContainer: container)
      let parentID = UUID()

      let model = try await database.insertAndSave { Parent(id: parentID) }

      #expect(try await database.get(for: .model(model)) { $0.id } == parentID)
      // A second database on the same store has never seen the temporary identifier.
      let other = kind.makeDatabase(modelContainer: container)
      #expect(try await other.get(for: .model(model)) { $0.id } == parentID)
      #expect(try ModelContext(container).fetchCount(FetchDescriptor<Parent>()) == 1)
    }

    @Test(arguments: DatabaseKind.allCases)
    internal func insertAndSaveCommitsOtherPendingChanges(kind: DatabaseKind) async throws {
      let container = try DatabaseKind.makeContainer(for: Parent.self, Child.self)
      let database = kind.makeDatabase(modelContainer: container)
      _ = await database.insert { Child(id: UUID()) }

      _ = try await database.insertAndSave { Parent(id: UUID()) }

      let check = ModelContext(container)
      #expect(try check.fetchCount(FetchDescriptor<Child>()) == 1)
      #expect(try check.fetchCount(FetchDescriptor<Parent>()) == 1)
    }
  #endif
}
