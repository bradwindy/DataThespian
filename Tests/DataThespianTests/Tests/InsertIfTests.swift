//
//  InsertIfTests.swift
//  DataThespian
//

import Foundation
import Testing
import os

@testable import DataThespian

#if canImport(SwiftData)
  import SwiftData
#endif

@Suite(.enabled(if: swiftDataIsAvailable()))
internal struct InsertIfTests {
  #if canImport(SwiftData)
    private static func selector(for parent: Parent) -> DataThespian.Selector<Parent>.Get {
      let id = parent.id
      return .predicate(#Predicate<Parent> { $0.id == id })
    }

    /// The existence check and the insert used to be two separate actor hops, so concurrent
    /// callers could both see nothing and both insert.
    @Test(arguments: DatabaseKind.allCases)
    internal func concurrentInsertIfInsertsOnce(kind: DatabaseKind) async throws {
      let container = try DatabaseKind.makeContainer(for: Parent.self, Child.self)
      let database = kind.makeDatabase(modelContainer: container)
      let parentID = UUID()

      try await withThrowingTaskGroup(of: UUID.self) { group in
        for _ in 0..<20 {
          group.addTask {
            try await database.insertIf(
              { Parent(id: parentID) },
              notExist: { Self.selector(for: $0) },
              with: { $0.id }
            )
          }
        }
        for try await id in group {
          #expect(id == parentID)
        }
      }
      try await database.save()

      let count = try await database.fetch(for: .all(Parent.self)) { $0.count }
      #expect(count == 1)
    }

    /// The factory used to run twice: once off the database to build the selector and again
    /// for the insert, so a generated key checked one instance and inserted another.
    @Test(arguments: DatabaseKind.allCases)
    internal func insertIfCallsFactoryOnce(kind: DatabaseKind) async throws {
      let container = try DatabaseKind.makeContainer(for: Parent.self, Child.self)
      let database = kind.makeDatabase(modelContainer: container)
      let calls = OSAllocatedUnfairLock(initialState: 0)

      try await database.insertIf(
        {
          calls.withLock { $0 += 1 }
          return Parent(id: UUID())
        },
        notExist: { Self.selector(for: $0) }
      )
      #expect(calls.withLock { $0 } == 1)

      try await database.save()
      let ids = try await database.fetch(for: .all(Parent.self)) { $0.map(\.id) }
      #expect(ids.count == 1)
    }

    @Test(arguments: DatabaseKind.allCases)
    internal func insertIfReturnsExistingModel(kind: DatabaseKind) async throws {
      let container = try DatabaseKind.makeContainer(for: Parent.self, Child.self)
      let database = kind.makeDatabase(modelContainer: container)
      let parentID = UUID()
      _ = await database.insert { Parent(id: parentID) }
      try await database.save()
      let existing = try #require(
        try await database.getOptional(for: .predicate(#Predicate<Parent> { $0.id == parentID }))
      )

      let result = try await database.insertIf(
        { Parent(id: parentID) },
        notExist: { Self.selector(for: $0) }
      )
      #expect(result.persistentIdentifier == existing.persistentIdentifier)

      try await database.save()
      let count = try await database.fetch(for: .all(Parent.self)) { $0.count }
      #expect(count == 1)
    }
  #endif
}
