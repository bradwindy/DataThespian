import Foundation
import Testing

@testable import DataThespian

#if canImport(SwiftData)
  import SwiftData
#endif

@Suite(.enabled(if: swiftDataIsAvailable()))
internal struct BasicDatabaseTests {
  @Test internal func withModelContext() async throws {
    #if canImport(SwiftData)
      let database = try TestingDatabase(for: Parent.self, Child.self)
      let parentID = UUID()
      try await database.withModelContext { context in
        context.insert(Parent(id: parentID))
        try context.save()
      }

      let parentIDs = try await database.fetch(for: .all(Parent.self)) { parents in
        parents.map(\.id)
      }

      #expect(parentIDs == [parentID])
    #endif
  }

  @Test internal func testInsertAndDelete() async throws {
    #if canImport(SwiftData)
      let database = try TestingDatabase(for: Parent.self, Child.self)
      let parentID = UUID()

      // Test insert
      try await database.withModelContext { context in
        context.insert(Parent(id: parentID))
        try context.save()
      }

      // Verify insert
      let initialCount = try await database.fetch(for: .all(Parent.self)) { parents in
        parents.count
      }
      #expect(initialCount == 1)

      // Test delete using predicate
      try await database.delete(
        .predicate(
          #Predicate<Parent> { parent in
            parent.id == parentID
          }
        )
      )

      // Verify delete
      let finalCount = try await database.fetch(for: .all(Parent.self)) { parents in
        parents.count
      }
      #expect(finalCount == 0)
    #endif
  }

  @Test internal func testDeleteAll() async throws {
    #if canImport(SwiftData)
      let database = try TestingDatabase(for: Parent.self, Child.self)

      // Insert multiple parents
      try await database.withModelContext { context in
        for _ in 0..<5 {
          context.insert(Parent(id: UUID()))
        }
        try context.save()
      }

      // Delete all parents
      try await database.delete(.all(Parent.self))

      // Verify all parents were deleted
      let parentCount = try await database.fetch(for: .all(Parent.self)) { parents in
        parents.count
      }
      #expect(parentCount == 0)
    #endif
  }

  /// `withModelContext` requires a `Sendable` result. Returning a `Sendable` snapshot through
  /// `BackgroundDatabase` and through `any Database` still works.
  ///
  /// The negative case cannot be expressed as a test: with the constraint in place,
  /// `withModelContext { $0 }` and `withModelContext { try $0.fetch(FetchDescriptor<Parent>()) }`
  /// fail to compile because `ModelContext` and `Parent` are not `Sendable`.
  @Test internal func withModelContextReturnsSendableSnapshot() async throws {
    #if canImport(SwiftData)
      let container = try ModelContainer(
        for: Parent.self, Child.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
      )
      let background = BackgroundDatabase(modelContainer: container)
      let parentIDs = [UUID(), UUID()]
      try await background.withModelContext { context in
        for id in parentIDs {
          context.insert(Parent(id: id))
        }
        try context.save()
      }

      let count = try await background.withModelContext { context in
        try context.fetchCount(FetchDescriptor<Parent>())
      }
      #expect(count == 2)

      let database: any Database = background
      let ids = try await database.withModelContext { context in
        try context.fetch(FetchDescriptor<Parent>()).map(\.id)
      }
      #expect(Set(ids) == Set(parentIDs))
    #endif
  }
}
