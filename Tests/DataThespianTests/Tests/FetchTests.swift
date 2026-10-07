import Foundation
import Testing

@testable import DataThespian

#if canImport(SwiftData)
  import SwiftData
#endif

/// Each case covers a different `Queryable` path, on every `Database` implementation.
@Suite(.enabled(if: swiftDataIsAvailable()))
internal struct FetchTests {
  #if canImport(SwiftData)
    private static func makeDatabase(
      _ kind: DatabaseKind, names: [String] = []
    ) async throws -> (any Database, [UUID]) {
      let container = try DatabaseKind.makeContainer(for: Parent.self, Child.self)
      let database = kind.makeDatabase(modelContainer: container)
      let ids = names.map { _ in UUID() }
      let seeds = Array(zip(ids, names))
      try await database.withModelContext { context in
        for (id, name) in seeds {
          let parent = Parent(id: id)
          parent.name = name
          context.insert(parent)
        }
        try context.save()
      }
      return (database, ids)
    }

    @Test(arguments: DatabaseKind.allCases)
    internal func testFetchAll(kind: DatabaseKind) async throws {
      let (database, parentIDs) = try await Self.makeDatabase(kind, names: ["a", "b", "c"])

      let fetchedIDs = try await database.fetch(for: .all(Parent.self)) { parents in
        parents.map(\.id)
      }

      #expect(fetchedIDs.sorted() == parentIDs.sorted())
    }

    @Test(arguments: DatabaseKind.allCases)
    internal func testFetchByPredicate(kind: DatabaseKind) async throws {
      let (database, parentIDs) = try await Self.makeDatabase(kind, names: ["a", "b"])
      let parentID = parentIDs[1]

      let fetchedName = try await database.getOptional(
        for: .predicate(#Predicate<Parent> { $0.id == parentID })
      ) { parent in
        parent?.name
      }

      #expect(fetchedName == "b")
    }

    @Test(arguments: DatabaseKind.allCases)
    internal func testFetchMissingIDReturnsNil(kind: DatabaseKind) async throws {
      let (database, _) = try await Self.makeDatabase(kind, names: ["a"])
      let missingID = UUID()

      let fetched = try await database.getOptional(
        for: .predicate(#Predicate<Parent> { $0.id == missingID })
      )

      #expect(fetched == nil)
    }

    @Test(arguments: DatabaseKind.allCases)
    internal func testFetchByIDs(kind: DatabaseKind) async throws {
      let (database, parentIDs) = try await Self.makeDatabase(kind, names: ["a", "b", "c", "d"])
      let wanted = Array(parentIDs.prefix(3))

      let fetchedIDs = try await database.fetch(
        for: .descriptor(predicate: #Predicate<Parent> { wanted.contains($0.id) })
      ) { parents in
        parents.map(\.id)
      }

      #expect(fetchedIDs.sorted() == wanted.sorted())
    }

    @Test(arguments: DatabaseKind.allCases)
    internal func testFetchSortedWithLimit(kind: DatabaseKind) async throws {
      let (database, _) = try await Self.makeDatabase(kind, names: ["c", "a", "d", "b"])

      let names = try await database.fetch(
        for: .descriptor(sortBy: [SortDescriptor(\Parent.name)], fetchLimit: 2)
      ) { parents in
        parents.map(\.name)
      }

      #expect(names == ["a", "b"])
    }

    @Test(arguments: DatabaseKind.allCases)
    internal func testUpdateByPredicateIsSaved(kind: DatabaseKind) async throws {
      let (database, parentIDs) = try await Self.makeDatabase(kind, names: ["before"])
      let parentID = parentIDs[0]

      try await database.update(for: .predicate(#Predicate<Parent> { $0.id == parentID })) {
        $0.name = "after"
      }
      try await database.save()

      let names = try await database.fetch(for: .all(Parent.self)) { $0.map(\.name) }
      #expect(names == ["after"])
    }

    @Test(arguments: DatabaseKind.allCases)
    internal func testUpdateListUpdatesEveryMatch(kind: DatabaseKind) async throws {
      let (database, _) = try await Self.makeDatabase(kind, names: ["a", "b", "c"])

      try await database.update(for: .all(Parent.self)) { parents in
        for parent in parents {
          parent.name = "renamed"
        }
      }
      try await database.save()

      let names = try await database.fetch(for: .all(Parent.self)) { $0.map(\.name) }
      #expect(names == ["renamed", "renamed", "renamed"])
    }
  #endif
}
