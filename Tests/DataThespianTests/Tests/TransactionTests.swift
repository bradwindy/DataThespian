//
//  TransactionTests.swift
//  DataThespian
//

import Foundation
import Testing

@testable import DataThespian

#if canImport(SwiftData)
  import SwiftData
#endif

@Suite(.enabled(if: swiftDataIsAvailable()))
internal struct TransactionTests {
  private struct TransactionFailure: Error {}

  #if canImport(SwiftData)
    /// A transaction whose block throws used to leave its changes pending in the context,
    /// where the next unrelated `save()` committed them.
    @Test(arguments: DatabaseKind.allCases)
    internal func failedTransactionLeavesNothingToSave(kind: DatabaseKind) async throws {
      let container = try DatabaseKind.makeContainer(for: Parent.self, Child.self)
      let database = kind.makeDatabase(modelContainer: container)

      await #expect(throws: TransactionFailure.self) {
        try await database.transaction { context in
          context.insert(Parent(id: UUID()))
          throw TransactionFailure()
        }
      }

      let hasChanges = await database.withModelContext { $0.hasChanges }
      #expect(hasChanges == false)

      try await database.save()
      let count = try await database.fetch(for: .all(Parent.self)) { $0.count }
      #expect(count == 0)
    }

    /// Another caller's unsaved insert shares the database's context. A failed transaction
    /// must discard only its own insert, not roll that pending work back with it.
    @Test(arguments: DatabaseKind.allCases)
    internal func failedTransactionKeepsOtherPendingChanges(kind: DatabaseKind) async throws {
      let container = try DatabaseKind.makeContainer(for: Parent.self, Child.self)
      let database = kind.makeDatabase(modelContainer: container)
      let pendingID = UUID()

      _ = await database.insert { Parent(id: pendingID) }
      // The transaction must start on a dirty context for this to test anything.
      let dirtyOnEntry = await database.withModelContext { $0.hasChanges }
      #expect(dirtyOnEntry == true)

      await #expect(throws: TransactionFailure.self) {
        try await database.transaction { context in
          context.insert(Parent(id: UUID()))
          throw TransactionFailure()
        }
      }

      try await database.save()

      let stored = try ModelContext(container).fetch(FetchDescriptor<Parent>()).map(\.id)
      #expect(stored == [pendingID])
    }

    @Test(arguments: DatabaseKind.allCases)
    internal func successfulTransactionSaves(kind: DatabaseKind) async throws {
      let container = try DatabaseKind.makeContainer(for: Parent.self, Child.self)
      let database = kind.makeDatabase(modelContainer: container)

      try await database.transaction { context in
        context.insert(Parent(id: UUID()))
        context.insert(Parent(id: UUID()))
      }

      // Read through a separate context: the rows must be in the store, not just pending.
      let count = try ModelContext(container).fetchCount(FetchDescriptor<Parent>())
      #expect(count == 2)
    }

    @Test(arguments: DatabaseKind.allCases)
    internal func deleteAllRemovesEveryType(kind: DatabaseKind) async throws {
      let container = try DatabaseKind.makeContainer(for: Parent.self, Child.self)
      let database = kind.makeDatabase(modelContainer: container)
      try await database.withModelContext { context in
        context.insert(Parent(id: UUID()))
        context.insert(Child(id: UUID()))
        try context.save()
      }

      try await database.deleteAll(of: [Parent.self, Child.self])

      let verify = ModelContext(container)
      #expect(try verify.fetchCount(FetchDescriptor<Parent>()) == 0)
      #expect(try verify.fetchCount(FetchDescriptor<Child>()) == 0)
    }
  #endif
}
